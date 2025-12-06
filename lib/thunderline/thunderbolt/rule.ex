defmodule Thunderline.Thunderbolt.Rule do
  @moduledoc """
  Behaviour for pluggable CA/NCA/Ising rule backends.

  Allows the Stepper to route to different update rule implementations:
  - `:classic_ca` — Outer-totalistic rules (B/S notation)
  - `:nca` — Neural Cellular Automata (attention-based, ViT-style)
  - `:ising` — Ising/spin models with Metropolis dynamics
  - `:ternary` — Reversible ternary rules (Feynman/Toffoli)

  ## Implementing a Rule

  Modules implementing this behaviour must define:

  1. `update/3` — Compute next state for a single cell given neighbors
  2. `init_params/1` — Initialize any learnable parameters (for NCA)
  3. `backend_type/0` — Return the backend type atom

  ## Example

      defmodule MyCustomRule do
        @behaviour Thunderline.Thunderbolt.Rule

        @impl true
        def backend_type, do: :custom_ca

        @impl true
        def init_params(_opts), do: %{}

        @impl true
        def update(cell, neighbors, params) do
          # Custom update logic
          new_state = compute_new_state(cell, neighbors)
          {:ok, new_state, %{}}
        end
      end

  ## Side-Quest Metrics

  Rules can optionally emit side-quest metrics by returning them
  in the third element of the update tuple:

      {:ok, new_state, %{clustering: 0.5, entropy: 0.3}}

  These are aggregated by the Stepper and forwarded to Thundercore.

  ## Registration

  Rules can be registered with Thunderforge for DSL-based configuration:

      Thunderforge.register_rule(:my_rule, MyCustomRule)

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 2
  - NCA: Mordvintsev et al. "Growing Neural Cellular Automata" (2020)
  """

  alias Thunderline.Thunderbolt.Thunderbit

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type cell :: Thunderbit.t() | map() | any()
  @type neighbor :: {Thunderbit.coord(), Thunderbit.t()} | Thunderbit.t() | map()
  @type params :: map()
  @type side_quest_metrics :: %{
          optional(:clustering) => float(),
          optional(:entropy) => float(),
          optional(:sortedness) => float(),
          optional(:divergence) => float(),
          optional(:healing_rate) => float()
        }
  @type update_result :: {:ok, cell(), side_quest_metrics()} | {:error, term()}

  @type backend_type :: :classic_ca | :nca | :ising | :ternary | :hybrid | atom()

  # ═══════════════════════════════════════════════════════════════
  # Callbacks
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns the backend type for this rule.

  Used by the Stepper for routing and telemetry tagging.
  """
  @callback backend_type() :: backend_type()

  @doc """
  Initializes parameters for the rule.

  For classic CA, this typically returns an empty map or rule configuration.
  For NCA, this initializes neural network weights.
  For Ising, this initializes coupling matrices and temperature.

  Options may include:
  - `:seed` - Random seed for reproducibility
  - `:config` - Rule-specific configuration
  """
  @callback init_params(opts :: keyword()) :: params()

  @doc """
  Computes the next state for a cell given its neighbors.

  Returns `{:ok, new_cell, side_quest_metrics}` or `{:error, reason}`.

  The side-quest metrics map can contain any of:
  - `:clustering` - Local clustering coefficient
  - `:entropy` - Local entropy
  - `:sortedness` - Local order measure
  - `:divergence` - Divergence from expected
  - `:healing_rate` - Damage recovery rate

  These metrics are aggregated by the Stepper and emitted to Thundercore.
  """
  @callback update(cell :: cell(), neighbors :: [neighbor()], params :: params()) ::
              update_result()

  # ═══════════════════════════════════════════════════════════════
  # Optional Callbacks
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Batch update for multiple cells (optional optimization).

  Default implementation calls `update/3` for each cell.
  Override for vectorized implementations (e.g., Nx-based NCA).
  """
  @callback batch_update(cells :: [cell()], neighbors_list :: [[neighbor()]], params :: params()) ::
              {:ok, [cell()], side_quest_metrics()} | {:error, term()}

  @doc """
  Step an entire grid (optional, for Nx tensor-based rules).

  For NCA rules that operate on entire grids rather than individual cells.
  Returns the new grid state and aggregated metrics.
  """
  @callback step_grid(grid :: any(), params :: params(), opts :: keyword()) ::
              {:ok, any(), side_quest_metrics()} | {:error, term()}

  @optional_callbacks batch_update: 3, step_grid: 3

  # ═══════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Checks if a module implements the Rule behaviour.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :update, 3) and
      function_exported?(module, :backend_type, 0)
  end

  @doc """
  Gets the backend type for a rule module, or nil if not a valid rule.
  """
  @spec get_backend_type(module()) :: backend_type() | nil
  def get_backend_type(module) when is_atom(module) do
    if implements?(module), do: module.backend_type(), else: nil
  end

  @doc """
  Aggregate side-quest metrics from multiple cells.

  Computes mean values for each metric type present.
  """
  @spec aggregate_metrics([side_quest_metrics()]) :: side_quest_metrics()
  def aggregate_metrics([]), do: %{}

  def aggregate_metrics(metrics_list) do
    # Collect all metric keys
    all_keys =
      metrics_list
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    # Compute mean for each key
    Map.new(all_keys, fn key ->
      values =
        metrics_list
        |> Enum.map(&Map.get(&1, key))
        |> Enum.reject(&is_nil/1)

      mean =
        if Enum.empty?(values) do
          0.0
        else
          Enum.sum(values) / length(values)
        end

      {key, Float.round(mean, 4)}
    end)
  end

  @doc """
  Merge side-quest metrics with criticality metrics.

  Combines the side-quest metrics from rule updates with
  the criticality metrics (PLV, entropy, λ̂, Lyapunov).
  """
  @spec merge_with_criticality(side_quest_metrics(), map()) :: map()
  def merge_with_criticality(side_quest, criticality) do
    Map.merge(criticality, side_quest, fn _k, v1, v2 ->
      # Prefer side-quest values for overlapping keys
      v2 || v1
    end)
  end
end
