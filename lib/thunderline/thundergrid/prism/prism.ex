defmodule Thunderline.Thundergrid.Prism do
  @moduledoc """
  Thundergrid.Prism — Visual Intelligence & Automata Introspection

  Consolidated from Thunderprism, this module provides:

  1. **ML Decision DAGs** — Track ML decision trails via PrismNode/PrismEdge
  2. **Automata Introspection** — Query CA/NCA grid state and metrics
  3. **Side-Quest Metrics** — Access clustering, emergence, healing snapshots
  4. **Criticality Dashboard** — PLV, entropy, edge-of-chaos zone visibility

  ## GraphQL Queries

  Available via Thundergrid.Domain:

  - `prism_nodes` — List ML decision nodes
  - `prism_node` — Get single decision node
  - `automata_snapshot` — Current automata metrics
  - `automata_history` — Historical metrics timeline

  ## Usage

      # Log ML decision
      Prism.log_decision(%{
        pac_id: "controller_1",
        iteration: 42,
        chosen_model: :model_a,
        model_probabilities: %{model_a: 0.7, model_b: 0.3}
      })

      # Query automata state
      {:ok, snapshot} = Prism.get_automata_snapshot("run_123")

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 4
  - Consolidation: Thunderprism → Thundergrid.Prism
  """

  alias Thunderline.Thundergrid.Prism.{PrismNode, PrismEdge, MLTap, AutomataSnapshot}
  alias Thunderline.Thunderbolt.CA.{Stepper, Runner, Criticality, SideQuestMetrics}

  require Logger

  # ═══════════════════════════════════════════════════════════════
  # ML Decision Logging
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Log an ML decision as a PrismNode (async, non-blocking).

  See `MLTap.log_node/1` for full documentation.
  """
  @spec log_decision(map()) :: Task.t()
  defdelegate log_decision(attrs), to: MLTap, as: :log_node

  @doc """
  Log an edge between two decision nodes (async).
  """
  @spec log_edge(map()) :: Task.t()
  defdelegate log_edge(attrs), to: MLTap

  @doc """
  Log decision with optional edge to previous node.
  """
  @spec log_with_edge(map(), String.t() | nil) :: {:ok, Task.t()}
  defdelegate log_with_edge(attrs, prev_node_id \\ nil), to: MLTap

  # ═══════════════════════════════════════════════════════════════
  # Automata Introspection
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Get current automata snapshot for a running CA.

  Returns grid state, criticality metrics, and side-quest metrics.

  ## Parameters

  - `run_id` - The CA run identifier

  ## Returns

  `{:ok, snapshot}` with:
  - `:grid_state` - Current grid tick, bounds, cell count
  - `:criticality` - PLV, entropy, lambda_hat, lyapunov, zone
  - `:side_quest` - clustering, sortedness, emergence_score
  - `:sampled_at` - Timestamp
  """
  @spec get_automata_snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def get_automata_snapshot(run_id) do
    try do
      # Get grid from runner
      grid = Runner.get_grid(run_id)

      # Extract grid state
      grid_state = extract_grid_state(grid)

      # Get latest metrics (would need a metrics store in production)
      # For now, return current state without historical metrics
      snapshot = %{
        run_id: run_id,
        grid_state: grid_state,
        criticality: %{},
        side_quest: %{},
        sampled_at: DateTime.utc_now()
      }

      {:ok, snapshot}
    rescue
      e ->
        Logger.warning("[Prism] automata snapshot failed: #{inspect(e)}")
        {:error, {:snapshot_failed, e}}
    catch
      :exit, {:noproc, _} ->
        {:error, :run_not_found}
    end
  end

  @doc """
  Compute and return automata metrics for a grid without stepping.

  Useful for one-off introspection.
  """
  @spec compute_metrics(Stepper.grid(), keyword()) :: {:ok, map()} | {:error, term()}
  def compute_metrics(grid, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)
    history = Keyword.get(opts, :history, [])

    # Step the grid to get deltas
    {:ok, deltas, _new_grid, side_quest} = Stepper.next_with_metrics(grid, %{})

    # Compute criticality
    {:ok, criticality} = Criticality.compute_from_deltas(deltas, tick: tick, history: history)

    # Compute side-quest
    {:ok, sq_metrics} = SideQuestMetrics.compute(deltas, side_quest, tick: tick, history: history)

    {:ok, %{
      criticality: criticality,
      side_quest: sq_metrics,
      grid_stats: extract_grid_state(grid),
      computed_at: DateTime.utc_now()
    }}
  end

  @doc """
  List all active CA runs with their current state.
  """
  @spec list_active_runs() :: [{String.t(), map()}]
  def list_active_runs do
    # Get all registered runners
    Registry.select(Thunderline.Thunderbolt.CA.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.map(fn {run_id, _pid} ->
      case get_automata_snapshot(run_id) do
        {:ok, snapshot} -> {run_id, snapshot}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ═══════════════════════════════════════════════════════════════
  # Prism Node Queries
  # ═══════════════════════════════════════════════════════════════

  @doc """
  List all prism nodes, optionally filtered.
  """
  @spec list_nodes(keyword()) :: {:ok, [PrismNode.t()]} | {:error, term()}
  def list_nodes(opts \\ []) do
    PrismNode
    |> apply_filters(opts)
    |> Ash.read()
  end

  @doc """
  Get a single prism node by ID.
  """
  @spec get_node(String.t()) :: {:ok, PrismNode.t()} | {:error, term()}
  def get_node(id) do
    PrismNode
    |> Ash.get(id)
  end

  @doc """
  List prism edges, optionally filtered.
  """
  @spec list_edges(keyword()) :: {:ok, [PrismEdge.t()]} | {:error, term()}
  def list_edges(opts \\ []) do
    PrismEdge
    |> apply_filters(opts)
    |> Ash.read()
  end

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp extract_grid_state(%{bits: bits, bounds: bounds, tick: tick}) do
    %{
      tick: tick,
      bounds: bounds,
      cell_count: map_size(bits),
      type: :thunderbit
    }
  end

  defp extract_grid_state(%{size: size}) do
    %{
      tick: 0,
      bounds: {size, size, 1},
      cell_count: size * size,
      type: :legacy
    }
  end

  defp extract_grid_state(_), do: %{type: :unknown}

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:pac_id, pac_id}, q -> Ash.Query.filter_input(q, %{pac_id: pac_id})
      {:limit, limit}, q -> Ash.Query.limit(q, limit)
      {:offset, offset}, q -> Ash.Query.offset(q, offset)
      _, q -> q
    end)
  end
end
