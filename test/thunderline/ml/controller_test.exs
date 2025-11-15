defmodule Thunderline.Thunderbolt.ML.ControllerTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.ML.Controller

  describe "initialization" do
    test "start_supervised! with valid models initializes correctly" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})
      assert Process.alive?(pid)

      state = Controller.state(pid)
      assert state.models == [:model_a, :model_b]
      assert map_size(state.parzen) == 2
      assert Map.has_key?(state.parzen, :model_a)
      assert Map.has_key?(state.parzen, :model_b)
      assert state.iteration == 0
      assert is_nil(state.last_reward)
      assert state.distance_metric == :js
      assert state.window_size == 300
    end

    test "validates non-empty models list" do
      # start_supervised returns {:error, reason} when init crashes
      result = start_supervised({Controller, models: []})
      assert {:error, {{%ArgumentError{message: msg}, _}, _}} = result
      assert msg =~ "models must be a non-empty list"
    end

    test "allows custom distance metric" do
      {:ok, pid} = start_supervised({Controller, models: [:a], distance_metric: :kl})
      state = Controller.state(pid)
      assert state.distance_metric == :kl
    end

    test "allows custom window size and SLA params" do
      {:ok, pid} =
        start_supervised({Controller, models: [:a], window_size: 500, alpha: 0.2, v: 0.1})

      state = Controller.state(pid)
      assert state.window_size == 500
    end
  end

  describe "single-step batch processing" do
    test "simple 2-class example processes successfully" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.7, 0.3]),
          model_b: Nx.tensor([0.4, 0.6])
        },
        target_dist: Nx.tensor([0.75, 0.25])
      }

      {:ok, result} = Controller.process_batch(pid, batch)

      # Check result structure
      assert result.chosen_model in [:model_a, :model_b]
      assert is_map(result.probabilities)
      assert is_map(result.distances)
      assert result.iteration == 1

      # Model A should be closer to target
      assert result.distances[:model_a] < result.distances[:model_b]
      assert result.reward_model == :model_a
    end

    test "probabilities are valid and sum to ~1.0" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.8, 0.2]),
          model_b: Nx.tensor([0.5, 0.5])
        },
        target_dist: Nx.tensor([0.9, 0.1])
      }

      {:ok, result} = Controller.process_batch(pid, batch)

      probs = result.probabilities
      assert probs[:model_a] >= 0 and probs[:model_a] <= 1
      assert probs[:model_b] >= 0 and probs[:model_b] <= 1

      sum = probs[:model_a] + probs[:model_b]
      assert_in_delta sum, 1.0, 0.01
    end

    test "iteration increments after each batch" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.7, 0.3]),
          model_b: Nx.tensor([0.6, 0.4])
        },
        target_dist: Nx.tensor([0.7, 0.3])
      }

      {:ok, result1} = Controller.process_batch(pid, batch)
      assert result1.iteration == 1

      {:ok, result2} = Controller.process_batch(pid, batch)
      assert result2.iteration == 2

      state = Controller.state(pid)
      assert state.iteration == 2
    end

    test "handles 2D batch inputs correctly" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      # Batch of 3 samples, 2 classes
      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([[0.7, 0.3], [0.8, 0.2], [0.6, 0.4]]),
          model_b: Nx.tensor([[0.4, 0.6], [0.5, 0.5], [0.3, 0.7]])
        },
        target_dist: Nx.tensor([[0.75, 0.25], [0.8, 0.2], [0.7, 0.3]])
      }

      {:ok, result} = Controller.process_batch(pid, batch)

      assert result.chosen_model in [:model_a, :model_b]
      assert is_map(result.distances)
      assert result.iteration == 1
    end
  end

  describe "multi-step learning and convergence" do
    test "20 iterations with consistent best model converges" do
      {:ok, pid} = start_supervised({Controller, models: [:good, :bad], alpha: 0.15})

      # Run 20 iterations with good model consistently better
      Enum.each(1..20, fn _ ->
        batch = %{
          model_outputs: %{
            good: Nx.tensor([0.9, 0.1]),
            bad: Nx.tensor([0.1, 0.9])
          },
          target_dist: Nx.tensor([0.95, 0.05])
        }

        {:ok, _result} = Controller.process_batch(pid, batch)
      end)

      state = Controller.state(pid)

      # Good model should have high probability (>70%)
      final_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state.sla)
      assert final_probs[:good] > 0.7
      assert state.iteration == 20
    end

    test "probabilities shift toward consistently better model" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      # Initial probabilities
      state0 = Controller.state(pid)
      initial_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state0.sla)

      # Run 10 iterations with model_a consistently better
      Enum.each(1..10, fn _ ->
        batch = %{
          model_outputs: %{
            model_a: Nx.tensor([0.85, 0.15]),
            model_b: Nx.tensor([0.3, 0.7])
          },
          target_dist: Nx.tensor([0.9, 0.1])
        }

        {:ok, _result} = Controller.process_batch(pid, batch)
      end)

      # Final probabilities
      state_final = Controller.state(pid)
      final_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state_final.sla)

      # Model A probability should increase
      assert final_probs[:model_a] > initial_probs[:model_a]
      assert final_probs[:model_b] < initial_probs[:model_b]
    end

    test "handles 3 models correctly" do
      {:ok, pid} =
        start_supervised({Controller, models: [:model_a, :model_b, :model_c], alpha: 0.1})

      # Model B is consistently best
      Enum.each(1..15, fn _ ->
        batch = %{
          model_outputs: %{
            model_a: Nx.tensor([0.5, 0.5]),
            model_b: Nx.tensor([0.8, 0.2]),
            model_c: Nx.tensor([0.3, 0.7])
          },
          target_dist: Nx.tensor([0.85, 0.15])
        }

        {:ok, result} = Controller.process_batch(pid, batch)
        assert result.reward_model == :model_b
      end)

      state = Controller.state(pid)
      final_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state.sla)

      # Model B should dominate
      assert final_probs[:model_b] > final_probs[:model_a]
      assert final_probs[:model_b] > final_probs[:model_c]
    end
  end

  describe "error handling" do
    test "missing model output returns error" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b, :model_c]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.5, 0.5])
          # Missing :model_b and :model_c
        },
        target_dist: Nx.tensor([0.5, 0.5])
      }

      # Controller returns list of ALL missing models
      assert {:error, {:missing_model_output, missing_models}} =
               Controller.process_batch(pid, batch)

      assert is_list(missing_models)
      assert Enum.sort(missing_models) == [:model_b, :model_c]

      # State should be unchanged
      state = Controller.state(pid)
      assert state.iteration == 0
    end

    test "shape mismatch between outputs returns error" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.5, 0.5]),
          # Wrong shape - 3 classes instead of 2
          model_b: Nx.tensor([0.3, 0.3, 0.4])
        },
        target_dist: Nx.tensor([0.5, 0.5])
      }

      assert {:error, {:shape_mismatch, :model_b, _, _}} =
               Controller.process_batch(pid, batch)

      # State should be unchanged
      state = Controller.state(pid)
      assert state.iteration == 0
    end

    test "invalid target (not a tensor) returns error" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.5, 0.5])
        },
        # Invalid - should be tensor
        target_dist: [0.5, 0.5]
      }

      assert {:error, :invalid_target} = Controller.process_batch(pid, batch)

      state = Controller.state(pid)
      assert state.iteration == 0
    end

    test "invalid target shape (3D tensor) returns error" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a]})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.5, 0.5])
        },
        # Invalid - 3D tensor
        target_dist: Nx.tensor([[[0.5, 0.5]]])
      }

      assert {:error, {:invalid_target_shape, _}} = Controller.process_batch(pid, batch)

      state = Controller.state(pid)
      assert state.iteration == 0
    end

    test "invalid batch format returns error" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a]})

      # Missing required keys
      invalid_batch = %{some_other_key: "value"}

      assert {:error, :invalid_batch_format} = Controller.process_batch(pid, invalid_batch)

      state = Controller.state(pid)
      assert state.iteration == 0
    end

    test "state unchanged on any error" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      # Successful batch first
      good_batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.7, 0.3]),
          model_b: Nx.tensor([0.6, 0.4])
        },
        target_dist: Nx.tensor([0.7, 0.3])
      }

      {:ok, _result} = Controller.process_batch(pid, good_batch)
      state_after_good = Controller.state(pid)
      assert state_after_good.iteration == 1

      # Now send bad batch
      bad_batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.5, 0.5])
          # Missing model_b
        },
        target_dist: Nx.tensor([0.5, 0.5])
      }

      {:error, _reason} = Controller.process_batch(pid, bad_batch)

      # State should still be at iteration 1
      state_after_bad = Controller.state(pid)
      assert state_after_bad.iteration == 1
      assert state_after_bad.sla == state_after_good.sla
    end
  end

  describe "snapshot and restore" do
    test "round-trip preserves state" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      # Process some batches
      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.7, 0.3]),
          model_b: Nx.tensor([0.4, 0.6])
        },
        target_dist: Nx.tensor([0.8, 0.2])
      }

      Enum.each(1..5, fn _ ->
        Controller.process_batch(pid, batch)
      end)

      # Get snapshot
      snap = Controller.snapshot(pid)

      # Restore from snapshot
      restored_state = Controller.from_snapshot(snap)

      # Compare states
      original_state = Controller.state(pid)
      assert restored_state.iteration == original_state.iteration
      assert restored_state.models == original_state.models
      assert restored_state.distance_metric == original_state.distance_metric
      assert restored_state.window_size == original_state.window_size
    end

    test "SLA probabilities identical after restore" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b]})

      # Run some iterations
      Enum.each(1..10, fn _ ->
        batch = %{
          model_outputs: %{
            model_a: Nx.tensor([0.8, 0.2]),
            model_b: Nx.tensor([0.3, 0.7])
          },
          target_dist: Nx.tensor([0.85, 0.15])
        }

        Controller.process_batch(pid, batch)
      end)

      # Snapshot & restore
      snap = Controller.snapshot(pid)
      restored_state = Controller.from_snapshot(snap)
      original_state = Controller.state(pid)

      # SLA probabilities should match
      original_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(original_state.sla)
      restored_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(restored_state.sla)

      assert_in_delta original_probs[:model_a], restored_probs[:model_a], 0.001
      assert_in_delta original_probs[:model_b], restored_probs[:model_b], 0.001
    end

    test "snapshot contains all required fields" do
      {:ok, pid} = start_supervised({Controller, models: [:a, :b]})

      snap = Controller.snapshot(pid)

      assert is_list(snap.models)
      assert is_map(snap.parzen)
      assert is_map(snap.sla)
      assert snap.distance_metric in [:js, :kl, :hellinger, :cross_entropy]
      assert is_integer(snap.window_size)
      assert is_integer(snap.iteration)
      assert is_map(snap.meta)
    end
  end

  describe "different distance metrics" do
    test "KL divergence metric works correctly" do
      {:ok, pid} =
        start_supervised({Controller, models: [:model_a, :model_b], distance_metric: :kl})

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.7, 0.3]),
          model_b: Nx.tensor([0.5, 0.5])
        },
        target_dist: Nx.tensor([0.75, 0.25])
      }

      {:ok, result} = Controller.process_batch(pid, batch)
      assert is_float(result.distances[:model_a])
      assert is_float(result.distances[:model_b])
    end

    test "Hellinger distance metric works correctly" do
      {:ok, pid} =
        start_supervised(
          {Controller, models: [:model_a, :model_b], distance_metric: :hellinger}
        )

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.8, 0.2]),
          model_b: Nx.tensor([0.6, 0.4])
        },
        target_dist: Nx.tensor([0.85, 0.15])
      }

      {:ok, result} = Controller.process_batch(pid, batch)
      assert result.distances[:model_a] >= 0
      assert result.distances[:model_b] >= 0
    end

    test "Cross-entropy metric works correctly" do
      {:ok, pid} =
        start_supervised(
          {Controller, models: [:model_a], distance_metric: :cross_entropy}
        )

      batch = %{
        model_outputs: %{
          model_a: Nx.tensor([0.9, 0.1])
        },
        target_dist: Nx.tensor([0.95, 0.05])
      }

      {:ok, result} = Controller.process_batch(pid, batch)
      assert is_float(result.distances[:model_a])
    end
  end

  describe "integration scenarios" do
    test "realistic 3-model scenario with varying performance" do
      {:ok, pid} =
        start_supervised(
          {Controller, models: [:baseline, :improved, :experimental], alpha: 0.12}
        )

      # First 10 iterations: baseline is best
      Enum.each(1..10, fn _ ->
        batch = %{
          model_outputs: %{
            baseline: Nx.tensor([0.7, 0.3]),
            improved: Nx.tensor([0.5, 0.5]),
            experimental: Nx.tensor([0.4, 0.6])
          },
          target_dist: Nx.tensor([0.75, 0.25])
        }

        {:ok, _result} = Controller.process_batch(pid, batch)
      end)

      state_mid = Controller.state(pid)
      mid_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state_mid.sla)
      # Baseline should be favored
      assert mid_probs[:baseline] > mid_probs[:improved]

      # Next 10 iterations: experimental becomes best
      Enum.each(11..20, fn _ ->
        batch = %{
          model_outputs: %{
            baseline: Nx.tensor([0.5, 0.5]),
            improved: Nx.tensor([0.6, 0.4]),
            experimental: Nx.tensor([0.85, 0.15])
          },
          target_dist: Nx.tensor([0.9, 0.1])
        }

        {:ok, _result} = Controller.process_batch(pid, batch)
      end)

      state_final = Controller.state(pid)
      final_probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state_final.sla)

      # Experimental should now be favored
      assert final_probs[:experimental] > final_probs[:baseline]
      assert state_final.iteration == 20
    end

    test "convergence with alternating best models" do
      {:ok, pid} = start_supervised({Controller, models: [:model_a, :model_b], alpha: 0.1})

      # Alternate which model is better
      Enum.each(1..20, fn i ->
        if rem(i, 2) == 0 do
          batch = %{
            model_outputs: %{
              model_a: Nx.tensor([0.8, 0.2]),
              model_b: Nx.tensor([0.4, 0.6])
            },
            target_dist: Nx.tensor([0.85, 0.15])
          }

          {:ok, _result} = Controller.process_batch(pid, batch)
        else
          batch = %{
            model_outputs: %{
              model_a: Nx.tensor([0.3, 0.7]),
              model_b: Nx.tensor([0.85, 0.15])
            },
            target_dist: Nx.tensor([0.9, 0.1])
          }

          {:ok, _result} = Controller.process_batch(pid, batch)
        end
      end)

      state = Controller.state(pid)
      probs = Thunderline.Thunderbolt.ML.SLASelector.probabilities(state.sla)

      # With alternating performance, probabilities should be relatively balanced
      assert probs[:model_a] > 0.3
      assert probs[:model_b] > 0.3
      assert state.iteration == 20
    end
  end
end
