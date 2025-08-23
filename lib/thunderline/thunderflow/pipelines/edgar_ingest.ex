defmodule Thunderline.Thunderflow.Pipelines.EDGARIngest do
  @moduledoc """
  Broadway pipeline for EDGAR filings ingestion (Phase 0 skeleton).
  Future: Parse -> SectionChunk -> Embedding -> FeatureCompute -> Persist -> Emit.
  """
  use Broadway
  require Logger
  alias Broadway.Message

  @producer Thunderline.Thunderflow.Producers.EDGARMock

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {@producer, []}, concurrency: 1],
      processors: [default: [concurrency: 1]],
      batchers: []
    )
  end

  @impl true
  def handle_message(_, %Message{data: filing}=message, _ctx) do
    Logger.debug(fn -> "[EDGARIngest] filing #{inspect(Map.take(filing, [:cik, :form, :filing_time]))}" end)
    message
  end

  @impl true
  def handle_batch(_, messages, _batch_info, _ctx), do: messages
end
