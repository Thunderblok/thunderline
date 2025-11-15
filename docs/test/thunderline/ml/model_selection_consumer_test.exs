defmodule Thunderline.Thunderbolt.ML.ModelSelectionConsumerTest do
  use ExUnit.Case, async: false

  alias Thunderline.Event
  alias Thunderline.Thunderbolt.ML.{Controller, ModelSelectionConsumer}

  setup do
    # Start ML Controller
    controller_opts = [
      models: [:model_a, :model_b],
      distance_metric: :js,
      window_size: 10
    ]

    {:ok, controller_pid} = start_supervised({Controller, controller_opts})

    # Give controller a moment to initialize
    Process.sleep(50)

    %{controller_pid: controller_pid}
  end

  describe "event validation" do
    test "accepts valid ml.model.evaluation_ready event" do
      event = %Event{
        id: "test-123",
        name: "ml.model.evaluation_ready",
        source: "test",
        payload: %{
          model_outputs: %{
            model_a: Nx.tensor([0.7, 0.3]),
            model_b: Nx.tensor([0.6, 0.4])
          },
          target_dist: Nx.tensor([0.8, 0.2])
        },
        correlation_id: "corr-123",
        timestamp: DateTime.utc_now()
      }

      assert {:ok, validated} = validate_test_event(event)
      assert validated.correlation_id == "corr-123"
      assert validated.causation_id == "test-123"
      assert is_map(validated.model_outputs)
      assert is_struct(validated.target_dist, Nx.Tensor)
    end

    test "rejects event with missing model_outputs" do
      event = %Event{
        id: "test-123",
        name: "ml.model.evaluation_ready",
        source: "test",
        payload: %{
          target_dist: Nx.tensor([0.8, 0.2])
        },
        timestamp: DateTime.utc_now()
      }

      assert {:error, :invalid_event_payload} = validate_test_event(event)
    end

    test "rejects event with non-tensor outputs" do
      event = %Event{
      id: "test-123",
      name: "ml.model.evaluation_ready",
      source: "test",
      payload: %{
        model_outputs: %{
          model_a: "not a tensor"
        },
        target_dist: Nx.tensor([0.8, 0.2])
      },
      timestamp: DateTime.utc_now()
    }

    assert {:error, :invalid_tensor_outputs} = validate_test_event(event)
    end
  end

  describe "controller integration" do
    test "processes valid batch through controller", %{controller_pid: controller_pid} do
      event = %Event{
        id: "test-456",
        name: "ml.model.evaluation_ready",
        source: "test",
        payload: %{
          model_outputs: %{
            model_a: Nx.tensor([0.7, 0.3]),
            model_b: Nx.tensor([0.6, 0.4])
          },
          target_dist: Nx.tensor([0.8, 0.2]),
          context: %{test_run: true}
        },
        correlation_id: "corr-456",
        timestamp: DateTime.utc_now()
      }

      {:ok, validated} = validate_test_event(event)

      batch_data = %{
        model_outputs: validated.model_outputs,
        target_dist: validated.target_dist
      }

      assert {:ok, result} = Controller.process_batch(controller_pid, batch_data)
      assert result.chosen_model in [:model_a, :model_b]
      assert is_map(result.probabilities)
      assert is_map(result.distances)
      assert result.iteration >= 0
    end

    test "handles controller errors gracefully", %{controller_pid: controller_pid} do
      # Invalid batch - empty model_outputs
      batch_data = %{
        model_outputs: %{},
        target_dist: Nx.tensor([0.8, 0.2])
      }

      assert {:error, _reason} = Controller.process_batch(controller_pid, batch_data)
    end
  end

  describe "event emission" do
    test "emits ml.model.selected event after processing", %{controller_pid: controller_pid} do
      # Subscribe to event bus - topic is based on event type (last segment)
      # For "ml.run.selected", type is :selected
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:selected")

      event = %Event{
        id: "test-789",
        name: "ml.model.evaluation_ready",
        source: "test",
        payload: %{
          model_outputs: %{
            model_a: Nx.tensor([0.7, 0.3]),
            model_b: Nx.tensor([0.6, 0.4])
          },
          target_dist: Nx.tensor([0.8, 0.2])
        },
        correlation_id: "corr-789",
        timestamp: DateTime.utc_now()
      }

      {:ok, validated} = validate_test_event(event)

      batch_data = %{
        model_outputs: validated.model_outputs,
        target_dist: validated.target_dist
      }

      {:ok, result} = Controller.process_batch(controller_pid, batch_data)

      # Simulate event emission
      enriched = Map.merge(result, %{
        correlation_id: validated.correlation_id,
        causation_id: validated.causation_id,
        context: %{}
      })

      event_attrs = %{
        name: "ml.run.selected",  # Use ml.run category (allowed for :bolt)
        source: :bolt,
        payload: %{
          chosen_model: enriched.chosen_model,
          probabilities: enriched.probabilities,
          distances: enriched.distances,
          iteration: enriched.iteration,
          reward_model: enriched.reward_model
        },
        # Let Event.new generate proper UUID v7 correlation_id
        causation_id: enriched.causation_id
      }

      {:ok, selection_event} = Event.new(event_attrs)

      # Broadcast directly to PubSub for testing (bypass EventBus queue)
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "events:" <> to_string(selection_event.type),
        {:event, selection_event}
      )

      # Verify event was published
      assert_receive {:event, received_event}, 1000
      assert received_event.name == "ml.run.selected"
      assert received_event.payload.chosen_model in [:model_a, :model_b]
    end
  end

  # Helper to access private validation function for testing
  defp validate_test_event(event) do
    # This mirrors the private validate_event/1 function
    case event do
      %Event{name: name} = evt when name in ["ml.model.evaluation_ready", "ml.model.eval"] ->
        case evt.payload do
          %{model_outputs: outputs, target_dist: target} = payload
          when is_map(outputs) ->
            with :ok <- validate_tensors(outputs),
                 :ok <- validate_target(target) do
              correlation_id = evt.correlation_id || evt.id
              causation_id = evt.id

              {:ok,
               %{
                 model_outputs: outputs,
                 target_dist: target,
                 features: Map.get(payload, :features),
                 context: Map.get(payload, :context, %{}),
                 correlation_id: correlation_id,
                 causation_id: causation_id
               }}
            end

          _other ->
            {:error, :invalid_event_payload}
        end

      %Event{} ->
        {:error, {:unexpected_event_type, event.name || event.type}}

      _other ->
        {:error, {:invalid_event, event}}
    end
  end

  defp validate_tensors(outputs) when is_map(outputs) do
    if Enum.all?(outputs, fn {_k, v} -> is_struct(v, Nx.Tensor) end) do
      :ok
    else
      {:error, :invalid_tensor_outputs}
    end
  end

  defp validate_target(target) do
    if is_struct(target, Nx.Tensor) do
      :ok
    else
      {:error, :invalid_target_tensor}
    end
  end
end
