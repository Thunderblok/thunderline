defmodule Thunderline.Thunderflow.Producers.EDGARMock do
  @moduledoc "Mock producer emitting synthetic EDGAR filings for Phase 0 testing."
  use GenStage
  require Logger

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    state = %{demand: 0, cik: "0000000001"}
    Process.send_after(self(), :filing, 5_000)
    {:producer, state}
  end

  @impl true
  def handle_demand(incoming, state) do
    {:noreply, [], %{state | demand: state.demand + incoming}}
  end

  @impl true
  def handle_info(:filing, %{demand: demand}=state) do
    filing_time = DateTime.utc_now()
    events =
      if demand > 0 do
        [%{cik: state.cik, form: "10-Q", filing_time: filing_time, sections: %{"MDA" => "Sample text"}}]
      else
        []
      end
    if demand > 0, do: Logger.debug("[EDGARMock] emitted filing #{filing_time}")
    Process.send_after(self(), :filing, 5_000)
    {:noreply, events, %{state | demand: max(demand - length(events), 0)}}
  end
end
