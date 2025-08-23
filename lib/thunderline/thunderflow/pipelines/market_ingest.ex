defmodule Thunderline.Thunderflow.Pipelines.MarketIngest do
  @moduledoc """
  Broadway pipeline for market tick ingestion → window building (Phase 0 skeleton).
  Steps (future): Normalize -> WindowBuilder -> FeatureCompute -> Persist -> Emit.
  """
  use Broadway
  require Logger

  alias Broadway.Message

  @producer Thunderline.Thunderflow.Producers.MarketMock

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {@producer, []}, concurrency: 1],
      processors: [default: [concurrency: 2]],
      batchers: []
    )
  end

  @impl true
  def handle_message(_, %Message{data: tick}=message, _ctx) do
    seq = Map.get(tick, :vendor_seq)
    log_every = market_ingest_log_every()
    if log_tick?(seq, log_every) do
      if market_ingest_log_payload?() do
        # Log a small, safe projection of the tick to avoid log spam/KeyErrors
        projection = Map.take(tick, [:symbol, :vendor_seq, :bid_px, :ask_px])
        Logger.debug(fn -> "[MarketIngest] tick #{inspect(projection)}" end)
      else
        Logger.debug(fn -> "[MarketIngest] tick seq=#{seq}" end)
      end
    end
    message
  end

  defp market_ingest_log_every do
    Application.get_env(:thunderline, :market_ingest)[:log_every] || 50
  end

  defp market_ingest_log_payload? do
    Application.get_env(:thunderline, :market_ingest)[:log_payload?] || false
  end

  defp log_tick?(seq, every) when is_integer(seq) and every > 0 do
    seq == 1 or rem(seq, every) == 0
  end
  defp log_tick?(_, _), do: false

  @impl true
  def handle_batch(_, messages, _batch_info, _ctx), do: messages
end
