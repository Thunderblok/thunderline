defmodule Thunderchief.Jobs.DomainProcessor do
  @moduledoc """
  Placeholder Oban worker to process domain events routed by the EventPipeline.

  This stub eliminates undefined module warnings. Replace with real logic
  per-domain, or refactor the EventPipeline to dispatch directly to existing
  Thunderline.Thunderflow.Jobs.* workers.
  """

  use Oban.Worker, queue: :domain_events, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event, "domain" => domain}}) do
    Logger.debug("[DomainProcessor] Received event for #{domain}: #{inspect(event)}")
    # TODO: Implement per-domain delegation
    {:ok, %{handled: true, domain: domain}}
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("[DomainProcessor] Unexpected args: #{inspect(args)}")
    {:discard, :invalid_args}
  end
end
