defmodule Thunderline.Thunderbolt.StreamManager do
  @moduledoc """
  StreamManager supervisor for Thunderbolt domain.

  Manages GenStage-based data streams with PubSub bridging for:
  - CA chunk state distribution
  - Topology updates (partitioner/rebalancer)
  - ML pipeline events (AutoML, HPO)
  - Unikernel coordination events

  Provides ingest/drop behaviors for backpressure management and
  telemetry integration for monitoring stream health.

  ## Architecture

  ```
  StreamManager (Supervisor)
  ├── PubSubBridge (GenStage producer)
  │   └── Subscribes to thunderbolt:* topics
  ├── StreamRegistry (Registry for named streams)
  └── StreamStats (ETS-based metrics)
  ```

  ## Usage

  ```elixir
  # Ingest events into stream
  StreamManager.ingest(:chunk_updates, event_data)

  # Drop stream (graceful shutdown)
  StreamManager.drop(:chunk_updates)

  # Get stream stats
  StreamManager.stats(:chunk_updates)
  ```
  """

  use Supervisor
  require Logger

  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @registry __MODULE__.Registry
  @stats_table :thunderbolt_stream_stats

  # PubSub topics this manager subscribes to
  @default_topics [
    "thunderbolt:chunks",
    "thunderbolt:topology",
    "thunderbolt:ml",
    "thunderbolt:lanes",
    "thunderbolt:ca",
    "thunderbolt:events",
    "thunderbolt:alerts"
  ]

  ## Public API

  @doc """
  Starts the StreamManager supervisor.

  ## Options
    - `:topics` - List of PubSub topics to subscribe to (default: built-in topics)
    - `:name` - Supervisor name (default: `#{inspect(__MODULE__)}`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Ingest data into a named stream.

  Creates the stream if it doesn't exist. Returns `:ok` on success
  or `{:error, reason}` on failure.

  ## Examples

      iex> StreamManager.ingest(:chunk_updates, %{chunk_id: "abc", state: :active})
      :ok

      iex> StreamManager.ingest(:ml_events, %{trial_id: 123, metric: 0.95})
      :ok
  """
  @spec ingest(atom(), term()) :: :ok | {:error, term()}
  def ingest(stream_name, data) when is_atom(stream_name) do
    event = wrap_event(stream_name, data)

    # Emit telemetry for ingest
    :telemetry.execute(
      [:thunderline, :thunderbolt, :stream, :ingest],
      %{count: 1, size: estimate_size(data)},
      %{stream: stream_name}
    )

    # Update stats
    update_stats(stream_name, :ingest, 1)

    # Broadcast to stream topic
    topic = stream_topic(stream_name)
    PubSub.broadcast(@pubsub, topic, {:stream_event, event})
  end

  @doc """
  Drop (terminate) a named stream.

  Gracefully shuts down the stream and emits telemetry. Returns `:ok`
  even if stream doesn't exist.

  ## Examples

      iex> StreamManager.drop(:chunk_updates)
      :ok
  """
  @spec drop(atom()) :: :ok
  def drop(stream_name) when is_atom(stream_name) do
    Logger.info("[StreamManager] Dropping stream: #{stream_name}")

    # Emit telemetry for drop
    :telemetry.execute(
      [:thunderline, :thunderbolt, :stream, :drop],
      %{count: 1},
      %{stream: stream_name}
    )

    # Update stats
    update_stats(stream_name, :drop, 1)

    # Notify subscribers of stream termination
    topic = stream_topic(stream_name)
    PubSub.broadcast(@pubsub, topic, {:stream_dropped, stream_name})

    :ok
  end

  @doc """
  Get statistics for a named stream.

  Returns a map with ingest count, drop count, and last activity timestamp.
  Returns `{:error, :not_found}` if stream has no recorded activity.

  ## Examples

      iex> StreamManager.stats(:chunk_updates)
      {:ok, %{ingest_count: 150, drop_count: 0, last_activity: ~U[...]}}
  """
  @spec stats(atom()) :: {:ok, map()} | {:error, :not_found}
  def stats(stream_name) when is_atom(stream_name) do
    case :ets.lookup(@stats_table, stream_name) do
      [{^stream_name, stats}] ->
        {:ok, stats}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Get all active stream names.
  """
  @spec list_streams() :: [atom()]
  def list_streams do
    @stats_table
    |> :ets.tab2list()
    |> Enum.map(fn {name, _stats} -> name end)
  end

  @doc """
  Subscribe to a stream's events.

  ## Examples

      iex> StreamManager.subscribe(:chunk_updates)
      :ok
  """
  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(stream_name) when is_atom(stream_name) do
    topic = stream_topic(stream_name)
    PubSub.subscribe(@pubsub, topic)
  end

  @doc """
  Unsubscribe from a stream's events.
  """
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(stream_name) when is_atom(stream_name) do
    topic = stream_topic(stream_name)
    PubSub.unsubscribe(@pubsub, topic)
  end

  @doc """
  Broadcast data to all subscribers of a stream without recording it.

  Useful for ephemeral notifications that don't need metrics tracking.
  """
  @spec broadcast(atom(), term()) :: :ok | {:error, term()}
  def broadcast(stream_name, data) when is_atom(stream_name) do
    topic = stream_topic(stream_name)
    PubSub.broadcast(@pubsub, topic, {:stream_broadcast, data})
  end

  @doc """
  Initialize the stats ETS table. Called by supervisor on startup.
  """
  @spec init_stats() :: :ok
  def init_stats do
    case :ets.whereis(@stats_table) do
      :undefined ->
        :ets.new(@stats_table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ref ->
        :ok
    end
  end

  ## Supervisor callbacks

  @impl Supervisor
  def init(opts) do
    # Initialize ETS stats table
    init_stats()

    topics = Keyword.get(opts, :topics, @default_topics)

    children = [
      # Registry for named streams
      {Registry, keys: :unique, name: @registry},

      # PubSub bridge GenServer
      {__MODULE__.PubSubBridge, topics: topics}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  ## Private helpers

  defp stream_topic(stream_name), do: "thunderbolt:stream:#{stream_name}"

  defp wrap_event(stream_name, data) do
    %{
      stream: stream_name,
      data: data,
      timestamp: DateTime.utc_now(),
      id: Thunderline.UUID.v7()
    }
  end

  defp estimate_size(data) when is_map(data), do: map_size(data) * 50
  defp estimate_size(data) when is_list(data), do: length(data) * 20
  defp estimate_size(data) when is_binary(data), do: byte_size(data)
  defp estimate_size(_), do: 10

  defp update_stats(stream_name, operation, count) do
    now = DateTime.utc_now()

    :ets.update_counter(
      @stats_table,
      stream_name,
      [{2, count}],
      {stream_name, %{ingest_count: 0, drop_count: 0, last_activity: now}}
    )

    # Update the operation-specific counter and timestamp
    case :ets.lookup(@stats_table, stream_name) do
      [{^stream_name, stats}] ->
        updated_stats =
          case operation do
            :ingest ->
              %{stats | ingest_count: Map.get(stats, :ingest_count, 0) + count, last_activity: now}

            :drop ->
              %{stats | drop_count: Map.get(stats, :drop_count, 0) + count, last_activity: now}
          end

        :ets.insert(@stats_table, {stream_name, updated_stats})

      [] ->
        initial_stats = %{
          ingest_count: if(operation == :ingest, do: count, else: 0),
          drop_count: if(operation == :drop, do: count, else: 0),
          last_activity: now
        }

        :ets.insert(@stats_table, {stream_name, initial_stats})
    end
  end
end
