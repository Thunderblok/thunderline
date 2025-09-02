defmodule Thunderline.Thunderflow.Heartbeat do
  @moduledoc """
  Single system heartbeat emitter (WARHORSE).

  Emits a realtime event every interval (default 2000ms initially per doctrine) with
  monotonic sequence counter and last drift measurement placeholder.
  """
  use GenServer
  require Logger

  @default_interval 2000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    state = %{interval: interval, seq: 0, last_emit: System.monotonic_time()}
    Logger.info("[Heartbeat] starting interval=#{interval}ms")
    schedule(interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{interval: interval, seq: seq, last_emit: last} = state) do
    now = System.monotonic_time()
    drift = now - last - ms_to_native(interval)
    payload = %{sequence: seq + 1, drift_native: drift, interval_ms: interval}
    with {:ok, ev} <- Thunderline.Event.new(%{
           name: "system.flow.tick",
           source: :flow,
           payload: payload,
           meta: %{pipeline: :realtime},
           priority: :high,
           type: :system_tick
         }) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("[Heartbeat] publish tick failed: #{inspect(reason)} seq=#{seq + 1}")
      end
    end
    :telemetry.execute([:thunderline, :heartbeat, :tick], %{seq: seq + 1}, %{interval: interval, drift_native: drift})
    schedule(interval)
    {:noreply, %{state | seq: seq + 1, last_emit: now}}
  end

  defp schedule(interval), do: Process.send_after(self(), :tick, interval)
  defp ms_to_native(ms), do: System.convert_time_unit(ms, :millisecond, :native)
end
