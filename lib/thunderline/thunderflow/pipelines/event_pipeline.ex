defmodule Thunderline.Thunderflow.Pipelines.EventPipeline do
  @moduledoc """
  Broadway Pipeline for Structured Event Processing

  Processes events from all domains with batching, backpressure handling,
  and dead letter queues for failed events.
  """

  use Broadway

  alias Broadway.Message
  alias Phoenix.PubSub
  require Logger

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {Thunderflow.MnesiaProducer,
           [
             table: Thunderflow.MnesiaProducer,
             poll_interval: 1000,
             max_batch_size: 50,
             broadway_name: __MODULE__
           ]}
      ],
      processors: [
        default: [
          concurrency: 10,
          min_demand: 5,
          max_demand: 20
        ]
      ],
      batchers: [
        domain_events: [
          concurrency: 5,
          batch_size: 25,
          batch_timeout: 2000
        ],
        critical_events: [
          concurrency: 2,
          batch_size: 10,
          batch_timeout: 500
        ]
      ]
    )
  end

  @impl Broadway
  def handle_message(_processor, %Message{} = message, _context) do
    event_data = message.data

    try do
      processed_event = transform_event(event_data)

      # Route to appropriate batcher based on event type
      batcher = determine_batcher(processed_event)

      message
      |> Message.update_data(fn _ -> processed_event end)
      |> Message.put_batcher(batcher)
    rescue
      error ->
        Logger.error("Event processing failed: #{inspect(error)}")
        Message.failed(message, error)
    end
  end

  @impl Broadway
  def handle_batch(:domain_events, messages, _batch_info, _context) do
    Logger.info("Processing batch of #{length(messages)} domain events")

    events = Enum.map(messages, & &1.data)

    # Process events in batch
    case process_domain_events_batch(events) do
      :ok ->
        # Broadcast batch completion
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderflow:batch_completed",
          {:domain_events_processed, length(events)}
        )

        messages

      {:error, failed_events} ->
        # Mark failed events and retry successful ones
        handle_batch_failures(messages, failed_events)
    end
  end

  @impl Broadway
  def handle_batch(:critical_events, messages, _batch_info, _context) do
    Logger.warning("Processing batch of #{length(messages)} critical events")

    # Process critical events with higher priority
    events = Enum.map(messages, & &1.data)

    case process_critical_events_batch(events) do
      :ok ->
        # Immediate notification for critical events
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderflow:critical_processed",
          {:critical_events_processed, length(events), DateTime.utc_now()}
        )

        messages

      {:error, reason} ->
        Logger.error("Critical event batch failed: #{inspect(reason)}")

        # Send alerts for critical event failures
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderline:alerts:critical",
          {:critical_event_processing_failed, reason}
        )

        Enum.map(messages, &Message.failed(&1, reason))
    end
  end

  # Event transformation pipeline
  # New unified event shape from EventBus: %{type: atom(), payload: map(), domain: "...", timestamp: DateTime.t}
  defp transform_event(%{type: type, payload: payload} = event) when is_atom(type) do
    domain = Map.get(event, :domain) || infer_domain_from_payload(payload)
    base = %{
      "domain" => domain,
      "action" => to_string(type),
      "payload" => payload,
      "timestamp" => Map.get(event, :timestamp, DateTime.utc_now()),
      "severity" => Map.get(event, :severity, "normal")
    }

    base
    |> enrich_with_metadata()
    |> normalize_timestamps()
    |> validate_event_schema()
    |> tag_with_priority()
  end

  # Legacy already-normalized map with string keys domain/action
  defp transform_event(%{"domain" => _domain, "action" => _action} = event) do
    event
    |> enrich_with_metadata()
    |> normalize_timestamps()
    |> validate_event_schema()
    |> tag_with_priority()
  end

  # Fallback: wrap arbitrary map
  defp transform_event(other) when is_map(other) do
    %{
      type: Map.get(other, :type, :unknown_event),
      payload: other,
      timestamp: DateTime.utc_now()
    }
    |> transform_event()
  end

  defp infer_domain_from_payload(%{domain: d}) when is_binary(d), do: d
  defp infer_domain_from_payload(%{"domain" => d}) when is_binary(d), do: d
  defp infer_domain_from_payload(%{agent_id: _}), do: "thunderchief"
  defp infer_domain_from_payload(%{"agent_id" => _}), do: "thunderchief"
  defp infer_domain_from_payload(%{message_id: _}), do: "thunderblock"
  defp infer_domain_from_payload(_), do: "unknown"

  defp enrich_with_metadata(event) do
    Map.merge(event, %{
      "processing_node" => Node.self(),
      "processing_timestamp" => DateTime.utc_now(),
      "trace_id" => generate_trace_id()
    })
  end

  defp normalize_timestamps(event) do
    case Map.get(event, "timestamp") do
      nil ->
        Map.put(event, "timestamp", DateTime.utc_now())

      timestamp when is_binary(timestamp) ->
        Map.put(event, "timestamp", DateTime.from_iso8601(timestamp))

      timestamp ->
        Map.put(event, "timestamp", timestamp)
    end
  end

  defp validate_event_schema(event) do
    # Add schema validation here
    event
  end

  defp tag_with_priority(%{"severity" => severity} = event)
       when severity in ["critical", "error"] do
    Map.put(event, "priority", "high")
  end

  defp tag_with_priority(event), do: Map.put(event, "priority", "normal")

  defp determine_batcher(%{"priority" => "high"}), do: :critical_events
  defp determine_batcher(_event), do: :domain_events

  defp process_domain_events_batch(events) do
    # Group events by domain for efficient processing
    events
    |> Enum.group_by(& &1["domain"])
    |> Enum.reduce_while(:ok, fn {domain, domain_events}, _acc ->
      case process_domain_specific_events(domain, domain_events) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp process_critical_events_batch(events) do
    # Process critical events with immediate handling
    Enum.reduce_while(events, :ok, fn event, _acc ->
      case handle_critical_event(event) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp process_domain_specific_events("thundercore", events) do
    # Handle Thundercore events
    Enum.each(events, &route_to_thundercore/1)
    :ok
  end

  defp process_domain_specific_events("thunderblock", events) do
    # Handle Thundervault events
    Enum.each(events, &route_to_thundervault/1)
    :ok
  end

  defp process_domain_specific_events("thunderbolt", events) do
    # Handle Thunderbolt events
    Enum.each(events, &route_to_thunderbolt/1)
    :ok
  end

  defp process_domain_specific_events(domain, events) do
    Logger.info("Processing #{length(events)} events for domain: #{domain}")
    # Generic domain event processing
    :ok
  end

  defp handle_critical_event(%{"action" => "system_failure"} = event) do
    # Immediate system failure handling
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderline:system:emergency",
      {:system_failure, event}
    )

    :ok
  end

  defp handle_critical_event(%{"action" => "security_breach"} = event) do
    # Immediate security response
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderline:security:alert",
      {:security_breach, event}
    )

    :ok
  end

  defp handle_critical_event(event) do
    Logger.warning("Unhandled critical event: #{inspect(event)}")
    :ok
  end

  defp route_to_thundercore(event) do
    # Route to Thundercore domain
    %{
      "event" => event,
      "domain" => "thundercore"
    }
    |> Thunderchief.Jobs.DomainProcessor.new()
    |> Oban.insert()
  end

  defp route_to_thundervault(event) do
    # Route to Thundervault domain
    %{
      "event" => event,
      "domain" => "thunderblock"
    }
    |> Thunderchief.Jobs.DomainProcessor.new()
    |> Oban.insert()
  end

  defp route_to_thunderbolt(event) do
    # Route to Thunderbolt domain
    %{
      "event" => event,
      "domain" => "thunderbolt"
    }
    |> Thunderchief.Jobs.DomainProcessor.new()
    |> Oban.insert()
  end

  defp handle_batch_failures(messages, _failed_events) do
    # Implementation for handling partial batch failures
    messages
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
