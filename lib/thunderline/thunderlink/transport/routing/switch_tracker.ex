defmodule Thunderline.Thunderlink.Transport.Routing.SwitchTracker do
  @moduledoc """
  Tracks relay switches within a sliding time window and emits telemetry for hysteresis management.
  """
  use GenServer
  require Logger

  @window_ms 10_000
  @flush_ms 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Record a relay switch candidate. total_nodes may be nil if unknown."
  def record_switch(zone, prev, new, total_nodes, opts \\ []) do
    GenServer.cast(__MODULE__, {:switch, zone, prev, new, total_nodes, opts})
  end

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, %{zones: %{}, started_at: now_ms()}}
  end

  @impl true
  def handle_cast({:switch, zone, prev, new, total_nodes, _opts}, state) do
    cond do
      prev == nil or new == nil or prev == new -> {:noreply, state}
      true ->
        zones = Map.update(state.zones, zone, %{switches: 1, total_nodes: total_nodes}, fn z ->
          %{z | switches: z.switches + 1, total_nodes: total_nodes || z.total_nodes}
        end)
        {:noreply, %{state | zones: zones}}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    window_s = @window_ms / 1000
    Enum.each(state.zones, fn {zone, %{switches: sw, total_nodes: tn}} ->
      rate_pct = if tn && tn > 0 do
        (sw / tn) * (60 / window_s) * 100
      else
        0.0
      end
      :telemetry.execute([:tocp, :routing_relay_switch_rate], %{rate_pct: rate_pct}, %{zone: zone, switches: sw, total_nodes: tn || 0, window_s: window_s})
    end)
    schedule_flush()
    {:noreply, %{state | zones: %{}}}
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_ms)
  defp now_ms, do: System.system_time(:millisecond)
end
