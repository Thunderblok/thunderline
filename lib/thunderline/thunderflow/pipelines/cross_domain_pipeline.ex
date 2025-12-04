defmodule Thunderline.Thunderflow.Pipelines.CrossDomainPipeline do
  @moduledoc """
  Broadway Pipeline for Cross-Domain Event Processing

  Handles events that need to be routed between different Thunderline domains
  with proper batching, transformation, and dead letter queue handling.
  """

  use Broadway

  alias Broadway.Message
  alias Phoenix.PubSub
  alias Thunderline.Event
  require Logger

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {Thunderline.Thunderflow.MnesiaProducer,
           [
             table: Thunderline.Thunderflow.CrossDomainEvents,
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
        thundercrown_events: [
          concurrency: 3,
          batch_size: 20,
          batch_timeout: 1500
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
  def handle_message(_processor, %Message{} = message, _context) do
    try do
      # Normalize to canonical event struct
      canonical_event =
        case message.data do
          bin when is_binary(bin) ->
            bin |> Jason.decode!() |> Event.normalize!()

          data when is_map(data) ->
            Event.normalize!(data)

          other ->
            Event.normalize!(%{"type" => "unknown", "payload" => other})
        end

      # Apply transformations to canonical event
      processed_event =
        canonical_event
        |> apply_transformation_rules()
        |> Event.increment_hop_count()
        |> Event.put_metadata("processing_node", Node.self())
        |> Event.put_metadata("processed_at", DateTime.utc_now())

      # Determine target domain batcher
      batcher = determine_target_batcher(processed_event)

      message
      |> Message.update_data(fn _ -> processed_event end)
      |> Message.put_batcher(batcher)
    rescue
      error ->
        Logger.error("Cross-domain event processing failed: #{inspect(error)}")

        # Send to dead letter queue
        send_to_dead_letter_queue(message.data, error)

        Message.failed(message, error)
    end
  end

  @impl Broadway
  def handle_batch(:thundercrown_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} ThunderCrown events")

    events = Enum.map(messages, & &1.data)

    # Emit fanout telemetry for single-domain routing
    Enum.each(events, fn event ->
      :telemetry.execute(
        [:thunderline, :cross_domain, :fanout],
        %{target_count: 1},
        %{event_type: to_string(event.type), source_domain: event.source_domain}
      )
    end)

    case route_to_thundercrown_batch(events) do
      :ok ->
        notify_domain_processing_complete("thundercrown", length(events))
        messages

      {:error, failed_events} ->
        handle_routing_failures("thundercrown", messages, failed_events)
    end
  end

  @impl Broadway
  def handle_batch(:thunderbolt_events, messages, _batch_info, _context) do
    Logger.info("Processing #{length(messages)} ThunderBolt events")

    events = Enum.map(messages, & &1.data)

    # Emit fanout telemetry for single-domain routing
    Enum.each(events, fn event ->
      :telemetry.execute(
        [:thunderline, :cross_domain, :fanout],
        %{target_count: 1},
        %{event_type: to_string(event.type), source_domain: event.source_domain}
      )
    end)

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
    Logger.info("Processing #{length(messages)} ThunderBlock events")

    events = Enum.map(messages, & &1.data)

    # Emit fanout telemetry for single-domain routing
    Enum.each(events, fn event ->
      :telemetry.execute(
        [:thunderline, :cross_domain, :fanout],
        %{target_count: 1},
        %{event_type: to_string(event.type), source_domain: event.source_domain}
      )
    end)

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

    # Emit fanout telemetry for broadcast events (high fanout)
    Enum.each(events, fn event ->
      :telemetry.execute(
        [:thunderline, :cross_domain, :fanout],
        # broadcast_targets length
        %{target_count: 3},
        %{event_type: to_string(event.type), source_domain: event.source_domain}
      )
    end)

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

  defp apply_transformation_rules(%Event{metadata: %{"transformation_rules" => rules}} = event)
       when is_list(rules) do
    Enum.reduce(rules, event, &apply_transformation_rule/2)
  end

  defp apply_transformation_rules(%Event{} = event), do: event

  defp apply_transformation_rule(
         %{"type" => "field_mapping", "mappings" => mappings},
         %Event{} = event
       ) do
    # Apply field mappings for cross-domain compatibility in payload
    updated_payload =
      Enum.reduce(mappings, event.payload, fn {old_field, new_field}, acc ->
        case Map.pop(acc, old_field) do
          {nil, acc} -> acc
          {value, acc} -> Map.put(acc, new_field, value)
        end
      end)

    %{event | payload: updated_payload}
  end

  defp apply_transformation_rule(
         %{"type" => "data_enrichment", "source" => source},
         %Event{} = event
       ) do
    # Enrich event data from external sources
    enrichment_data = fetch_enrichment_data(source, event)
    Event.put_metadata(event, "enrichment", enrichment_data)
  end

  defp apply_transformation_rule(_rule, %Event{} = event), do: event

  defp determine_target_batcher(%Event{target_domain: "thunderbolt"}), do: :thunderbolt_events
  defp determine_target_batcher(%Event{target_domain: "thunderblock"}), do: :thunderblock_events
  defp determine_target_batcher(%Event{target_domain: "thundercrown"}), do: :thundercrown_events
  defp determine_target_batcher(%Event{target_domain: "broadcast"}), do: :broadcast_events
  defp determine_target_batcher(%Event{}), do: :broadcast_events

  # Domain-specific routing implementations
  defp route_to_thundercrown_batch(events) do
    # Convert canonical events to maps for job serialization
    event_maps = Enum.map(events, &Event.to_map/1)

    job_params = %{
      "events" => event_maps,
      "target_domain" => "thundercrown",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now(),
      "operation" => "process_domain_event"
    }

    case Thunderline.Thunderflow.Jobs.ThunderCrownProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_to_thunderbolt_batch(events) do
    # Convert canonical events to maps for job serialization
    event_maps = Enum.map(events, &Event.to_map/1)

    job_params = %{
      "events" => event_maps,
      "target_domain" => "thunderbolt",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now(),
      "operation" => "compute_task"
    }

    case Thunderline.Thunderflow.Jobs.ThunderBoltProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_to_thunderblock_batch(events) do
    # Convert canonical events to maps for job serialization
    event_maps = Enum.map(events, &Event.to_map/1)

    job_params = %{
      "events" => event_maps,
      "target_domain" => "thunderblock",
      "batch_size" => length(events),
      "processing_timestamp" => DateTime.utc_now(),
      "operation" => "vault_sync"
    }

    case Thunderline.Thunderflow.Jobs.ThunderBlockProcessor.new(job_params) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_broadcast_events_batch(events) do
    # Process events that need to go to multiple domains
    broadcast_targets = ["thundercrown", "thunderblock", "thunderbolt"]

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

  defp create_domain_job(domain, params) do
    # Protect domain job creation with circuit breaker
    Thunderline.Thunderflow.Support.CircuitBreaker.call({:domain, domain}, fn ->
      case domain do
        "thunderbolt" ->
          Thunderline.Thunderflow.Jobs.ThunderBoltProcessor.new(params) |> Oban.insert()

        "thunderblock" ->
          Thunderline.Thunderflow.Jobs.ThunderBlockProcessor.new(params) |> Oban.insert()

        "thundercrown" ->
          Thunderline.Thunderflow.Jobs.ThunderCrownProcessor.new(params) |> Oban.insert()

        _ ->
          {:error, :unknown_domain}
      end
    end)
  end

  defp notify_domain_processing_complete(domain, event_count) do
    PubSub.broadcast(
      Thunderline.PubSub,
      "thunderflow:domain_processing",
      {:domain_events_processed,
       %{
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
    |> Thunderline.Thunderflow.Jobs.RetryProcessor.new(scheduled_at: retry_event["retry_at"])
    |> Oban.insert()
  end

  defp fetch_enrichment_data(_source, _event) do
    # Placeholder for data enrichment
    %{"enriched_at" => DateTime.utc_now()}
  end
end
