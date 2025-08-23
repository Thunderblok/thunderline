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
    # Phase 0: just log & ack. Later we will build windows & create FeatureWindow.
    Logger.debug(fn -> "[MarketIngest] tick #{inspect(tick)}" end)
    message
  end

  @impl true
  def handle_batch(_, messages, _batch_info, _ctx), do: messages
end
