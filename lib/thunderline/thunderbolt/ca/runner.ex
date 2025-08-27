defmodule Thunderline.Thunderbolt.CA.Runner do
  @moduledoc """
  Cellular Automata Run Loop.

  Periodically emits deltas over Phoenix PubSub topic `ca:<run_id>`.
  Feature gated by `:ca_viz` – callers should ensure feature enabled
  before starting a run (the supervisor is only started when enabled).
  """
  use GenServer
  require Logger
  alias Thunderline.CA.Stepper

  @default_tick_ms 50        # ~20 Hz; can be adjusted via opts
  @telemetry_event [:thunderline, :ca, :tick]

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = via(run_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    size = Keyword.get(opts, :size, 24)
    ruleset = Keyword.get(opts, :ruleset, %{rule: :demo})
    tick_ms = Keyword.get(opts, :tick_ms, @default_tick_ms)
    state = %{
      run_id: run_id,
      grid: %{size: size},
      ruleset: ruleset,
      seq: 0,
      tick_ms: tick_ms
    }
    schedule_tick(tick_ms)
    Logger.info("[CA.Runner] started run=#{inspect(run_id)} size=#{size}Hz=#{Float.round(1000.0/tick_ms,1)}")
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{grid: grid, ruleset: rules, run_id: run_id, seq: seq, tick_ms: tick_ms} = st) do
    started = System.monotonic_time(:microsecond)
    case Stepper.next(grid, rules) do
      {:ok, deltas, new_grid} ->
        msg = %{run_id: run_id, seq: seq + 1, cells: deltas}
        Phoenix.PubSub.broadcast(Thunderline.PubSub, "ca:#{run_id}", {:ca_delta, msg})
        duration_ms = (System.monotonic_time(:microsecond) - started) / 1000
        :telemetry.execute(@telemetry_event, %{duration_ms: duration_ms, cells: length(deltas)}, %{run_id: run_id})
        schedule_tick(tick_ms)
        {:noreply, %{st | grid: new_grid, seq: seq + 1}}
      {:error, reason} ->
        Logger.error("[CA.Runner] step error run=#{run_id} reason=#{inspect(reason)}")
        schedule_tick(tick_ms)
        {:noreply, st}
    end
  end

  defp schedule_tick(interval), do: Process.send_after(self(), :tick, interval)
  defp via(run_id), do: {:via, Registry, {Thunderline.Thunderbolt.CA.Registry, run_id}}
end
