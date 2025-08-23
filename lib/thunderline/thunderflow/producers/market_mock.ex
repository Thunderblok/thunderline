defmodule Thunderline.Thunderflow.Producers.MarketMock do
  @moduledoc "Mock producer emitting synthetic MarketTick events for Phase 0 testing."
  use GenStage
  require Logger

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    state = %{demand: 0, symbol: "MOCK", seq: 0}
    Process.send_after(self(), :tick, 50)
    {:producer, state}
  end

  @impl true
  def handle_demand(incoming, state) do
    {:noreply, [], %{state | demand: state.demand + incoming}}
  end

  @impl true
  def handle_info(:tick, %{demand: demand}=state) do
    state = %{state | seq: state.seq + 1}
    events =
      if demand > 0 do
        [%{symbol: state.symbol, ts: System.os_time(:microsecond), vendor_seq: state.seq, bid_px: 100.0, ask_px: 100.1}]
      else
        []
      end
    if demand > 0, do: Logger.debug("[MarketMock] emitted tick seq=#{state.seq}")
    Process.send_after(self(), :tick, 50)
    {:noreply, events, %{state | demand: max(demand - length(events), 0)}}
  end
end
