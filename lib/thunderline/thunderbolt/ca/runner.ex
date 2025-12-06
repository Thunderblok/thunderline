defmodule Thunderline.Thunderbolt.CA.Runner do
  @moduledoc """
  Cellular Automata Run Loop.

  Periodically emits deltas over Phoenix PubSub topic `ca:<run_id>`.
  Feature gated by `:ca_viz` – callers should ensure feature enabled
  before starting a run (the supervisor is only started when enabled).

  ## Timing Modes

  - **Self-timed (default)**: Runner uses its own timer at ~20Hz
  - **Clock-driven**: Runner subscribes to Clock's :hold phase for v2 ternary grids

  Configure via `:clock_driven` option or `:rule_version` in ruleset.

  ## Criticality Metrics (HC-40)

  If `:emit_criticality` option is true (default), the runner computes
  PLV, entropy, λ̂, and Lyapunov metrics every tick and emits:

  - Telemetry: `[:thunderline, :bolt, :ca, :criticality]`
  - Event: `bolt.ca.metrics.snapshot`

  These metrics are consumed by Cerebros-DiffLogic for edge-of-chaos tuning.

  ## Side-Quest Metrics (TIGER LATTICE)

  When using pluggable Rule backends, the runner also emits side-quest metrics:

  - Telemetry: `[:thunderbolt, :automata, :side_quest]`
  - Event: `bolt.automata.side_quest.snapshot`

  Side-quest metrics (clustering, sortedness, healing_rate) are merged with
  criticality metrics for a unified view of automata dynamics.
  """
  use GenServer
  require Logger
  alias Thunderline.Thunderbolt.CA.Stepper
  alias Thunderline.Thunderbolt.CA.Criticality
  alias Thunderline.Thunderbolt.CA.SideQuestMetrics
  alias Thunderline.Thundercore.Clock

  # ~20 Hz; can be adjusted via opts
  @default_tick_ms 50
  @telemetry_event [:thunderline, :ca, :tick]
  @default_history_depth 10

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = via(run_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current grid state for a running CA.
  """
  def get_grid(run_id) do
    GenServer.call(via(run_id), :get_grid)
  end

  @doc """
  Updates the ruleset for a running CA.
  """
  def update_ruleset(run_id, ruleset) do
    GenServer.cast(via(run_id), {:update_ruleset, ruleset})
  end

  @doc """
  Updates tuning parameters for a running CA (from RewardController).

  Supported params:
  - `:lambda` — Langton's λ̂ parameter (fraction of non-quiescent rules)
  - `:temperature` — Noise/stochasticity level
  - `:coupling` — Neighbor coupling strength

  These are merged into the ruleset for the next step.
  """
  def update_params(run_id, params) when is_map(params) do
    GenServer.cast(via(run_id), {:update_params, params})
  end

  @doc """
  Gets the current tuning parameters for a running CA.
  """
  def get_params(run_id) do
    GenServer.call(via(run_id), :get_params)
  end

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    size = Keyword.get(opts, :size, 24)
    ruleset = Keyword.get(opts, :ruleset, %{rule: :demo})
    tick_ms = Keyword.get(opts, :tick_ms, @default_tick_ms)

    # Determine timing mode
    # Clock-driven if explicitly set OR if ruleset has rule_version: 2
    clock_driven =
      Keyword.get(opts, :clock_driven, false) or
        Map.get(ruleset, :rule_version, 1) == 2

    # Criticality metrics config (HC-40)
    emit_criticality = Keyword.get(opts, :emit_criticality, true)
    history_depth = Keyword.get(opts, :history_depth, @default_history_depth)

    # Create grid - use Thunderbit grid for v2, legacy for v1
    grid =
      if Map.get(ruleset, :rule_version, 1) == 2 do
        # v2: Create 3D Thunderbit grid
        dim = Keyword.get(opts, :dimension, {size, size, 1})
        {x, y, z} = normalize_dimension(dim, size)
        Stepper.create_thunderbit_grid(x, y, z, rule_id: get_rule_from_ruleset(ruleset))
      else
        # v1: Legacy 2D grid
        %{size: size}
      end

    # Initialize tuning params from ruleset or defaults
    tuning_params = %{
      lambda: Map.get(ruleset, :lambda, 0.5),
      temperature: Map.get(ruleset, :temperature, 1.0),
      coupling: Map.get(ruleset, :coupling, 0.5)
    }

    state = %{
      run_id: run_id,
      grid: grid,
      ruleset: ruleset,
      tuning_params: tuning_params,
      seq: 0,
      tick_ms: tick_ms,
      clock_driven: clock_driven,
      timer_ref: nil,
      emit_criticality: emit_criticality,
      history_depth: history_depth,
      flow_history: []
    }

    # Start ticking based on mode
    state =
      if clock_driven do
        subscribe_to_clock(state)
      else
        schedule_tick(state)
      end

    mode = if clock_driven, do: "clock-driven", else: "self-timed"
    rule_version = Map.get(ruleset, :rule_version, 1)

    Logger.info(
      "[CA.Runner] started run=#{inspect(run_id)} mode=#{mode} v#{rule_version} Hz=#{Float.round(1000.0 / tick_ms, 1)}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_grid, _from, state) do
    {:reply, state.grid, state}
  end

  @impl true
  def handle_call(:get_params, _from, state) do
    {:reply, state.tuning_params, state}
  end

  @impl true
  def handle_cast({:update_ruleset, ruleset}, state) do
    {:noreply, %{state | ruleset: ruleset}}
  end

  @impl true
  def handle_cast({:update_params, params}, state) do
    # Merge tuning params into ruleset
    new_params = Map.merge(state.tuning_params, params)
    new_ruleset = merge_params_into_ruleset(state.ruleset, new_params)

    Logger.debug(
      "[CA.Runner] #{state.run_id} updated params: λ=#{new_params[:lambda]} T=#{new_params[:temperature]} C=#{new_params[:coupling]}"
    )

    {:noreply, %{state | ruleset: new_ruleset, tuning_params: new_params}}
  end

  # Self-timed tick handler
  @impl true
  def handle_info(
        :tick,
        %{grid: grid, ruleset: rules, run_id: run_id, seq: seq, clock_driven: false} = st
      ) do
    {deltas, new_grid, duration_ms, new_history} = do_step(grid, rules, run_id, seq, st)

    broadcast_deltas(run_id, seq + 1, deltas)
    emit_telemetry(run_id, duration_ms, deltas)

    new_state = schedule_tick(%{st | grid: new_grid, seq: seq + 1, flow_history: new_history})
    {:noreply, new_state}
  end

  # Clock-driven tick handler (from Clock phase subscription)
  @impl true
  def handle_info(
        {:clock_phase, :hold, clock_tick},
        %{grid: grid, ruleset: rules, run_id: run_id, seq: seq, clock_driven: true} = st
      ) do
    {deltas, new_grid, duration_ms, new_history} = do_step(grid, rules, run_id, seq, st)

    broadcast_deltas(run_id, seq + 1, deltas)
    emit_telemetry(run_id, duration_ms, deltas)

    Logger.debug("[CA.Runner] #{run_id} stepped on clock tick #{clock_tick}")
    {:noreply, %{st | grid: new_grid, seq: seq + 1, flow_history: new_history}}
  end

  # Ignore other clock phases
  @impl true
  def handle_info({:clock_phase, _phase, _tick}, state) do
    {:noreply, state}
  end

  # Ignore unexpected tick if we switched to clock-driven
  @impl true
  def handle_info(:tick, %{clock_driven: true} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{timer_ref: ref}) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ─────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────

  defp do_step(grid, rules, run_id, seq, state) do
    started = System.monotonic_time(:microsecond)

    # Stepper.next_with_metrics/2 dispatches to v1/v2 and collects side-quest metrics
    {:ok, deltas, new_grid, side_quest_metrics} = Stepper.next_with_metrics(grid, rules)

    duration_ms = (System.monotonic_time(:microsecond) - started) / 1000

    # Compute and emit criticality metrics (HC-40)
    new_history =
      if state.emit_criticality do
        emit_criticality_metrics(run_id, seq, deltas, side_quest_metrics, state)
      else
        state.flow_history
      end

    {deltas, new_grid, duration_ms, new_history}
  end

  defp emit_criticality_metrics(run_id, tick, deltas, side_quest_metrics, state) do
    history = state.flow_history

    case Criticality.compute_from_deltas(deltas, tick: tick, history: history) do
      {:ok, criticality_metrics} ->
        # Emit criticality metrics
        Criticality.emit_metrics(run_id, tick, criticality_metrics)

        # Emit side-quest metrics if we have them
        if map_size(side_quest_metrics) > 0 do
          emit_side_quest_metrics(run_id, tick, deltas, side_quest_metrics, history)
        end

        # Update flow history (bounded ring buffer)
        flows = Enum.map(deltas, fn d -> Map.get(d, :sigma_flow, Map.get(d, :energy, 0.5)) end)
        update_history(flows, history, state.history_depth)

      {:error, reason} ->
        Logger.warning("[CA.Runner] criticality computation failed: #{inspect(reason)}")
        history
    end
  end

  defp emit_side_quest_metrics(run_id, tick, deltas, rule_metrics, history) do
    # Compute full side-quest snapshot using rule metrics + delta analysis
    case SideQuestMetrics.compute(deltas, rule_metrics, tick: tick, history: history) do
      {:ok, sq_metrics} ->
        SideQuestMetrics.emit(run_id, tick, sq_metrics)

      {:error, reason} ->
        Logger.debug("[CA.Runner] side-quest computation skipped: #{inspect(reason)}")
    end
  end

  defp update_history(new_flows, history, depth) do
    [new_flows | history]
    |> Enum.take(depth)
  end

  defp broadcast_deltas(run_id, seq, deltas) do
    msg = %{run_id: run_id, seq: seq, cells: deltas}
    Phoenix.PubSub.broadcast(Thunderline.PubSub, "ca:#{run_id}", {:ca_delta, msg})
  end

  defp emit_telemetry(run_id, duration_ms, deltas) do
    :telemetry.execute(
      @telemetry_event,
      %{duration_ms: duration_ms, cells: length(deltas)},
      %{run_id: run_id}
    )
  end

  defp schedule_tick(%{tick_ms: interval} = state) do
    ref = Process.send_after(self(), :tick, interval)
    %{state | timer_ref: ref}
  end

  defp subscribe_to_clock(state) do
    # Subscribe to :hold phase - the compute phase in the 4-phase cycle
    runner_pid = self()

    Clock.on_phase(:hold, fn tick ->
      send(runner_pid, {:clock_phase, :hold, tick})
    end)

    Logger.debug("[CA.Runner] #{state.run_id} subscribed to Clock :hold phase")
    state
  end

  defp normalize_dimension({x, y, z}, _default), do: {x, y, z}
  defp normalize_dimension(size, _default) when is_integer(size), do: {size, size, 1}
  defp normalize_dimension(_, default), do: {default, default, 1}

  defp get_rule_from_ruleset(%{rule_id: rule_id}), do: rule_id
  defp get_rule_from_ruleset(%{rule: rule}), do: rule
  defp get_rule_from_ruleset(_), do: :demo

  defp merge_params_into_ruleset(ruleset, params) do
    # Merge tuning params into ruleset for rules that support them
    ruleset
    |> Map.put(:lambda, params[:lambda] || 0.5)
    |> Map.put(:temperature, params[:temperature] || 1.0)
    |> Map.put(:coupling, params[:coupling] || 0.5)
  end

  defp via(run_id), do: {:via, Registry, {Thunderline.Thunderbolt.CA.Registry, run_id}}
end
