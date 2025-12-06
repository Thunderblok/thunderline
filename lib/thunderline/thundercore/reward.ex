defmodule Thunderline.Thundercore.Reward do
  @moduledoc """
  Thundercore.Reward — Edge-of-Chaos Reward Loop System.

  Unified interface for the reward loop subsystem that drives automata
  toward critical behavior (λ̂ ≈ 0.273, edge of chaos).

  ## Components

  - `RewardSchema` — Computes reward from criticality + side-quest metrics
  - `RewardController` — Maintains tuning state per run
  - `RewardLoop` — Event-driven loop per CA run
  - `RewardSnapshot` — Ash resource for persistence

  ## Quick Start

      # Attach reward loop to a CA run
      Reward.attach("run_123")

      # Manual computation
      {:ok, result} = Reward.compute(criticality, side_quest, tick: 42)
      # => %{reward: 0.78, tuning: %{lambda_delta: -0.007, ...}}

      # Get average reward for run
      {:ok, avg} = Reward.average_reward("run_123")

  ## Architecture

  ```
  ┌───────────────────────────────────────────────────────────────┐
  │                    REWARD LOOP                                │
  │                                                               │
  │   Automata ──▶ Metrics ──▶ RewardSchema ──▶ Tuning ──▶ λ,T   │
  │      ▲                                                  │     │
  │      └──────────────────────────────────────────────────┘     │
  └───────────────────────────────────────────────────────────────┘
  ```

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 3
  - Langton, C.G. (1990) "Computation at the Edge of Chaos"
  """

  alias Thunderline.Thundercore.Reward.{
    RewardSchema,
    RewardController,
    RewardLoop,
    RewardSnapshot
  }

  # ═══════════════════════════════════════════════════════════════
  # Loop Management
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Attaches a reward loop to a CA run.

  The loop automatically:
  1. Subscribes to metrics events for this run
  2. Computes rewards when both criticality + side-quest are available
  3. Applies tuning signals back to the CA runner
  """
  defdelegate attach(run_id, opts \\ []), to: RewardLoop

  @doc """
  Detaches the reward loop from a run.
  """
  defdelegate detach(run_id), to: RewardLoop

  @doc """
  Gets the current state of a reward loop.
  """
  defdelegate loop_state(run_id), to: RewardLoop, as: :get_state

  # ═══════════════════════════════════════════════════════════════
  # Reward Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes reward from criticality and side-quest metrics.

  ## Examples

      criticality = %{edge_score: 0.85, lambda_hat: 0.28, plv: 0.45, ...}
      side_quest = %{emergence_score: 0.7, healing_rate: 0.8, ...}

      {:ok, result} = Reward.compute(criticality, side_quest, tick: 42)
      # => %{reward: 0.78, tuning: %{lambda_delta: -0.007, ...}, ...}
  """
  defdelegate compute(criticality, side_quest, opts \\ []), to: RewardSchema

  @doc """
  Computes reward (raising version).
  """
  defdelegate compute!(criticality, side_quest, opts \\ []), to: RewardSchema

  @doc """
  Returns the reward weights configuration.
  """
  defdelegate weights(), to: RewardSchema

  @doc """
  Returns the target values for edge-of-chaos.
  """
  defdelegate targets(), to: RewardSchema

  # ═══════════════════════════════════════════════════════════════
  # Controller Interface
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Processes metrics for a run through the controller.

  Returns computed reward with smoothed tuning and applied params.
  """
  defdelegate process(run_id, criticality, side_quest, tick), to: RewardController, as: :process_metrics

  @doc """
  Gets the reward history for a run.
  """
  defdelegate history(run_id), to: RewardController, as: :get_reward_history

  @doc """
  Gets the current tuning parameters for a run.
  """
  defdelegate current_params(run_id), to: RewardController, as: :get_current_params

  @doc """
  Gets the average reward for a run.
  """
  defdelegate average_reward(run_id), to: RewardController, as: :get_average_reward

  @doc """
  Lists all registered runs.
  """
  defdelegate list_runs(), to: RewardController

  # ═══════════════════════════════════════════════════════════════
  # Persistence
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a reward snapshot for persistence.
  """
  def create_snapshot(result, opts \\ []) do
    run_id = Keyword.fetch!(opts, :run_id)

    attrs = %{
      run_id: run_id,
      tick: result.tick,
      reward: result.reward,
      edge_score: result.components.edge_score,
      emergence: result.components.emergence,
      stability: result.components.stability,
      healing: result.components.healing,
      lambda_delta: result.tuning.lambda_delta,
      temp_delta: result.tuning.temp_delta,
      coupling_delta: result.tuning.coupling_delta,
      applied_lambda: get_in(result, [:applied_params, :lambda]),
      applied_temperature: get_in(result, [:applied_params, :temperature]),
      applied_coupling: get_in(result, [:applied_params, :coupling]),
      zone: result.zone
    }

    RewardSnapshot.create(attrs)
  end

  @doc """
  Gets reward snapshots for a run.
  """
  defdelegate snapshots(run_id), to: RewardSnapshot, as: :by_run

  @doc """
  Gets the latest reward snapshot for a run.
  """
  defdelegate latest_snapshot(run_id), to: RewardSnapshot, as: :latest_for_run

  @doc """
  Gets snapshots in a specific dynamical zone.
  """
  defdelegate snapshots_in_zone(zone), to: RewardSnapshot, as: :in_zone
end
