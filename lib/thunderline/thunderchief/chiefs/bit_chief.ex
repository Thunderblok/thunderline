defmodule Thunderline.Thunderchief.Chiefs.BitChief do
  @moduledoc """
  Thunderbit Domain Orchestrator (Puppeteer).

  The BitChief observes the Thunderbit domain and decides which bits
  to activate, transition, or consolidate on each tick. This implements
  the "puppeteer" pattern for Thunderbit orchestration.

  ## Responsibilities

  - Monitor pending/active bit counts by category
  - Decide which bits to activate next
  - Manage category transitions (sensory → cognitive → motor)
  - Trigger consolidation when chain depth is high
  - Log trajectory data for Cerebros policy learning

  ## Action Space

  - `{:activate_pending, %{strategy: :fifo | :priority | :energy}}`
  - `{:transition, category_atom}`
  - `:consolidate` - Merge activated bits into cells
  - `:checkpoint` - Save current state
  - `:wait` - No action, wait for stimulus

  ## Example

      state = BitChief.observe_state(ctx)
      {:ok, action} = BitChief.choose_action(state)
      {:ok, updated_ctx} = BitChief.apply_action(action, ctx)
      outcome = BitChief.report_outcome(updated_ctx)
  """

  @behaviour Thunderline.Thunderchief.Behaviour

  require Logger

  alias Thunderline.Thunderbit.Category
  alias Thunderline.Thunderchief.{State, Action}
  alias Thunderline.Thunderbolt.CerebrosFacade.Mini.Bridge, as: CerebrosBridge

  @categories [:sensory, :cognitive, :motor, :governance, :meta]
  @max_chain_depth 5
  @min_energy_threshold 0.3
  @consolidation_threshold 10
  @cerebros_eval_batch_size 10

  # ===========================================================================
  # Behaviour Implementation
  # ===========================================================================

  @impl true
  def observe_state(ctx) do
    bits = Map.values(ctx.bits_by_id)
    cells = Map.values(ctx.cells_by_id)

    # Count bits by category and status
    category_counts = count_by_category(bits)
    pending = count_pending(bits)
    active = count_active(bits)

    # Count bits needing Cerebros evaluation
    needs_cerebros_eval = count_needs_cerebros_eval(bits)

    # Calculate aggregate metrics
    total_energy = calculate_total_energy(bits)
    avg_energy = if length(bits) > 0, do: total_energy / length(bits), else: 1.0
    chain_depth = calculate_chain_depth(bits)
    cell_count = length(cells)

    State.new(:bit, %{
      # Counts
      pending_count: pending,
      active_count: active,
      total_bits: length(bits),
      cell_count: cell_count,

      # Cerebros
      needs_cerebros_eval: needs_cerebros_eval,

      # By category
      category_counts: category_counts,
      active_category: current_active_category(bits),

      # Energy
      total_energy: total_energy,
      avg_energy: avg_energy,
      energy_level: avg_energy,

      # Chain depth
      chain_depth: chain_depth,
      needs_consolidation: chain_depth > @max_chain_depth,

      # Session
      session_age_ms: session_age(ctx),
      last_action: Map.get(ctx.metadata, :last_action)
    },
    tick: Map.get(ctx.metadata, :tick, 0),
    context: ctx
    )
  end

  @impl true
  def choose_action(%State{features: state}) do
    cond do
      # High priority: consolidate if chain too deep
      state.needs_consolidation ->
        {:ok, :consolidate}

      # Cerebros evaluation: score bits needing eval
      state.needs_cerebros_eval > 0 ->
        {:ok, {:cerebros_evaluate, %{batch_size: @cerebros_eval_batch_size}}}

      # Energy critical: wait for recovery
      state.energy_level < @min_energy_threshold ->
        {:wait, 500}

      # Pending bits with sufficient energy: activate
      state.pending_count > 0 and state.energy_level > 0.5 ->
        strategy = choose_activation_strategy(state)
        {:ok, {:activate_pending, %{strategy: strategy}}}

      # Many active bits: consider transition
      state.active_count > @consolidation_threshold ->
        next_category = transition_target(state.active_category)
        {:ok, {:transition, next_category}}

      # Normal: checkpoint or maintain
      state.session_age_ms > 30_000 ->
        {:ok, :checkpoint}

      # No action needed
      true ->
        {:wait, 100}
    end
  end

  @impl true
  def apply_action(action, ctx) do
    action_struct = Action.from_tuple(action)
    action_struct = Action.mark_executing(action_struct)

    result = do_apply_action(action, ctx)

    case result do
      {:ok, updated_ctx} ->
        Action.log(Action.mark_completed(action_struct), :executed, %{})
        updated_ctx = put_in(updated_ctx.metadata[:last_action], action)
        {:ok, updated_ctx}

      {:error, reason} = error ->
        Action.log(Action.mark_failed(action_struct, reason), :failed, %{})
        error
    end
  end

  @impl true
  def report_outcome(ctx) do
    state = observe_state(ctx)

    %{
      reward: calculate_reward(ctx, state),
      metrics: %{
        bits_processed: Map.get(ctx.metadata, :bits_processed, 0),
        active_bits: state.features.active_count,
        pending_bits: state.features.pending_count,
        energy_level: state.features.energy_level,
        chain_depth: state.features.chain_depth
      },
      trajectory_step: %{
        state: state.features,
        action: Map.get(ctx.metadata, :last_action),
        next_state: state.features,
        timestamp: DateTime.utc_now()
      }
    }
  end

  @impl true
  def action_space do
    [
      :consolidate,
      :checkpoint,
      :wait,
      {:activate_pending, %{strategy: :fifo}},
      {:activate_pending, %{strategy: :priority}},
      {:activate_pending, %{strategy: :energy}},
      {:transition, :sensory},
      {:transition, :cognitive},
      {:transition, :motor},
      {:cerebros_evaluate, %{batch_size: @cerebros_eval_batch_size}}
    ]
  end

  # ===========================================================================
  # Action Execution
  # ===========================================================================

  defp do_apply_action(:consolidate, ctx) do
    # Merge activated bits into cells
    active_bits = ctx.bits_by_id
                  |> Map.values()
                  |> Enum.filter(&(&1.status == :active))

    if length(active_bits) > 0 do
      # Group by category and consolidate
      _groups = Enum.group_by(active_bits, & &1.category)
      # For now, just mark consolidation in metadata
      updated = update_in(ctx.metadata[:consolidations], &((&1 || 0) + 1))
      {:ok, updated}
    else
      {:ok, ctx}
    end
  end

  defp do_apply_action(:checkpoint, ctx) do
    # Save current state checkpoint
    updated = put_in(ctx.metadata[:last_checkpoint], DateTime.utc_now())
    {:ok, updated}
  end

  defp do_apply_action({:activate_pending, %{strategy: strategy}}, ctx) do
    pending = ctx.bits_by_id
              |> Map.values()
              |> Enum.filter(&(&1.status == :pending))

    case select_bit(pending, strategy) do
      nil ->
        {:ok, ctx}

      bit ->
        activated = Map.put(bit, :status, :active)
        updated = put_in(ctx.bits_by_id[bit.id], activated)
        updated = update_in(updated.metadata[:bits_processed], &((&1 || 0) + 1))
        {:ok, updated}
    end
  end

  defp do_apply_action({:transition, category}, ctx) when category in @categories do
    # Transition active bits to new category phase
    active = ctx.bits_by_id
             |> Map.values()
             |> Enum.filter(&(&1.status == :active))

    updated_bits = Enum.reduce(active, ctx.bits_by_id, fn bit, acc ->
      # Mark transition in bit metadata
      updated_bit = put_in(bit[:metadata][:transition], {bit.category, category})
      Map.put(acc, bit.id, updated_bit)
    end)

    {:ok, %{ctx | bits_by_id: updated_bits}}
  end

  defp do_apply_action({:cerebros_evaluate, %{batch_size: batch_size}}, ctx) do
    # Find bits needing Cerebros evaluation
    bits_to_eval = ctx.bits_by_id
                   |> Map.values()
                   |> Enum.filter(&needs_cerebros_eval?/1)
                   |> Enum.take(batch_size)

    if length(bits_to_eval) > 0 do
      case CerebrosBridge.evaluate_and_apply_batch(bits_to_eval, ctx) do
        {:ok, updated_bits, updated_ctx} ->
          # Update bits_by_id with evaluated bits
          new_bits_by_id = Enum.reduce(updated_bits, updated_ctx.bits_by_id, fn bit, acc ->
            Map.put(acc, bit.id, bit)
          end)

          updated = %{updated_ctx | bits_by_id: new_bits_by_id}
          updated = update_in(updated.metadata[:cerebros_evals], &((&1 || 0) + length(updated_bits)))

          Logger.debug("[BitChief] Cerebros evaluated #{length(updated_bits)} bits")
          {:ok, updated}

        {:error, reason} ->
          Logger.warning("[BitChief] Cerebros evaluation failed: #{inspect(reason)}")
          {:ok, ctx}  # Non-fatal, continue
      end
    else
      {:ok, ctx}
    end
  end

  defp do_apply_action(action, ctx) do
    # Unknown action, log warning
    Logger.warning("[BitChief] Unknown action: #{inspect(action)}")
    {:ok, ctx}
  end

  # ===========================================================================
  # Strategy Selection
  # ===========================================================================

  defp choose_activation_strategy(state) do
    cond do
      # Low energy: prioritize by energy efficiency
      state.energy_level < 0.5 -> :energy
      # Many pending: use FIFO for fairness
      state.pending_count > 20 -> :fifo
      # Default: priority-based
      true -> :priority
    end
  end

  defp select_bit([], _strategy), do: nil

  defp select_bit(pending, :fifo) do
    # First in, first out by creation time
    Enum.min_by(pending, & &1.created_at, DateTime)
  end

  defp select_bit(pending, :priority) do
    # Highest priority first
    Enum.max_by(pending, &Map.get(&1, :priority, 0))
  end

  defp select_bit(pending, :energy) do
    # Lowest energy cost first
    Enum.min_by(pending, &Map.get(&1, :energy_cost, 1.0))
  end

  defp transition_target(current) do
    # Natural flow: sensory → cognitive → motor
    case current do
      :sensory -> :cognitive
      :cognitive -> :motor
      :motor -> :governance
      _ -> :sensory
    end
  end

  # ===========================================================================
  # Metric Calculation
  # ===========================================================================

  defp count_by_category(bits) do
    Enum.reduce(bits, %{}, fn bit, acc ->
      cat = Category.atom_to_category(bit.category || :sensory)
      Map.update(acc, cat, 1, &(&1 + 1))
    end)
  rescue
    _ -> %{}
  end

  defp count_pending(bits) do
    Enum.count(bits, &(&1.status == :pending))
  end

  defp count_active(bits) do
    Enum.count(bits, &(&1.status == :active))
  end

  defp count_needs_cerebros_eval(bits) do
    Enum.count(bits, &needs_cerebros_eval?/1)
  end

  defp needs_cerebros_eval?(bit) do
    # A bit needs Cerebros evaluation if:
    # 1. It's newly spawned (no score yet)
    # 2. It's been modified since last eval
    # 3. It's explicitly flagged for re-evaluation

    cond do
      # Explicitly flagged
      Map.get(bit, :needs_cerebros_eval?, false) == true -> true

      # No score yet (never evaluated)
      is_nil(Map.get(bit, :cerebros_score)) -> true

      # Stale evaluation (older than 5 minutes)
      stale_cerebros_eval?(bit) -> true

      # Otherwise, no need
      true -> false
    end
  end

  defp stale_cerebros_eval?(bit) do
    case Map.get(bit, :last_cerebros_eval) do
      nil -> true
      last_eval ->
        age = DateTime.diff(DateTime.utc_now(), last_eval, :second)
        age > 300  # 5 minutes
    end
  end

  defp calculate_total_energy(bits) do
    Enum.reduce(bits, 0.0, fn bit, acc ->
      acc + Map.get(bit, :energy, 1.0)
    end)
  end

  defp calculate_chain_depth(bits) do
    bits
    |> Enum.map(&Map.get(&1, :chain_depth, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp current_active_category(bits) do
    active = Enum.filter(bits, &(&1.status == :active))
    if length(active) > 0 do
      active
      |> Enum.frequencies_by(& &1.category)
      |> Enum.max_by(&elem(&1, 1), fn -> {:sensory, 0} end)
      |> elem(0)
    else
      :sensory
    end
  end

  defp session_age(ctx) do
    case ctx.started_at do
      nil -> 0
      started -> DateTime.diff(DateTime.utc_now(), started, :millisecond)
    end
  end

  defp calculate_reward(ctx, state) do
    # Reward signal for RL training
    # Higher reward for: throughput, energy efficiency, low chain depth

    throughput = Map.get(ctx.metadata, :bits_processed, 0) / max(state.features.session_age_ms, 1) * 1000
    energy_bonus = state.features.energy_level
    depth_penalty = state.features.chain_depth / (@max_chain_depth * 2)

    throughput * energy_bonus - depth_penalty
  end
end
