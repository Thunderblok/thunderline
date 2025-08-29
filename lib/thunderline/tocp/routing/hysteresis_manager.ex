defmodule Thunderline.TOCP.Routing.HysteresisManager do
  @moduledoc """
  Dynamic hysteresis adjustment control.

  Listens for `:tocp, :routing_relay_switch_rate` telemetry events (to be
  emitted by routing implementation) and temporarily increases hysteresis
  percentage when churn threshold breached, reverting after a timeout.
  """
  use GenServer
  require Logger

  @telemetry_event [:tocp, :routing_relay_switch_rate]
  @default_up_pct 25
  @revert_ms 5 * 60 * 1000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    conf = Thunderline.TOCP.Config.get()
    base = conf.selector.hysteresis_pct
    attach()
    {:ok, %{base: base, current: base, timer: nil}}
  end

  def current, do: GenServer.call(__MODULE__, :current)

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state.current, state}

  @impl true
  def handle_info({:set_temp, pct}, state) do
    Logger.warning("[TOCP][Hysteresis] Elevating hysteresis to #{pct}% for #{@revert_ms}ms (prev #{state.current}%)")
    timer = Process.send_after(self(), :revert, @revert_ms)
    {:noreply, %{state | current: pct, timer: timer}}
  end

  @impl true
  def handle_info(:revert, state) do
    Logger.info("[TOCP][Hysteresis] Reverting hysteresis to base #{state.base}%")
    {:noreply, %{state | current: state.base, timer: nil}}
  end

  defp attach do
    :telemetry.attach_many(
      {__MODULE__, :relay_switch_rate},
      [@telemetry_event],
      &__MODULE__.handle_event/4,
      %{}
    )
  rescue
    _ -> :ok
  end

  @doc false
  # measurements: %{rate_pct: float}
  def handle_event(_event, %{rate_pct: rate}, _meta, _cfg) do
    # Threshold fixed for now (5%) – future: config-driven & adaptive.
    if rate > 5.0 do
      send(__MODULE__, {:set_temp, @default_up_pct})
    end
    :ok
  end
end
