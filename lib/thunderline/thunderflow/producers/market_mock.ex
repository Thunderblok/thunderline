defmodule Thunderline.Thunderflow.Producers.MarketMock do
  @moduledoc "Mock producer emitting synthetic MarketTick events for Phase 0 testing."
  use GenStage
  require Logger
  alias Broadway.Message

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
    log_every = market_ingest_log_every()
    events =
      if demand > 0 do
        raw = %{symbol: state.symbol, ts: System.os_time(:microsecond), vendor_seq: state.seq, bid_px: 100.0, ask_px: 100.1}
        [build_message(raw)]
      else
        []
      end
    if demand > 0 and producer_log_enabled?() and log_tick?(state.seq, log_every) do
      Logger.debug("[MarketMock] emitted tick seq=#{state.seq}")
    end
    Process.send_after(self(), :tick, 50)
    {:noreply, events, %{state | demand: max(demand - length(events), 0)}}
  end

  defp market_ingest_log_every do
    Application.get_env(:thunderline, :market_ingest)[:log_every] || 50
  end

  defp producer_log_enabled? do
    Application.get_env(:thunderline, :market_ingest)[:producer_log?] || false
  end

  defp log_tick?(seq, every) when is_integer(seq) and every > 0 do
    seq == 1 or rem(seq, every) == 0
  end
  defp log_tick?(_, _), do: false

  defp build_message(data) do
    # Use the noop acknowledger correctly. Its ack/3 clause only matches when ack_ref == nil.
    # Broadway.NoopAcknowledger.init/0 returns {Broadway.NoopAcknowledger, nil, nil}.
    %Message{data: data, metadata: %{}, acknowledger: Broadway.NoopAcknowledger.init()}
  end
end
