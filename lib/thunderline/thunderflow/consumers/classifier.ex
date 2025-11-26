defmodule Thunderline.Thunderflow.Consumers.Classifier do
  @moduledoc """
  Broadway consumer that processes file ingestion events and classifies content.

  Listens for `ui.command.ingest.received` events, invokes Magika classification,
  and emits `system.ingest.classified` events on success.

  ## Event Flow

  Input:  `ui.command.ingest.received` - Raw file bytes from upload
  Output: `system.ingest.classified` - Content type, confidence, SHA256

  ## Dead Letter Queue

  Failed classifications are routed to DLQ with error metadata:
  - CLI failures
  - File read errors
  - Timeout errors
  - Invalid event payloads

  ## Configuration

      config :thunderline, Thunderline.Thunderflow.Consumers.Classifier,
        producer: Thunderline.EventBus,
        batch_size: 10,
        batch_timeout: 1_000,
        concurrency: 4

  ## Supervision

  Add to application supervision tree:

      {Thunderline.Thunderflow.Consumers.Classifier, []}
  """

  use Broadway

  alias Broadway.Message
  alias Thunderline.Thundergate.Magika
  alias Thunderline.Event

  require Logger

  @default_config [
    batch_size: 10,
    batch_timeout: 1_000,
    concurrency: 4,
    max_demand: 10
  ]

  def start_link(opts) do
    config = Application.get_env(:thunderline, __MODULE__, @default_config)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {Thunderline.Thunderflow.MnesiaProducer,
           table: Thunderline.Thunderflow.MnesiaProducer,
           poll_interval: 1_000,
           max_batch_size: Keyword.get(config, :batch_size, 10),
           broadway_name: __MODULE__},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: Keyword.get(config, :concurrency, 4),
          max_demand: Keyword.get(config, :max_demand, 10)
        ]
      ],
      batchers: [
        default: [
          batch_size: Keyword.get(config, :batch_size, 10),
          batch_timeout: Keyword.get(config, :batch_timeout, 1_000)
        ]
      ],
      context: opts
    )
  end

  @impl true
  def handle_message(_processor, message, _context) do
    case process_ingestion_event(message.data) do
      {:ok, classification} ->
        message
        |> Message.put_data(classification)
        |> Message.put_batch_key(:default)

      {:error, reason} ->
        Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    # Acknowledge all successful classifications
    Enum.each(messages, fn message ->
      Logger.debug("Classified file",
        content_type: message.data.content_type,
        confidence: message.data.confidence,
        filename: message.data.filename
      )
    end)

    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn message ->
      route_to_dlq(message)
    end)

    messages
  end

  # Private functions

  defp process_ingestion_event(event) do
    with {:ok, validated} <- validate_event(event) do
      classify_content(validated)
    end
  end

  defp validate_event(%Event{type: "ui.command.ingest.received"} = event) do
    # Extract required fields from event data
    case event.data do
      %{bytes: bytes, filename: filename} when is_binary(bytes) and is_binary(filename) ->
        correlation_id = get_in(event.metadata, [:correlation_id]) || event.id
        causation_id = event.id

        {:ok,
         %{
           bytes: bytes,
           filename: filename,
           correlation_id: correlation_id,
           causation_id: causation_id
         }}

      %{path: path} when is_binary(path) ->
        correlation_id = get_in(event.metadata, [:correlation_id]) || event.id
        causation_id = event.id

        {:ok,
         %{
           path: path,
           correlation_id: correlation_id,
           causation_id: causation_id
         }}

      _other ->
        {:error, :invalid_event_payload}
    end
  end

  # Handle new taxonomy format (using 'name' instead of 'type')
  defp validate_event(%Event{name: name} = event)
       when name in ["ui.command.ingest.received", "ui.command.ingest"] do
    # Extract required fields from event payload (new taxonomy uses 'payload' not 'data')
    case event.payload do
      %{bytes: bytes, filename: filename} when is_binary(bytes) and is_binary(filename) ->
        correlation_id = event.correlation_id || event.id
        causation_id = event.id

        {:ok,
         %{
           bytes: bytes,
           filename: filename,
           correlation_id: correlation_id,
           causation_id: causation_id
         }}

      %{path: path} when is_binary(path) ->
        correlation_id = event.correlation_id || event.id
        causation_id = event.id

        {:ok,
         %{
           path: path,
           correlation_id: correlation_id,
           causation_id: causation_id
         }}

      _other ->
        {:error, :invalid_event_payload}
    end
  end

  defp validate_event(%Event{} = event) do
    {:error, {:unexpected_event_type, event.type}}
  end

  defp validate_event(other) do
    {:error, {:invalid_event, other}}
  end

  defp classify_content(%{bytes: bytes, filename: filename} = params) do
    Magika.classify_bytes(
      bytes,
      filename,
      correlation_id: params.correlation_id,
      causation_id: params.causation_id,
      emit_event?: true
    )
  end

  defp classify_content(%{path: path} = params) do
    Magika.classify_file(
      path,
      correlation_id: params.correlation_id,
      causation_id: params.causation_id,
      emit_event?: true
    )
  end

  defp route_to_dlq(message) do
    error_metadata = %{
      reason: message.status,
      original_event: message.data,
      timestamp: DateTime.utc_now(),
      processor: __MODULE__
    }

    dlq_event_attrs = %{
      type: :dlq_classification_failed,
      source: :flow,
      payload: %{
        error: inspect(message.status),
        event_id: extract_event_id(message.data),
        processor: "thunderflow.consumers.classifier"
      },
      metadata: error_metadata
    }

    case Event.new(dlq_event_attrs) do
      {:ok, dlq_event} ->
        Thunderline.EventBus.publish_event(dlq_event)

        Logger.warning("Classification failed, routed to DLQ",
          error: inspect(message.status),
          event: extract_event_id(message.data)
        )

      {:error, reason} ->
        Logger.error("Failed to create DLQ event", reason: inspect(reason))
    end
  end

  defp extract_event_id(%Event{id: id}), do: id
  defp extract_event_id(_), do: nil
end
