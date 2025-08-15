defmodule Thunderline.Thunderflow.Pipelines.CrossDomainPipeline do
  @moduledoc """
  Broadway Pipeline for Cross-Domain Event Processing

  Handles events that need to be routed between different Thunderline domains
  with proper batching, transformation, and dead letter queue handling.
  """

  use Broadway

  alias Broadway.Message
  alias Phoenix.PubSub
  require Logger

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Thunderflow.MnesiaProducer, [
          table: Thunderflow.CrossDomainEvents,
          poll_interval: 800,
          max_batch_size: 40,
          broadway_name: __MODULE__
        ]}
      ],
      processors: [
        default: [
          concurrency: 8,
          min_demand: 5,
          max_demand: 15
        ]
      ],
      batchers: [
        thundercore_events: [
          concurrency: 3,
          batch_size: 20,
          batch_timeout: 1500
        ],
        thundervault_events: [
          concurrency: 3,
          batch_size: 20,
          batch_timeout: 1500
        ],
        thunderbolt_events: [
          concurrency: 2,
          batch_size: 15,
          batch_timeout: 1000
        ],
        thunderblock_events: [
          concurrency: 4,
          batch_size: 25,
          batch_timeout: 2000
        ],
        broadcast_events: [
          concurrency: 2,
          batch_size: 50,
          batch_timeout: 3000
        ]
      ]
    )
  end

  @impl Broadway
  def handle_message(processor, %Message{} = message, _context) do
    event_data = Jason.decode!(message.data)

    try do
      processed_event =
        event_data
        |> validate_cross_domain_event()
        |> enrich_with_routing_metadata()
        |> apply_transformation_rules()

      # Determine target domain batcher
      batcher = determine_target_batcher(processed_event)

      message
      |> Message.update_data(fn _ -> processed_event end)
      |> Message.put_batcher(batcher)
    rescue
      error ->
        Logger.error("Cross-domain event processing failed: #{inspect(error)}")

        # Send to dead letter queue
        send_to_dead_letter_queue(event_data, error)

        Message.failed(message, error)
    end
  end

  @impl Broadway
  def handle_batch(:thundercore_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} Thundercore events")

    events = Enum.map(messages, & &1.data)

    case route_to_thundercore_batch(events) do
      :ok ->
        notify_domain_processing_complete("thundercore", length(events))
        messages

      {:error, failed_events} ->
        handle_routing_failures("thundercore", messages, failed_events)
    end
  end

  @impl Broadway
  def handle_batch(:thundervault_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} Thundervault events")

    events = Enum.map(messages, & &1.data)

    case route_to_thundervault_batch(events) do
      :ok ->
        notify_domain_processing_complete("thunderblock", length(events))
        messages

      {:error, failed_events} ->
        handle_routing_failures("thunderblock", messages, failed_events)
    end
  end

  @impl Broadway
  def handle_batch(:thunderbolt_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} Thunderbolt events")

    events = Enum.map(messages, & &1.data)

    case route_to_thunderbolt_batch(events) do
      :ok ->
        notify_domain_processing_complete("thunderbolt", length(events))
        messages

      {:error, failed_events} ->
        handle_routing_failures("thunderbolt", messages, failed_events)
    end
  end

  @impl Broadway
  def handle_batch(:thunderblock_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} Thunderblock events")

    events = Enum.map(messages, & &1.data)

    case route_to_thunderblock_batch(events) do
      :ok ->
        notify_domain_processing_complete("thunderblock", length(events))
        messages

      {:error, failed_events} ->
        handle_routing_failures("thunderblock", messages, failed_events)
    end
  end

  @impl Broadway
  def handle_batch(:broadcast_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} broadcast events")

    events = Enum.map(messages, & &1.data)

    # These events go to multiple domains
    case handle_broadcast_events_batch(events) do
      :ok ->
        PubSub.broadcast(
          Thunderline.PubSub,
          "thunderflow:broadcast_completed",
          {:broadcast_events_processed, length(events)}
        )
        messages

      {:error, reason} ->
        Logger.error("Broadcast event batch failed: #{inspect(reason)}")
        Enum.map(messages, &Message.failed(&1, reason))
    end
  end

  # Event validation and transformation
  defp validate_cross_domain_event(event) do
    required_fields = ["source_domain", "target_domain", "action", "data"]

    missing_fields = required_fields -- Map.keys(event)

    if missing_fields != [] do
      raise "Missing required fields: #{inspect(missing_fields)}"
    end

    event
  end

  defp enrich_with_routing_metadata(event) do
    Map.merge(event, %{
      "routing_timestamp" => DateTime.utc_now(),
      "processing_node" => Node.self(),
      "correlation_id" => generate_correlation_id(),
      "hop_count" => Map.get(event, "hop_count", 0) + 1
    })
  end

  defp apply_transformation_rules(%{"transformation_rules" => rules} = event) when is_list(rules) do
    Enum.reduce(rules, event, &apply_transformation_rule/2)
  end
  defp apply_transformation_rules(event), do: event

  defp apply_transformation_rule(%{"type" => "field_mapping", "mappings" => mappings}, event) do
    # Apply field mappings for cross-domain compatibility
    Enum.reduce(mappings, event, fn {old_field, new_field}, acc ->
      case Map.pop(acc, old_field) do
        {nil, acc} -> acc
        {value, acc} -> Map.put(acc, new_field, value)
      end
    end)
  end

  defp apply_transformation_rule(%{"type" => "data_enrichment", "source" => source}, event) do
    # Enrich event data from external sources
    enrichment_data = fetch_enrichment_data(source, event)
    Map.put(event, "enrichment", enrichment_data)
  end

  defp apply_transformation_rule(_rule, event), do: event

  defp determine_target_batcher(%{"target_domain" => "thundercore"}), do: :thundercore_events
  defp determine_target_batcher(%{"target_domain" => "thunderblock"}), do: :thundervault_events
  defp determine_target_batcher(%{"target_domain" => "thunderbolt"}), do: :thunderbolt_events
  defp determine_target_batcher(%{"target_domain" => "thunderblock"}), do: :thunderblock_events
  defp determine_target_batcher(%{"target_domain" => "broadcast"}), do: :broadcast_events
  defp determine_target_batcher(_), do: :broadcast_events

  # Domain-specific routing implementations
  defp route_to_thundercore_batch(events) do
    job_params = %{
      "events" => events,
      "target_domain" => "thundercore",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now()
    }

    case Thunderchief.Jobs.ThundercoreProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_to_thundervault_batch(events) do
    job_params = %{
      "events" => events,
      "target_domain" => "thunderblock",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now()
    }

    case Thunderchief.Jobs.ThundervaultProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_to_thunderbolt_batch(events) do
    job_params = %{
      "events" => events,
      "target_domain" => "thunderbolt",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now()
    }

    case Thunderchief.Jobs.ThunderboltProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_to_thunderblock_batch(events) do
    job_params = %{
      "events" => events,
      "target_domain" => "thunderblock",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now()
    }

    case Thunderchief.Jobs.ThunderblockProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_broadcast_events_batch(events) do
    # Process events that need to go to multiple domains
    broadcast_targets = ["thundercore", "thunderblock", "thunderbolt", "thunderblock"]

    Enum.reduce_while(broadcast_targets, :ok, fn target, _acc ->
      job_params = %{
        "events" => events,
        "target_domain" => target,
        "is_broadcast" => true,
        "batch_size" => length(events),
        "processing_timestamp" => DateTime.utc_now()
      }

      case create_domain_job(target, job_params) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_domain_job("thundercore", params), do: Thunderchief.Jobs.ThundercoreProcessor.new(params) |> Oban.insert()
  defp create_domain_job("thunderblock", params), do: Thunderchief.Jobs.ThundervaultProcessor.new(params) |> Oban.insert()
  defp create_domain_job("thunderbolt", params), do: Thunderchief.Jobs.ThunderboltProcessor.new(params) |> Oban.insert()
  defp create_domain_job("thunderblock", params), do: Thunderchief.Jobs.ThunderblockProcessor.new(params) |> Oban.insert()
  defp create_domain_job(_, _), do: {:error, :unknown_domain}

  defp notify_domain_processing_complete(domain, event_count) do
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderflow:domain_processing",
      {:domain_events_processed, %{
        domain: domain,
        event_count: event_count,
        timestamp: DateTime.utc_now()
      }}
    )
  end

  defp handle_routing_failures(domain, messages, failed_events) do
    Logger.error("Failed to route #{length(failed_events)} events to #{domain}")

    # Send failed events to retry queue
    Enum.each(failed_events, &send_to_retry_queue(&1, domain))

    # Return appropriate message statuses
    messages
  end

  defp send_to_dead_letter_queue(event, error) do
    dead_letter_event = %{
      "original_event" => event,
      "error" => inspect(error),
      "failed_at" => DateTime.utc_now(),
      "processing_node" => Node.self()
    }

    # This would typically go to a dead letter queue system
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderflow:dead_letter",
      {:dead_letter_event, dead_letter_event}
    )
  end

  defp send_to_retry_queue(event, domain) do
    retry_event = %{
      "event" => event,
      "domain" => domain,
      "retry_at" => DateTime.add(DateTime.utc_now(), 30, :second),
      "retry_count" => Map.get(event, "retry_count", 0) + 1
    }

    # Schedule retry via Oban
    %{"retry_event" => retry_event}
    |> Thunderchief.Jobs.RetryProcessor.new(scheduled_at: retry_event["retry_at"])
    |> Oban.insert()
  end

  defp fetch_enrichment_data(_source, _event) do
    # Placeholder for data enrichment
    %{"enriched_at" => DateTime.utc_now()}
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
