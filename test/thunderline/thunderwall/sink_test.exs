defmodule Thunderline.Thunderwall.SinkTest do
  @moduledoc """
  Tests for Thunderwall Entropy Sink (HC-Ω-4).
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderwall.Sink

  describe "compute_entropy_score/2" do
    test "returns low score for fresh entities with good fitness" do
      metadata = %{
        created_at: DateTime.utc_now(),
        lambda_hat: 0.273,
        fitness: 0.8,
        lineage_depth: 5
      }

      score = Sink.compute_entropy_score(metadata)

      assert score < 0.5
    end

    test "returns high score for old entities with poor fitness" do
      old_time = DateTime.add(DateTime.utc_now(), -72, :hour)

      metadata = %{
        created_at: old_time,
        # Chaotic
        lambda_hat: 0.9,
        # Poor
        fitness: 0.1,
        # Shallow
        lineage_depth: 1
      }

      score = Sink.compute_entropy_score(metadata)

      assert score > 0.5
    end

    test "chaos factor increases score" do
      base = %{created_at: DateTime.utc_now(), fitness: 0.5, lineage_depth: 3}

      low_chaos = Map.put(base, :lambda_hat, 0.3)
      high_chaos = Map.put(base, :lambda_hat, 0.9)

      low_score = Sink.compute_entropy_score(low_chaos)
      high_score = Sink.compute_entropy_score(high_chaos)

      assert high_score > low_score
    end

    test "low fitness increases score" do
      base = %{created_at: DateTime.utc_now(), lambda_hat: 0.3, lineage_depth: 3}

      good_fitness = Map.put(base, :fitness, 0.9)
      poor_fitness = Map.put(base, :fitness, 0.1)

      good_score = Sink.compute_entropy_score(good_fitness)
      poor_score = Sink.compute_entropy_score(poor_fitness)

      assert poor_score > good_score
    end

    test "shallow lineage increases score" do
      base = %{created_at: DateTime.utc_now(), lambda_hat: 0.3, fitness: 0.5}

      deep = Map.put(base, :lineage_depth, 10)
      shallow = Map.put(base, :lineage_depth, 1)

      deep_score = Sink.compute_entropy_score(deep)
      shallow_score = Sink.compute_entropy_score(shallow)

      assert shallow_score > deep_score
    end

    test "handles missing metadata gracefully" do
      score = Sink.compute_entropy_score(%{})

      assert is_float(score)
      assert score >= 0.0
      assert score <= 1.0
    end
  end

  describe "extract_failure_pattern/1" do
    test "extracts CA run pattern" do
      entry = %{
        id: "sink_1",
        entity_type: :ca_run,
        entity_id: "run_123",
        reason: :ca_failure,
        entropy_score: 0.8,
        metadata: %{
          lambda_hat: 0.9,
          entropy: 0.85,
          config: %{grid_size: 10}
        },
        quarantined_at: DateTime.utc_now(),
        archived_at: nil,
        pattern: nil
      }

      pattern = Sink.extract_failure_pattern(entry)

      assert pattern.type == :ca_run
      assert pattern.signature.reason == :ca_failure
      assert pattern.signature.lambda_hat == 0.9
      assert pattern.frequency == 1
    end

    test "extracts Thunderbit pattern" do
      entry = %{
        id: "sink_2",
        entity_type: :thunderbit,
        entity_id: "bit_456",
        reason: :chaos_spike,
        entropy_score: 0.7,
        metadata: %{
          lambda_hat: 0.95,
          sigma_flow: 0.1,
          coord: {5, 5, 5}
        },
        quarantined_at: DateTime.utc_now(),
        archived_at: nil,
        pattern: nil
      }

      pattern = Sink.extract_failure_pattern(entry)

      assert pattern.type == :thunderbit
      assert pattern.signature.reason == :chaos_spike
      assert pattern.signature.coord == {5, 5, 5}
    end

    test "extracts trial pattern" do
      entry = %{
        id: "sink_3",
        entity_type: :trial,
        entity_id: "trial_789",
        reason: :trial_timeout,
        entropy_score: 0.9,
        metadata: %{
          params: %{lambda_modulation: 0.8, bias: 0.5},
          fitness: 0.0
        },
        quarantined_at: DateTime.utc_now(),
        archived_at: nil,
        pattern: nil
      }

      pattern = Sink.extract_failure_pattern(entry)

      assert pattern.type == :trial
      assert pattern.signature.reason == :trial_timeout
      assert pattern.signature.fitness == 0.0
    end
  end

  describe "GenServer operations" do
    setup do
      server_name = :"Sink_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Sink.start_link(
          name: server_name,
          gc_interval_ms: 60_000
        )

      {:ok, pid: pid, server: server_name}
    end

    test "quarantines CA run", %{server: server} do
      {:ok, entry} =
        Sink.quarantine_ca_run(
          "run_test_1",
          :ca_failure,
          %{lambda_hat: 0.9, entropy: 0.8},
          server: server
        )

      assert entry.entity_type == :ca_run
      assert entry.entity_id == "run_test_1"
      assert entry.reason == :ca_failure
      assert entry.entropy_score > 0
      assert entry.archived_at == nil
    end

    test "quarantines Thunderbit", %{server: server} do
      {:ok, entry} =
        Sink.quarantine_thunderbit(
          "bit_test_1",
          %{lambda_hat: 0.95, sigma_flow: 0.05},
          server: server
        )

      assert entry.entity_type == :thunderbit
      assert entry.reason == :chaos_spike
    end

    test "archives PAC lineage", %{server: server} do
      lineage = [
        %{fitness: 0.3, lambda_hat: 0.4},
        %{fitness: 0.35, lambda_hat: 0.45},
        %{fitness: 0.32, lambda_hat: 0.5}
      ]

      {:ok, entry} = Sink.archive_pac_lineage("pac_test_1", lineage, %{}, server: server)

      assert entry.entity_type == :lineage
      assert entry.archived_at != nil
      assert entry.pattern != nil
      assert entry.metadata.lineage_depth == 3
    end

    test "lists quarantine entries", %{server: server} do
      Sink.quarantine_ca_run("run_list_1", :ca_failure, %{}, server: server)
      Sink.quarantine_ca_run("run_list_2", :nan_detected, %{}, server: server)

      entries = Sink.list_quarantine(server: server)

      assert length(entries) == 2
    end

    test "lists archive entries", %{server: server} do
      Sink.archive_pac_lineage("pac_archive_1", [%{fitness: 0.1}], %{}, server: server)
      Sink.archive_pac_lineage("pac_archive_2", [%{fitness: 0.2}], %{}, server: server)

      entries = Sink.list_archive(server: server)

      assert length(entries) == 2
    end

    test "returns stats", %{server: server} do
      Sink.quarantine_ca_run("run_stats_1", :ca_failure, %{}, server: server)
      Sink.archive_pac_lineage("pac_stats_1", [], %{}, server: server)

      stats = Sink.stats(server: server)

      assert stats.quarantined_total >= 1
      assert stats.archived_total >= 1
      assert Map.has_key?(stats, :quarantine_count)
      assert Map.has_key?(stats, :archive_count)
    end

    test "runs GC", %{server: server} do
      {:ok, collected} = Sink.run_gc(server: server)

      assert is_integer(collected)
      assert collected >= 0
    end

    test "restores from quarantine", %{server: server} do
      {:ok, entry} = Sink.quarantine_ca_run("run_restore_1", :ca_failure, %{}, server: server)

      {:ok, restored} = Sink.restore(entry.id, server: server)

      assert restored.entity_id == "run_restore_1"

      # Should no longer be in quarantine
      entries = Sink.list_quarantine(server: server)
      assert Enum.find(entries, &(&1.id == entry.id)) == nil
    end

    test "restore returns error for non-existent entry", %{server: server} do
      result = Sink.restore("nonexistent_id", server: server)

      assert result == {:error, :not_found}
    end

    test "lists patterns after archiving", %{server: server} do
      Sink.archive_pac_lineage("pac_pattern_1", [%{fitness: 0.1}], %{}, server: server)

      patterns = Sink.list_patterns(server: server)

      assert length(patterns) >= 1
      [pattern | _] = patterns
      assert Map.has_key?(pattern, :type)
      assert Map.has_key?(pattern, :frequency)
    end
  end

  describe "edge cases" do
    setup do
      server_name = :"Sink_edge_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Sink.start_link(
          name: server_name,
          gc_interval_ms: 60_000
        )

      {:ok, pid: pid, server: server_name}
    end

    test "handles empty lineage", %{server: server} do
      {:ok, entry} = Sink.archive_pac_lineage("pac_empty", [], %{}, server: server)

      assert entry.metadata.lineage_depth == 0
    end

    test "handles quarantine with minimal metadata", %{server: server} do
      {:ok, entry} = Sink.quarantine_trial("trial_min", :trial_timeout, %{}, server: server)

      assert entry.entity_type == :trial
      assert is_float(entry.entropy_score)
    end
  end
end
