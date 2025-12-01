defmodule Thunderline.Thunderflow.Pipelines.ExampleDomainPipeline do
  @moduledoc """
  Example pipeline demonstrating the DomainProcessor behaviour.

  HC-12: Shows how to reduce ~300 lines of Broadway boilerplate to ~80 lines.

  ## Before (typical Broadway pipeline)

  Each pipeline repeated:
  - ~40 lines of `start_link/1` with producer/processor/batcher config
  - ~30 lines of `handle_message/3` with normalization, routing, error handling
  - ~20 lines per batcher in `handle_batch/4` with telemetry + PubSub
  - ~30 lines of `handle_failed/2` for DLQ routing
  - ~50+ lines of helper functions

  ## After (using DomainProcessor)

  - ~5 lines for `use` declaration
  - ~10-20 lines for `process_event/2` (your business logic)
  - ~10-20 lines per batcher in `handle_event_batch/4` (your side effects)
  - Optional: override configs as needed

  ## Usage

  Add to your supervision tree:

      children = [
        # ... other children
        {Thunderline.Thunderflow.Pipelines.ExampleDomainPipeline, []}
      ]

  The pipeline will:
  1. Pull events from MnesiaProducer
  2. Normalize and route via `process_event/2`
  3. Batch by type, emit telemetry, broadcast via PubSub
  4. Route failures to DLQ automatically
  """

  use Thunderline.Thunderflow.DomainProcessor,
    name: :example_domain,
    queue: :domain_events,
    batchers: [:standard, :priority, :audit],
    batch_size: 25,
    batch_timeout: 1_000,
    concurrency: 4

  alias Thunderline.Event
  alias Thunderline.Thunderflow.DomainProcessor

  require Logger

  # --- Required Callbacks ---

  @impl Thunderline.Thunderflow.DomainProcessor
  def process_event(event, _context) do
    # Normalize to canonical Event struct
    case DomainProcessor.normalize_event(event) do
      {:ok, normalized} ->
        # Route to appropriate batcher based on event properties
        batcher = determine_batcher(normalized)
        {:ok, normalized, batcher}

      {:error, reason} ->
        {:error, {:normalization_failed, reason}}
    end
  end

  @impl Thunderline.Thunderflow.DomainProcessor
  def handle_event_batch(:standard, messages, _batch_info, _context) do
    # Standard events: broadcast to subscribers
    events = Enum.map(messages, & &1.data)

    DomainProcessor.broadcast("domain:standard", {:events, events})

    Logger.debug("[ExampleDomain] Processed #{length(events)} standard events")
    messages
  end

  def handle_event_batch(:priority, messages, _batch_info, _context) do
    # Priority events: immediate processing + broadcast
    events = Enum.map(messages, & &1.data)

    # Could enqueue Oban jobs for heavy processing
    # Enum.each(events, fn ev ->
    #   DomainProcessor.enqueue_job(MyWorker, %{event_id: ev.id})
    # end)

    DomainProcessor.broadcast("domain:priority", {:priority_events, events})

    Logger.info("[ExampleDomain] Processed #{length(events)} priority events")
    messages
  end

  def handle_event_batch(:audit, messages, _batch_info, _context) do
    # Audit events: log for compliance
    events = Enum.map(messages, & &1.data)

    Enum.each(events, fn ev ->
      Logger.info("[ExampleDomain:Audit] event=#{ev.name} id=#{ev.id}")
    end)

    DomainProcessor.broadcast("domain:audit", {:audit_events, events})
    messages
  end

  # --- Optional: Custom Batcher Config ---

  @doc false
  def do_batcher_config(:priority) do
    # Priority events: smaller batches, shorter timeout for responsiveness
    [batch_size: 10, batch_timeout: 200]
  end

  def do_batcher_config(:audit) do
    # Audit events: larger batches, longer timeout for efficiency
    [batch_size: 50, batch_timeout: 5_000]
  end

  def do_batcher_config(_other) do
    # Use defaults for standard
    []
  end

  # --- Private Helpers ---

  defp determine_batcher(%Event{} = event) do
    cond do
      priority_event?(event) -> :priority
      audit_event?(event) -> :audit
      true -> :standard
    end
  end

  defp priority_event?(%Event{type: type}) when type in [:critical, :urgent, :alert], do: true

  defp priority_event?(%Event{name: name}) when is_binary(name) do
    String.starts_with?(name, "priority.") or String.contains?(name, ".critical.")
  end

  defp priority_event?(_), do: false

  defp audit_event?(%Event{type: type}) when type in [:audit, :compliance, :security], do: true

  defp audit_event?(%Event{name: name}) when is_binary(name) do
    String.starts_with?(name, "audit.") or String.starts_with?(name, "security.")
  end

  defp audit_event?(_), do: false
end
