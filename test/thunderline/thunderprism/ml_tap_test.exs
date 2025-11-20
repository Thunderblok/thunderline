defmodule Thunderline.Thunderprism.MLTapTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderprism.{MLTap, Domain}

  setup do
    :telemetry.attach_many(
      "mltap-test-handler",
      [
        [:thunderline, :thunderprism, :mltap, :log_start],
        [:thunderline, :thunderprism, :mltap, :log_success],
        [:thunderline, :thunderprism, :mltap, :log_error]
      ],
      &__MODULE__.handle_telemetry/4,
      %{test_pid: self()}
    )

    on_exit(fn ->
      :telemetry.detach("mltap-test-handler")
    end)

    :ok
  end

  def handle_telemetry(event, measurements, metadata, config) do
    send(config.test_pid, {:telemetry, event, measurements, metadata})
  end

  describe "log_node/1" do
    test "asynchronously creates PrismNode without blocking" do
      attrs = %{
        pac_id: "test_pac",
        iteration: 42,
        chosen_model: "gpt-4",
        model_probabilities: %{"gpt-4" => 0.8, "claude" => 0.2},
        model_distances: %{"gpt-4" => 0.1, "claude" => 0.3}
      }

      # Call should return immediately with Task
      start_time = System.monotonic_time(:millisecond)
      task = MLTap.log_node(attrs)
      end_time = System.monotonic_time(:millisecond)

      # Should complete in < 10ms (non-blocking)
      assert end_time - start_time < 10
      assert %Task{} = task

      # Wait for async completion
      result = Task.await(task, 5000)
      assert {:ok, node} = result
      assert node.pac_id == "test_pac"
      assert node.iteration == 42
      assert node.chosen_model == "gpt-4"
      assert node.model_probabilities == %{"gpt-4" => 0.8, "claude" => 0.2}

      # Verify telemetry emitted
      assert_receive {:telemetry, [:thunderline, :thunderprism, :mltap, :log_start], _, _}, 500

      assert_receive {:telemetry, [:thunderline, :thunderprism, :mltap, :log_success],
                      measurements, metadata},
                     500

      assert measurements.duration_us > 0
      assert metadata.pac_id == "test_pac"
    end

    test "includes timestamp when not provided" do
      attrs = %{
        pac_id: "test_pac_2",
        iteration: 1,
        chosen_model: "claude-3",
        model_probabilities: %{},
        model_distances: %{}
      }

      task = MLTap.log_node(attrs)
      {:ok, node} = Task.await(task, 5000)

      assert node.timestamp != nil
    end

    test "uses provided timestamp" do
      custom_timestamp = ~U[2025-11-19 12:00:00Z]

      attrs = %{
        pac_id: "test_pac_3",
        iteration: 2,
        chosen_model: "gemini",
        model_probabilities: %{},
        model_distances: %{},
        timestamp: custom_timestamp
      }

      task = MLTap.log_node(attrs)
      {:ok, node} = Task.await(task, 5000)

      # Truncate to second precision for comparison (Postgres stores with microseconds)
      assert DateTime.truncate(node.timestamp, :second) ==
               DateTime.truncate(custom_timestamp, :second)
    end

    test "handles errors gracefully without crashing" do
      # Invalid data - missing required field
      attrs = %{
        iteration: 5,
        chosen_model: "invalid"
        # Missing pac_id (required)
      }

      # Should not crash, returns Task
      task = MLTap.log_node(attrs)
      assert %Task{} = task

      # Async task should complete with error
      result = Task.await(task, 5000)
      assert {:error, _reason} = result

      # Error telemetry emitted
      assert_receive {:telemetry, [:thunderline, :thunderprism, :mltap, :log_error], _, metadata},
                     500

      assert Map.has_key?(metadata, :error)
    end

    test "accepts meta field for additional context" do
      attrs = %{
        pac_id: "test_pac_4",
        iteration: 10,
        chosen_model: "gpt-4",
        model_probabilities: %{"gpt-4" => 1.0},
        model_distances: %{"gpt-4" => 0.0},
        meta: %{
          experiment: "baseline",
          temperature: 0.7,
          max_tokens: 1000
        }
      }

      task = MLTap.log_node(attrs)
      {:ok, node} = Task.await(task, 5000)

      assert node.meta["experiment"] == "baseline"
      assert node.meta["temperature"] == 0.7
      assert node.meta["max_tokens"] == 1000
    end

    test "concurrent log_node calls don't interfere" do
      # Spawn 10 concurrent logging tasks
      tasks =
        Enum.map(1..10, fn i ->
          MLTap.log_node(%{
            pac_id: "concurrent_pac",
            iteration: i,
            chosen_model: "model_#{i}",
            model_probabilities: %{"model_#{i}" => 1.0},
            model_distances: %{"model_#{i}" => 0.0}
          })
        end)

      # All should succeed
      results = Enum.map(tasks, &Task.await(&1, 5000))

      assert Enum.all?(results, fn
               {:ok, _node} -> true
               _ -> false
             end)

      # All nodes should be different
      node_ids = Enum.map(results, fn {:ok, node} -> node.id end)
      assert length(Enum.uniq(node_ids)) == 10
    end
  end

  describe "log_edge/1" do
    setup do
      # Create two nodes to link
      node1 =
        Domain.create_prism_node!(
          "pac_edge_test",
          1,
          "gpt-4",
          %{"gpt-4" => 0.8},
          %{"gpt-4" => 0.1},
          %{},
          DateTime.utc_now()
        )

      node2 =
        Domain.create_prism_node!(
          "pac_edge_test",
          2,
          "claude",
          %{"claude" => 0.7},
          %{"claude" => 0.2},
          %{},
          DateTime.utc_now()
        )

      %{node1: node1, node2: node2}
    end

    test "asynchronously creates PrismEdge", %{node1: n1, node2: n2} do
      attrs = %{
        from_id: n1.id,
        to_id: n2.id,
        relation_type: "sequential"
      }

      # Non-blocking
      start_time = System.monotonic_time(:millisecond)
      task = MLTap.log_edge(attrs)
      end_time = System.monotonic_time(:millisecond)

      assert end_time - start_time < 10
      assert %Task{} = task

      # Wait for completion
      {:ok, edge} = Task.await(task, 5000)
      assert edge.from_id == n1.id
      assert edge.to_id == n2.id
      assert edge.relation_type == "sequential"
    end

    test "uses default relation_type when not provided", %{node1: n1, node2: n2} do
      attrs = %{
        from_id: n1.id,
        to_id: n2.id
      }

      task = MLTap.log_edge(attrs)
      {:ok, edge} = Task.await(task, 5000)

      assert edge.relation_type == "sequential"
    end

    test "accepts custom relation_type", %{node1: n1, node2: n2} do
      attrs = %{
        from_id: n1.id,
        to_id: n2.id,
        relation_type: "fallback"
      }

      task = MLTap.log_edge(attrs)
      {:ok, edge} = Task.await(task, 5000)

      assert edge.relation_type == "fallback"
    end

    test "includes meta in edge", %{node1: n1, node2: n2} do
      attrs = %{
        from_id: n1.id,
        to_id: n2.id,
        relation_type: "retry",
        meta: %{
          retry_count: 2,
          reason: "timeout"
        }
      }

      task = MLTap.log_edge(attrs)
      {:ok, edge} = Task.await(task, 5000)

      assert edge.meta["retry_count"] == 2
      assert edge.meta["reason"] == "timeout"
    end

    test "handles errors gracefully", %{node1: n1} do
      # Invalid - to_id references non-existent node
      attrs = %{
        from_id: n1.id,
        to_id: Ash.UUID.generate()
      }

      task = MLTap.log_edge(attrs)
      result = Task.await(task, 5000)

      # Should return error without crashing
      assert {:error, _reason} = result
    end
  end

  describe "log_with_edge/2" do
    setup do
      # Create a previous node
      prev_node =
        Domain.create_prism_node!(
          "pac_with_edge",
          1,
          "gpt-4",
          %{"gpt-4" => 0.9},
          %{"gpt-4" => 0.05},
          %{},
          DateTime.utc_now()
        )

      %{prev_node: prev_node}
    end

    test "creates node and edge in sequence", %{prev_node: prev} do
      node_attrs = %{
        pac_id: "pac_with_edge",
        iteration: 2,
        chosen_model: "claude",
        model_probabilities: %{"claude" => 0.85},
        model_distances: %{"claude" => 0.08}
      }

      {:ok, task} = MLTap.log_with_edge(node_attrs, prev.id)
      {:ok, {node, edge}} = Task.await(task, 5000)

      # Node created
      assert node.pac_id == "pac_with_edge"
      assert node.iteration == 2
      assert node.chosen_model == "claude"

      # Edge created linking prev -> new node
      assert edge.from_id == prev.id
      assert edge.to_id == node.id
      assert edge.relation_type == "sequential"
    end

    test "creates only node when prev_node_id is nil" do
      node_attrs = %{
        pac_id: "pac_no_edge",
        chosen_model: "gpt-4",
        iteration: 1,
        model_probabilities: %{"gpt-4" => 0.9},
        model_distances: %{"gpt-4" => 0.05}
      }

      {:ok, task} = MLTap.log_with_edge(node_attrs, nil)
      {:ok, node} = Task.await(task, 5000)

      # Node created successfully
      assert node.pac_id == "pac_no_edge"
      assert node.iteration == 1
      assert node.chosen_model == "gpt-4"
    end

    test "handles edge creation failure gracefully", %{prev_node: prev_node} do
      node_attrs = %{
        pac_id: "pac_with_edge",
        chosen_model: "gpt-4",
        iteration: 1,
        model_probabilities: %{"gpt-4" => 0.9},
        model_distances: %{"gpt-4" => 0.05}
      }

      # With a valid prev_node_id, both node and edge should succeed
      {:ok, task} = MLTap.log_with_edge(node_attrs, prev_node.id)
      {:ok, {node, edge}} = Task.await(task, 5000)

      # Both node and edge should be created successfully
      assert node.pac_id == "pac_with_edge"
      assert edge.from_id == prev_node.id
      assert edge.to_id == node.id
      assert edge.relation_type == "sequential"
    end
  end

  describe "telemetry integration" do
    test "emits log_start event on begin" do
      attrs = %{
        pac_id: "telemetry_test",
        iteration: 1,
        chosen_model: "gpt-4",
        model_probabilities: %{},
        model_distances: %{}
      }

      task = MLTap.log_node(attrs)

      assert_receive {:telemetry, [:thunderline, :thunderprism, :mltap, :log_start], _, metadata},
                     500

      assert metadata.pac_id == "telemetry_test"

      Task.await(task, 5000)
    end

    test "emits log_success with duration on success" do
      attrs = %{
        pac_id: "telemetry_success",
        iteration: 5,
        chosen_model: "claude",
        model_probabilities: %{},
        model_distances: %{}
      }

      task = MLTap.log_node(attrs)
      Task.await(task, 5000)

      assert_receive {:telemetry, [:thunderline, :thunderprism, :mltap, :log_success],
                      measurements, metadata},
                     500

      assert measurements.duration_us > 0
      assert metadata.pac_id == "telemetry_success"
      assert Map.has_key?(metadata, :node_id)
    end

    test "emits log_error with error details on failure" do
      # Invalid attrs
      attrs = %{
        iteration: 1,
        chosen_model: "test"
        # Missing pac_id
      }

      task = MLTap.log_node(attrs)
      Task.await(task, 5000)

      assert_receive {:telemetry, [:thunderline, :thunderprism, :mltap, :log_error], measurements,
                      metadata},
                     500

      assert measurements.duration_us > 0
      assert Map.has_key?(metadata, :error)
    end
  end

  describe "integration with ModelSelectionConsumer" do
    test "typical usage pattern from consumer" do
      # Simulate consumer data
      result = %{
        chosen_model: :gpt_4,
        probabilities: %{gpt_4: 0.75, claude: 0.25},
        distances: %{gpt_4: 0.08, claude: 0.15},
        iteration: 100,
        reward_model: :gpt_4,
        correlation_id: "corr-123",
        causation_id: "cause-456"
      }

      # Consumer pattern
      task =
        MLTap.log_node(%{
          pac_id: "ml_controller",
          iteration: result.iteration,
          chosen_model: to_string(result.chosen_model),
          model_probabilities: result.probabilities,
          model_distances: result.distances,
          meta: %{
            reward_model: to_string(result.reward_model),
            correlation_id: result.correlation_id,
            causation_id: result.causation_id
          }
        })

      # Should not block consumer
      assert %Task{} = task

      # Verify node created
      {:ok, node} = Task.await(task, 5000)
      assert node.pac_id == "ml_controller"
      assert node.iteration == 100
      assert node.chosen_model == "gpt_4"
      assert node.meta["correlation_id"] == "corr-123"
    end
  end
end
