defmodule Thunderline.Thunderchief.Chiefs.UIChief do
  @moduledoc """
  Thunderprism/Surface (UI) Domain Orchestrator (Puppeteer).

  The UIChief observes the user interface state and decides which
  components to render, update, or prune based on viewport, user
  focus, and system resources.

  ## Responsibilities

  - Monitor active LiveView sessions and component tree
  - Prioritize rendering based on viewport visibility
  - Manage component lifecycle (mount, update, unmount)
  - Throttle updates during high load
  - Log trajectory data for Cerebros UI optimization

  ## Action Space

  - `{:prioritize_component, component_id}` - Boost render priority
  - `{:throttle_updates, rate_ms}` - Slow down update frequency
  - `{:prune_offscreen, viewport}` - Remove invisible components
  - `{:prefetch_data, component_ids}` - Preload data for components
  - `:flush_stale` - Clear cached renders
  - `:wait` - No action

  ## UI Optimization Strategy

  1. Track which components are visible (viewport intersection)
  2. Prioritize updates for visible + interactive components
  3. Defer/batch updates for offscreen components
  4. Prune components that haven't been visible for threshold
  5. Prefetch data for components likely to become visible

  ## Example

      state = UIChief.observe_state(prism_ctx)
      {:ok, action} = UIChief.choose_action(state)
      {:ok, updated} = UIChief.apply_action(action, prism_ctx)
  """

  @behaviour Thunderline.Thunderchief.Behaviour

  require Logger

  alias Thunderline.Thunderchief.{State, Action}

  @default_throttle_ms 100
  @prune_after_ms 60_000
  # Prefetch when scrolling toward component
  @prefetch_threshold 3

  # ===========================================================================
  # Behaviour Implementation
  # ===========================================================================

  @impl true
  def observe_state(prism_ctx) do
    components = get_components(prism_ctx)
    sessions = get_active_sessions(prism_ctx)

    # Component states
    visible = Enum.filter(components, & &1.visible)
    interactive = Enum.filter(components, &(&1.focused || &1.hovered))
    stale = find_stale_components(components)
    offscreen = Enum.filter(components, &(!&1.visible))

    # Session metrics
    session_count = length(sessions)
    avg_latency = calculate_avg_latency(sessions)
    # 200ms threshold
    high_latency = avg_latency > 200

    # Render queue
    pending_updates = get_pending_updates(prism_ctx)
    update_pressure = length(pending_updates)

    # Predict which components may become visible
    likely_visible = predict_scroll_targets(prism_ctx)

    State.new(
      :ui,
      %{
        # Component counts
        total_components: length(components),
        visible_count: length(visible),
        interactive_count: length(interactive),
        offscreen_count: length(offscreen),
        stale_count: length(stale),

        # Interactive state
        visible_components: visible,
        interactive_components: interactive,
        stale_components: stale,
        likely_visible: likely_visible,

        # Session health
        session_count: session_count,
        avg_latency: avg_latency,
        high_latency: high_latency,

        # Render pressure
        pending_updates: update_pressure,
        needs_throttle: update_pressure > 20 or high_latency,

        # Current settings
        throttle_rate: prism_ctx[:throttle_rate] || @default_throttle_ms
      },
      tick: Map.get(prism_ctx, :tick, 0),
      context: prism_ctx
    )
  end

  @impl true
  def choose_action(%State{features: state}) do
    cond do
      # Priority 1: Throttle if under pressure
      state.needs_throttle and state.throttle_rate < 500 ->
        new_rate = min(state.throttle_rate * 2, 500)
        {:ok, {:throttle_updates, new_rate}}

      # Priority 2: Clear stale renders
      state.stale_count > 10 ->
        {:ok, :flush_stale}

      # Priority 3: Prune offscreen components
      state.offscreen_count > 50 ->
        {:ok, {:prune_offscreen, get_viewport(state)}}

      # Priority 4: Prefetch for likely-visible components
      length(state.likely_visible) > 0 and not state.needs_throttle ->
        component_ids = Enum.map(state.likely_visible, & &1.id)
        {:ok, {:prefetch_data, component_ids}}

      # Priority 5: Prioritize interactive components
      state.interactive_count > 0 ->
        [focused | _] = state.interactive_components
        {:ok, {:prioritize_component, focused.id}}

      # Priority 6: Relax throttle if pressure reduced
      state.pending_updates < 5 and state.throttle_rate > @default_throttle_ms ->
        {:ok, {:throttle_updates, @default_throttle_ms}}

      # No action needed
      true ->
        {:wait, 50}
    end
  end

  @impl true
  def apply_action(action, prism_ctx) do
    action_struct = Action.from_tuple(action)
    action_struct = Action.mark_executing(action_struct)

    {:ok, updated} = do_apply_action(action, prism_ctx)
    Action.log(Action.mark_completed(action_struct), :executed, %{chief: :ui})
    {:ok, updated}
  end

  @impl true
  def report_outcome(prism_ctx) do
    state = observe_state(prism_ctx)

    %{
      reward: calculate_reward(state),
      metrics: %{
        visible_components: state.features.visible_count,
        interactive: state.features.interactive_count,
        pending_updates: state.features.pending_updates,
        avg_latency: state.features.avg_latency,
        throttle_rate: state.features.throttle_rate
      },
      trajectory_step: %{
        state: state.features,
        action: nil,
        next_state: state.features,
        timestamp: DateTime.utc_now()
      }
    }
  end

  @impl true
  def action_space do
    [
      :flush_stale,
      :wait,
      {:prioritize_component, "component_id"},
      {:throttle_updates, 100},
      {:prune_offscreen, %{top: 0, bottom: 1000}},
      {:prefetch_data, ["component_ids"]}
    ]
  end

  # ===========================================================================
  # Action Execution
  # ===========================================================================

  defp do_apply_action({:prioritize_component, component_id}, ctx) do
    components = ctx[:components] || %{}

    updated =
      Map.update(components, component_id, nil, fn comp ->
        if comp, do: Map.put(comp, :priority, :high), else: comp
      end)

    {:ok, Map.put(ctx, :components, updated)}
  end

  defp do_apply_action({:throttle_updates, rate_ms}, ctx) do
    updated = Map.put(ctx, :throttle_rate, rate_ms)
    emit_ui_event(:throttle_adjusted, %{rate_ms: rate_ms})
    {:ok, updated}
  end

  defp do_apply_action({:prune_offscreen, _viewport}, ctx) do
    components = ctx[:components] || %{}

    # Remove components not visible for threshold
    now = DateTime.utc_now()

    pruned =
      Enum.reject(components, fn {_id, comp} ->
        not comp.visible and
          DateTime.diff(now, comp[:last_visible] || now, :millisecond) > @prune_after_ms
      end)
      |> Map.new()

    pruned_count = map_size(components) - map_size(pruned)
    emit_ui_event(:components_pruned, %{count: pruned_count})

    {:ok, Map.put(ctx, :components, pruned)}
  end

  defp do_apply_action({:prefetch_data, component_ids}, ctx) do
    # Mark components as prefetching
    components = ctx[:components] || %{}

    updated =
      Enum.reduce(component_ids, components, fn id, acc ->
        Map.update(acc, id, nil, fn comp ->
          if comp, do: Map.put(comp, :prefetching, true), else: comp
        end)
      end)

    emit_ui_event(:data_prefetch, %{component_ids: component_ids})
    {:ok, Map.put(ctx, :components, updated)}
  end

  defp do_apply_action(:flush_stale, ctx) do
    components = ctx[:components] || %{}

    # Clear stale render cache
    updated =
      Enum.map(components, fn {id, comp} ->
        {id, Map.put(comp, :cached_render, nil)}
      end)
      |> Map.new()

    emit_ui_event(:stale_flushed, %{count: map_size(components)})
    {:ok, Map.put(ctx, :components, updated)}
  end

  defp do_apply_action(_action, ctx) do
    {:ok, ctx}
  end

  # ===========================================================================
  # Observation Helpers
  # ===========================================================================

  defp get_components(ctx) do
    (ctx[:components] || %{})
    |> Map.values()
  end

  defp get_active_sessions(ctx) do
    ctx[:sessions] || []
  end

  defp get_pending_updates(ctx) do
    ctx[:pending_updates] || []
  end

  defp find_stale_components(components) do
    now = DateTime.utc_now()
    threshold = @prune_after_ms

    Enum.filter(components, fn comp ->
      case comp[:last_update] do
        nil -> false
        last -> DateTime.diff(now, last, :millisecond) > threshold
      end
    end)
  end

  defp calculate_avg_latency([]), do: 0.0

  defp calculate_avg_latency(sessions) do
    total = Enum.reduce(sessions, 0, &(&1[:latency] || 0 + &2))
    total / length(sessions)
  end

  defp predict_scroll_targets(ctx) do
    # Simple heuristic: components just outside viewport
    viewport = ctx[:viewport] || %{top: 0, bottom: 1000}
    components = get_components(ctx)

    components
    |> Enum.filter(fn comp ->
      pos = comp[:position] || %{y: 0}
      # 300px margin
      margin = @prefetch_threshold * 100

      (pos.y > viewport.bottom and pos.y < viewport.bottom + margin) or
        (pos.y < viewport.top and pos.y > viewport.top - margin)
    end)
    |> Enum.take(5)
  end

  defp get_viewport(state) do
    # Extract viewport from state context or use defaults
    case state do
      %{context: %{viewport: vp}} when is_map(vp) -> vp
      _ -> %{top: 0, bottom: 1000}
    end
  end

  defp emit_ui_event(event_type, payload) do
    event_name = "prism.ui.#{event_type}"

    Thunderline.Thunderflow.EventBus.publish_event(%{
      name: event_name,
      source: :prism,
      payload: payload
    })
  rescue
    _ -> :ok
  end

  # ===========================================================================
  # Reward Calculation
  # ===========================================================================

  defp calculate_reward(state) do
    # Reward: low latency, high interactivity, efficient updates
    # Normalize to ~0-5
    latency_penalty = state.features.avg_latency / 100
    interactivity_bonus = state.features.interactive_count * 0.5
    efficiency = if state.features.needs_throttle, do: -5, else: 5

    interactivity_bonus + efficiency - latency_penalty
  end
end
