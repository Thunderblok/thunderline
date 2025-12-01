defmodule Thunderline.Thunderbolt.TAK.Runner do
  @moduledoc """
  TAK Runner - GPU-enhanced CA evolution streaming via PubSub.

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.TAK

  @type runner_state :: %{
          run_id: String.t(),
          grid: TAK.Grid.t(),
          ruleset: struct(),
          seq: non_neg_integer(),
          tick_ms: pos_integer(),
          gpu_enabled?: boolean(),
          stats: map()
        }

  # Client API

  @doc \"""
  Start a TAK runner process.

  ## Options

  - `:run_id` - Unique identifier for this run (required)
  - `:size` - Grid dimensions (required)
  - `:ruleset` - Parsed CA rules (required)
  - `:tick_ms` - Milliseconds between generations (default: 50)
  - `:gpu_enabled?` - Use GPU acceleration (default: true in Phase 2)
  - `:broadcast?` - Emit PubSub deltas (default: true)

  ## Examples

      {:ok, pid} = TAK.Runner.start_link(%{
        run_id: "my_run",
        size: {100, 100, 100},
        ruleset: ruleset
      })
  """
  def start_link(opts) do
    run_id = Map.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(run_id))
  end

  @doc """
  Pause evolution (stop sending ticks).

  ## Examples

      :ok = TAK.Runner.pause(pid)
  """
  def pause(pid) when is_pid(pid) do
    GenServer.call(pid, :pause)
  end

  @doc """
  Resume evolution (restart ticks).

  ## Examples

      :ok = TAK.Runner.resume(pid)
  """
  def resume(pid) when is_pid(pid) do
    GenServer.call(pid, :resume)
  end

  @doc """
  Get current runner statistics.

  ## Examples

      TAK.Runner.get_stats(pid)
      # => %{generation: 1000, gen_per_sec: 1250, gpu_utilization: 0.85}
  """
  def get_stats(pid) when is_pid(pid) do
    GenServer.call(pid, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    run_id = Map.fetch!(opts, :run_id)
    size = Map.fetch!(opts, :size)
    ruleset = Map.fetch!(opts, :ruleset)
    tick_ms = Map.get(opts, :tick_ms, 50)
    gpu_enabled? = Map.get(opts, :gpu_enabled?, false)
    enable_recording? = Map.get(opts, :enable_recording?, true)

    grid = Grid.new(size)

    state = %{
      run_id: run_id,
      grid: grid,
      ruleset: ruleset,
      seq: 0,
      tick_ms: tick_ms,
      gpu_enabled?: gpu_enabled?,
      paused?: false,
      stats: %{
        started_at: System.monotonic_time(:millisecond),
        generation_count: 0,
        last_gen_time_ms: 0,
        avg_gen_time_ms: 0
      }
    }

    # Start Thundervine event recorder for this run
    if enable_recording? do
      case Thunderline.Thundervine.Supervisor.start_recorder(run_id: run_id) do
        {:ok, _pid} ->
          Logger.info("[TAK.Runner] Started Thundervine recorder for run_id=#{run_id}")

        {:error, {:already_started, _pid}} ->
          Logger.debug("[TAK.Runner] Thundervine recorder already started for run_id=#{run_id}")

        {:error, reason} ->
          Logger.warning("[TAK.Runner] Failed to start Thundervine recorder: #{inspect(reason)}")
      end
    end

    schedule_tick(tick_ms)

    Logger.info(
      "[TAK.Runner] Started run_id=#{run_id} size=#{inspect(size)} tick_ms=#{tick_ms} gpu?=#{gpu_enabled?}"
    )

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{paused?: true} = state) do
    schedule_tick(state.tick_ms)
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    start_time = System.monotonic_time(:millisecond)

    # Phase 3: GPU-accelerated evolution with proper Grid↔Tensor bridge
    {deltas, new_grid} =
      if state.gpu_enabled? do
        # GPU path: Grid → Tensor → GPU evolve → Tensor → Grid
        evolved_tensor = gpu_evolve(state.grid, state.ruleset)
        deltas = compute_deltas_from_tensor(state.grid, evolved_tensor)

        new_grid =
          Grid.from_tensor(state.grid, evolved_tensor)
          |> Grid.increment_generation()

        {deltas, new_grid}
      else
        # Fallback to existing Bolt.CA.Stepper
        result = Thunderline.Thunderbolt.TAK.evolve_gpu(state.grid, state.ruleset)

        case result do
          {:ok, d, g} ->
            {d, g}

          _ ->
            Logger.warning("[TAK.Runner] Evolution failed, using previous grid")
            {[], state.grid}
        end
      end

    gen_time_ms = System.monotonic_time(:millisecond) - start_time

    # Broadcast deltas via PubSub
    msg = %{
      run_id: state.run_id,
      seq: state.seq + 1,
      generation: Grid.generation(new_grid),
      cells: deltas,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "ca:#{state.run_id}",
      {:ca_delta, msg}
    )

    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :tak, :runner, :tick],
      %{duration_ms: gen_time_ms, cell_count: length(deltas)},
      %{run_id: state.run_id, gpu_enabled?: state.gpu_enabled?}
    )

    # Update stats
    new_stats =
      state.stats
      |> Map.put(:generation_count, state.stats.generation_count + 1)
      |> Map.put(:last_gen_time_ms, gen_time_ms)
      |> update_avg_gen_time(gen_time_ms)

    schedule_tick(state.tick_ms)

    {:noreply,
     %{
       state
       | grid: new_grid,
         seq: state.seq + 1,
         stats: new_stats
     }}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | paused?: true}}
  end

  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | paused?: false}}
  end

  def handle_call(:get_stats, _from, state) do
    runtime_ms = System.monotonic_time(:millisecond) - state.stats.started_at
    runtime_sec = runtime_ms / 1000.0

    stats = %{
      generation: state.seq,
      runtime_sec: runtime_sec,
      gen_per_sec: if(runtime_sec > 0, do: state.stats.generation_count / runtime_sec, else: 0),
      avg_gen_time_ms: state.stats.avg_gen_time_ms,
      last_gen_time_ms: state.stats.last_gen_time_ms,
      gpu_enabled?: state.gpu_enabled?
    }

    {:reply, stats, state}
  end

  # Private Helpers

  defp via_tuple(run_id) do
    {:via, Registry, {Thunderline.Thunderbolt.CA.Registry, run_id}}
  end

  defp schedule_tick(tick_ms) do
    Process.send_after(self(), :tick, tick_ms)
  end

  defp update_avg_gen_time(stats, new_gen_time_ms) do
    count = stats.generation_count
    old_avg = stats.avg_gen_time_ms
    new_avg = (old_avg * count + new_gen_time_ms) / (count + 1)
    Map.put(stats, :avg_gen_time_ms, new_avg)
  end

  # GPU evolution helper (Phase 2+3)
  defp gpu_evolve(grid, ruleset) do
    # Convert Grid to Nx tensor using Phase 3 implementation
    tensor = Grid.to_tensor(grid)

    # Evolve using GPU kernel
    born = Map.get(ruleset, :born, [3])
    survive = Map.get(ruleset, :survive, [2, 3])

    Thunderline.Thunderbolt.TAK.GPUStepper.evolve(tensor, born, survive)
  end

  # Compute delta changes from tensor evolution (Phase 3)
  defp compute_deltas_from_tensor(old_grid, new_tensor) do
    Grid.compute_deltas_from_tensor(old_grid, new_tensor)
  end
end
