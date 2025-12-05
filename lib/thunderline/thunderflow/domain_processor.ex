defmodule Thunderline.Thunderflow.DomainProcessor do
  @moduledoc """
  Behaviour and `__using__` macro for Broadway-based domain event processors.

  HC-12: Eliminates repeated Broadway consumer boilerplate across pipelines.

  ## Why This Exists

  Each Broadway pipeline (EventPipeline, CrossDomainPipeline, RealTimePipeline, Classifier)
  repeats ~100+ lines of setup: producer config, processor config, batchers, telemetry hooks,
  DLQ routing, and error handling. This behaviour extracts the common patterns.

  ## Quick Start

      defmodule MyApp.MyDomainPipeline do
        use Thunderline.Thunderflow.DomainProcessor,
          name: :my_domain_pipeline,
          queue: :domain_events,
          batchers: [:events, :critical]

        @impl Thunderline.Thunderflow.DomainProcessor
        def process_event(event, context) do
          # Your domain-specific logic here
          {:ok, event, :events}  # Return batcher key
        end

        @impl Thunderline.Thunderflow.DomainProcessor
        def handle_event_batch(:events, events, _batch_info, _context) do
          # Process batch of events
          events
        end
      end

  ## Callbacks

  Required:
  - `process_event/2` - Transform a single event, return `{:ok, data, batcher_key}` or `{:error, reason}`
  - `handle_event_batch/4` - Process a batch of events for a specific batcher

  Optional:
  - `batcher_config/1` - Override default batcher configuration
  - `producer_config/0` - Override default MnesiaProducer configuration
  - `processor_config/0` - Override default processor configuration
  - `handle_event_failed/2` - Custom failure handling (default routes to DLQ)
  - `telemetry_prefix/0` - Custom telemetry prefix (default: `[:thunderline, :domain_processor, :your_name]`)

  ## Built-in Features

  - **Telemetry**: Automatic instrumentation on message start/stop/error
  - **DLQ**: Failed messages routed to dead letter queue via EventBus
  - **Retry**: Integration with RetryPolicy for transient failures
  - **Normalization**: Events normalized to canonical `Thunderline.Event` struct
  - **Backpressure**: Sensible defaults for concurrency and demand

  ## Options

  - `:name` - Required. Atom name for the pipeline (used in telemetry + supervision)
  - `:queue` - Oban queue for related jobs (default: `:domain_events`)
  - `:batchers` - List of batcher names (default: `[:default]`)
  - `:batch_size` - Events per batch (default: `25`)
  - `:batch_timeout` - Max wait time for batch (default: `1_000` ms)
  - `:concurrency` - Processor concurrency (default: `4`)
  - `:max_demand` - Max events to pull from producer (default: `10`)
  """

  require Logger

  @type batcher_key :: atom()
  @type context :: map()
  @type batch_info :: Broadway.BatchInfo.t()

  @doc """
  Process a single event. Return the transformed data and target batcher.

  Returns:
  - `{:ok, transformed_data, batcher_key}` - Success, route to batcher
  - `{:error, reason}` - Failure, route to DLQ
  """
  @callback process_event(event :: term(), context :: context()) ::
              {:ok, term(), batcher_key()} | {:error, term()}

  @doc """
  Handle a batch of events for a specific batcher.

  Called after events are grouped by batcher key. Perform side effects here
  (PubSub broadcasts, database writes, Oban job enqueuing).

  Must return the list of messages (potentially modified).
  """
  @callback handle_event_batch(
              batcher :: batcher_key(),
              messages :: [Broadway.Message.t()],
              batch_info :: batch_info(),
              context :: context()
            ) :: [Broadway.Message.t()]

  @doc """
  Optional: Custom telemetry prefix. Default: `[:thunderline, :domain_processor, :name]`

  Override via `defoverridable` in using module.
  """
  @callback telemetry_prefix() :: [atom()]

  @optional_callbacks telemetry_prefix: 0

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      use Broadway

      alias Broadway.Message
      alias Thunderline.Event
      alias Thunderline.EventBus
      alias Thunderline.Thunderflow.RetryPolicy

      require Logger

      @behaviour Thunderline.Thunderflow.DomainProcessor

      @__dp_name Keyword.fetch!(unquote(opts), :name)
      @__dp_queue Keyword.get(unquote(opts), :queue, :domain_events)
      @__dp_batchers Keyword.get(unquote(opts), :batchers, [:default])
      @__dp_batch_size Keyword.get(unquote(opts), :batch_size, 25)
      @__dp_batch_timeout Keyword.get(unquote(opts), :batch_timeout, 1_000)
      @__dp_concurrency Keyword.get(unquote(opts), :concurrency, 4)
      @__dp_max_demand Keyword.get(unquote(opts), :max_demand, 10)

      @__dp_tele_prefix [:thunderline, :domain_processor, @__dp_name]

      # --- Start Link ---

      @doc """
      Starts the Broadway pipeline.

      Options are passed to the context and can be accessed in callbacks.
      """
      def start_link(opts \\ []) do
        Broadway.start_link(__MODULE__,
          name: __MODULE__,
          producer: build_producer_config(),
          processors: [default: build_processor_config()],
          batchers: build_batcher_configs(),
          context: Map.new(opts)
        )
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor,
          restart: :permanent
        }
      end

      # --- Broadway Callbacks ---

      @impl Broadway
      def handle_message(_processor, message, context) do
        start_time = System.monotonic_time()
        event = message.data

        :telemetry.execute(
          @__dp_tele_prefix ++ [:message, :start],
          %{system_time: System.system_time()},
          %{event: event_metadata(event)}
        )

        try do
          case process_event(event, context) do
            {:ok, transformed, batcher_key} when batcher_key in @__dp_batchers ->
              duration = System.monotonic_time() - start_time

              :telemetry.execute(
                @__dp_tele_prefix ++ [:message, :stop],
                %{duration: duration},
                %{batcher: batcher_key, event: event_metadata(event)}
              )

              message
              |> Message.put_data(transformed)
              |> Message.put_batch_key(batcher_key)

            {:ok, transformed, batcher_key} ->
              Logger.warning(
                "[#{@__dp_name}] Unknown batcher #{inspect(batcher_key)}, using :default"
              )

              message
              |> Message.put_data(transformed)
              |> Message.put_batch_key(:default)

            {:error, reason} ->
              duration = System.monotonic_time() - start_time

              :telemetry.execute(
                @__dp_tele_prefix ++ [:message, :error],
                %{duration: duration},
                %{reason: reason, event: event_metadata(event)}
              )

              Message.failed(message, reason)
          end
        rescue
          e ->
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              @__dp_tele_prefix ++ [:message, :exception],
              %{duration: duration},
              %{exception: e, stacktrace: __STACKTRACE__, event: event_metadata(event)}
            )

            Logger.error(
              "[#{@__dp_name}] Exception processing event: #{Exception.format(:error, e, __STACKTRACE__)}"
            )

            Message.failed(message, {:exception, e})
        end
      end

      @impl Broadway
      def handle_batch(batcher, messages, batch_info, context) do
        start_time = System.monotonic_time()

        :telemetry.execute(
          @__dp_tele_prefix ++ [:batch, :start],
          %{count: length(messages), system_time: System.system_time()},
          %{batcher: batcher}
        )

        try do
          result = handle_event_batch(batcher, messages, batch_info, context)
          duration = System.monotonic_time() - start_time
          duration_ms = System.convert_time_unit(duration, :native, :millisecond)

          :telemetry.execute(
            @__dp_tele_prefix ++ [:batch, :stop],
            %{duration: duration, count: length(messages)},
            %{batcher: batcher}
          )

          # Record pipeline throughput telemetry
          pipeline = infer_pipeline_type()

          Thunderline.Thunderflow.PipelineTelemetry.record_throughput(
            pipeline,
            length(messages),
            duration_ms
          )

          result
        rescue
          e ->
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              @__dp_tele_prefix ++ [:batch, :exception],
              %{duration: duration, count: length(messages)},
              %{batcher: batcher, exception: e}
            )

            # Record pipeline failure telemetry
            pipeline = infer_pipeline_type()

            Thunderline.Thunderflow.PipelineTelemetry.record_failure(
              pipeline,
              {:batch_exception, e.__struct__},
              nil,
              :batcher
            )

            Logger.error(
              "[#{@__dp_name}] Exception in batch handler: #{Exception.format(:error, e, __STACKTRACE__)}"
            )

            # Return messages as-is; they'll be marked failed by Broadway
            messages
        end
      end

      @impl Broadway
      def handle_failed(messages, context) do
        Enum.map(messages, fn message ->
          do_handle_event_failed(message, context)
        end)
      end

      # --- Default Implementations (Overridable) ---

      @doc false
      def do_handle_event_failed(message, _context) do
        error_metadata = %{
          reason: inspect(message.status),
          original_event: message.data,
          timestamp: DateTime.utc_now(),
          processor: __MODULE__,
          pipeline: @__dp_name
        }

        dlq_attrs = %{
          name: "system.dlq.#{@__dp_name}.failed",
          type: :dlq_event_failed,
          source: :flow,
          payload: %{
            error: inspect(message.status),
            event_id: extract_event_id(message.data),
            processor: inspect(__MODULE__),
            pipeline: @__dp_name
          },
          meta: error_metadata
        }

        # Record pipeline failure telemetry
        pipeline = infer_pipeline_type()
        event_name = extract_event_name(message.data)

        Thunderline.Thunderflow.PipelineTelemetry.record_failure(
          pipeline,
          message.status,
          event_name,
          :processor
        )

        case Event.new(dlq_attrs) do
          {:ok, dlq_event} ->
            case EventBus.publish_event(dlq_event) do
              {:ok, _} ->
                :telemetry.execute(
                  @__dp_tele_prefix ++ [:dlq, :routed],
                  %{count: 1},
                  %{reason: message.status}
                )

              {:error, reason} ->
                Logger.error("[#{@__dp_name}] Failed to publish DLQ event: #{inspect(reason)}")
            end

          {:error, reason} ->
            Logger.error("[#{@__dp_name}] Failed to create DLQ event: #{inspect(reason)}")
        end

        message
      end

      @doc false
      def do_producer_config, do: []

      @doc false
      def do_processor_config, do: []

      @doc false
      def do_batcher_config(_batcher), do: []

      # Allow overriding these defaults
      defoverridable do_handle_event_failed: 2,
                     do_producer_config: 0,
                     do_processor_config: 0,
                     do_batcher_config: 1

      # --- Config Builders ---

      defp build_producer_config do
        base = [
          module:
            {Thunderline.Thunderflow.MnesiaProducer,
             table: Thunderline.Thunderflow.MnesiaProducer,
             poll_interval: 1_000,
             max_batch_size: @__dp_batch_size,
             broadway_name: __MODULE__},
          concurrency: 1
        ]

        Keyword.merge(base, do_producer_config())
      end

      defp build_processor_config do
        base = [
          concurrency: @__dp_concurrency,
          max_demand: @__dp_max_demand
        ]

        Keyword.merge(base, do_processor_config())
      end

      defp build_batcher_configs do
        Enum.map(@__dp_batchers, fn batcher ->
          base = [
            batch_size: @__dp_batch_size,
            batch_timeout: @__dp_batch_timeout
          ]

          {batcher, Keyword.merge(base, do_batcher_config(batcher))}
        end)
      end

      # --- Helpers ---

      defp event_metadata(%Event{} = event) do
        %{
          id: event.id,
          name: event.name,
          type: event.type,
          source: event.source
        }
      end

      defp event_metadata(event) when is_map(event) do
        %{
          id: Map.get(event, :id) || Map.get(event, "id"),
          name: Map.get(event, :name) || Map.get(event, "name"),
          type: Map.get(event, :type) || Map.get(event, "type")
        }
      end

      defp event_metadata(_), do: %{}

      defp extract_event_id(%Event{id: id}), do: id
      defp extract_event_id(%{id: id}), do: id
      defp extract_event_id(%{"id" => id}), do: id
      defp extract_event_id(_), do: nil

      defp extract_event_name(%Event{name: name}), do: name
      defp extract_event_name(%{name: name}), do: name
      defp extract_event_name(%{"name" => name}), do: name
      defp extract_event_name(_), do: nil

      # Infer pipeline type from processor name
      # Follows naming convention: realtime_ prefix = :realtime, cross_domain_ = :cross_domain
      defp infer_pipeline_type do
        name_str = Atom.to_string(@__dp_name)

        cond do
          String.starts_with?(name_str, "realtime_") -> :realtime
          String.starts_with?(name_str, "cross_domain_") -> :cross_domain
          String.starts_with?(name_str, "priority_") -> :realtime
          String.starts_with?(name_str, "batch_") -> :general
          true -> :general
        end
      end

      # --- Telemetry Prefix Override ---

      @doc false
      def __telemetry_prefix__, do: @__dp_tele_prefix

      @impl Thunderline.Thunderflow.DomainProcessor
      def telemetry_prefix, do: @__dp_tele_prefix

      # Allow override of telemetry_prefix
      defoverridable telemetry_prefix: 0
    end
  end

  # --- Module Functions ---

  @doc """
  Normalize an event to the canonical `Thunderline.Event` struct.

  Handles both map and struct inputs, extracting standard fields.
  """
  @spec normalize_event(term()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  def normalize_event(%Thunderline.Event{} = event), do: {:ok, event}

  def normalize_event(event) when is_map(event) do
    source_raw = Map.get(event, :source) || Map.get(event, "source") || :unknown
    source = if is_binary(source_raw), do: String.to_existing_atom(source_raw), else: source_raw

    type_raw = Map.get(event, :type) || Map.get(event, "type") || :unknown
    type = if is_binary(type_raw), do: String.to_existing_atom(type_raw), else: type_raw

    attrs = %{
      name: Map.get(event, :name) || Map.get(event, "name") || "unknown",
      type: type,
      source: source,
      payload: Map.get(event, :payload) || Map.get(event, "payload") || %{},
      meta: Map.get(event, :meta) || Map.get(event, "meta") || %{}
    }

    Thunderline.Event.new(attrs)
  rescue
    ArgumentError ->
      # String.to_existing_atom failed - invalid source
      {:error, {:invalid_source, Map.get(event, :source) || Map.get(event, "source")}}
  end

  def normalize_event(other) do
    {:error, {:invalid_event, other}}
  end

  @doc """
  Broadcast an event via PubSub to a specific topic.

  Convenience wrapper for common broadcast pattern in batch handlers.
  """
  @spec broadcast(topic :: String.t(), event :: term()) :: :ok | {:error, term()}
  def broadcast(topic, event) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      topic,
      {:domain_event, event}
    )
  end

  @doc """
  Enqueue an Oban job for domain-specific processing.

  Returns `{:ok, job}` or `{:error, reason}`.
  """
  @spec enqueue_job(worker :: module(), args :: map(), opts :: keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_job(worker, args, opts \\ []) do
    if function_exported?(worker, :new, 1) do
      worker.new(args, opts)
    else
      %Oban.Job{worker: worker, args: args}
      |> Map.merge(Map.new(opts))
    end
    |> Oban.insert()
  end
end
