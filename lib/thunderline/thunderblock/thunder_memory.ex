defmodule Thunderline.ThunderMemory do
  @moduledoc """
  ThunderMemory – high-performance distributed memory layer.

  Provides fast, persistent storage for agents, chunks, and real-time metrics
  using Mnesia for durability & replication. Acts as the blackboard for
  ThunderBit/PAC processes.

  Key Features:
  - Agent lifecycle management (spawn, update, retrieve, list)
  - Chunk-based data storage with efficient querying
  - Real-time metrics collection and aggregation
  - Event-driven updates for real-time synchronization
  - Distributed cluster support via Mnesia
  """

  use GenServer
  require Logger

  alias :mnesia, as: Mnesia

  # Table definitions for ThunderMemory storage
  defmodule AgentTable do
    @moduledoc "Mnesia table for agent data"
    use Memento.Table,
      attributes: [:id, :data, :status, :created_at, :updated_at, :metadata],
      index: [:status, :created_at, :updated_at],
      type: :ordered_set
  end

  defmodule ChunkTable do
    @moduledoc "Mnesia table for chunk data"
    use Memento.Table,
      attributes: [:id, :data, :type, :size, :created_at, :agent_id, :metadata],
      index: [:type, :created_at, :agent_id],
      type: :ordered_set
  end

  defmodule MetricTable do
    @moduledoc "Mnesia table for metrics data"
    use Memento.Table,
      attributes: [:id, :metric_name, :value, :timestamp, :aggregation_level, :metadata],
      index: [:metric_name, :timestamp, :aggregation_level],
      type: :ordered_set
  end

  defmodule ThunderbitTable do
    @moduledoc "Mnesia table for Thunderbit state and blackboard data"
    use Memento.Table,
      attributes: [:id, :thunderbit_id, :data_type, :data, :created_at, :updated_at],
      index: [:thunderbit_id, :data_type, :created_at],
      type: :ordered_set
  end

  defmodule KeyValueTable do
    @moduledoc "Mnesia table for generic key-value storage"
    use Memento.Table,
      attributes: [:key, :value, :created_at, :updated_at],
      index: [:created_at],
      type: :ordered_set
  end

  ## Public API

  @doc "Start the ThunderMemory system"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get agent by ID"
  def get_agent(agent_id) do
    GenServer.call(__MODULE__, {:get_agent, agent_id})
  end

  @doc "Spawn a new agent"
  def spawn_agent(agent_data) do
    GenServer.call(__MODULE__, {:spawn_agent, agent_data})
  end

  @doc "Update an existing agent"
  def update_agent(agent_id, updates) do
    GenServer.call(__MODULE__, {:update_agent, agent_id, updates})
  end

  @doc "List agents with optional filters"
  def list_agents(filters \\ %{}) do
    GenServer.call(__MODULE__, {:list_agents, filters})
  end

  @doc "Get chunks with optional filters"
  def get_chunks(filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_chunks, filters})
  end

  @doc "Create a new chunk"
  def create_chunk(chunk_data) do
    GenServer.call(__MODULE__, {:create_chunk, chunk_data})
  end

  @doc "Record a metric"
  def record_metric(metric_name, value, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_metric, metric_name, value, metadata})
  end

  ## Generic key-value storage API

  @doc "Get value by key"
  def get(key) do
    GenServer.call(__MODULE__, {:get_key, key})
  end

  @doc "Store key-value pair"
  def store(key, value) do
    GenServer.call(__MODULE__, {:store_key, key, value})
  end

  ## ThunderBit-specific API

  @doc "Get ThunderBit blackboard data"
  def get_thunderbit_blackboard(thunderbit_id) do
    GenServer.call(__MODULE__, {:get_thunderbit_blackboard, thunderbit_id})
  end

  @doc "Store ThunderBit blackboard data"
  def store_thunderbit_blackboard(thunderbit_id, blackboard) do
    GenServer.call(__MODULE__, {:store_thunderbit_blackboard, thunderbit_id, blackboard})
  end

  @doc "Store ThunderBit state data"
  def store_thunderbit_state(thunderbit_id, state_data) do
    GenServer.call(__MODULE__, {:store_thunderbit_state, thunderbit_id, state_data})
  end

  @doc "Delete ThunderBit state data"
  def delete_thunderbit_state(thunderbit_id) do
    GenServer.call(__MODULE__, {:delete_thunderbit_state, thunderbit_id})
  end

  @doc "Delete ThunderBit blackboard data"
  def delete_thunderbit_blackboard(thunderbit_id) do
    GenServer.call(__MODULE__, {:delete_thunderbit_blackboard, thunderbit_id})
  end

  @doc "Get metrics by name and aggregation level"
  def get_metrics(metric_name, aggregation_level \\ :minute) do
    GenServer.call(__MODULE__, {:get_metrics, metric_name, aggregation_level})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting ThunderMemory system...")

    # Initialize Mnesia tables
    case setup_tables() do
      :ok ->
        Logger.info("ThunderMemory tables initialized successfully")
        {:ok, %{initialized: true, opts: opts}}

      {:error, reason} ->
        Logger.error("Failed to initialize ThunderMemory tables: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get_agent, agent_id}, _from, state) do
    result =
      Memento.transaction!(fn ->
        case Memento.Query.read(AgentTable, agent_id) do
          nil -> {:error, :not_found}
          agent -> {:ok, agent}
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:spawn_agent, agent_data}, _from, state) do
    agent_id = generate_agent_id()
    timestamp = DateTime.utc_now()

    agent = %AgentTable{
      id: agent_id,
      data: agent_data,
      status: :active,
      created_at: timestamp,
      updated_at: timestamp,
      metadata: %{}
    }

    result =
      Memento.transaction!(fn ->
        case Memento.Query.write(agent) do
          :ok ->
            publish_event(:agent_spawned, %{agent_id: agent_id, data: agent_data})
            {:ok, agent_id}

          error ->
            error
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_agent, agent_id, updates}, _from, state) do
    result =
      Memento.transaction!(fn ->
        case Memento.Query.read(AgentTable, agent_id) do
          nil ->
            {:error, :not_found}

          agent ->
            updated_agent = %{
              agent
              | data: Map.merge(agent.data, updates),
                updated_at: DateTime.utc_now()
            }

            case Memento.Query.write(updated_agent) do
              :ok ->
                publish_event(:agent_updated, %{agent_id: agent_id, updates: updates})
                {:ok, updated_agent}

              error ->
                error
            end
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:list_agents, filters}, _from, state) do
    result =
      Memento.transaction!(fn ->
        agents = Memento.Query.all(AgentTable)
        filtered_agents = apply_filters(agents, filters)
        {:ok, filtered_agents}
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_chunks, filters}, _from, state) do
    result =
      Memento.transaction!(fn ->
        chunks = Memento.Query.all(ChunkTable)
        filtered_chunks = apply_filters(chunks, filters)
        {:ok, filtered_chunks}
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_chunk, chunk_data}, _from, state) do
    chunk_id = generate_chunk_id()
    timestamp = DateTime.utc_now()

    chunk = %ChunkTable{
      id: chunk_id,
      data: chunk_data[:data],
      type: chunk_data[:type] || :generic,
      size: byte_size(chunk_data[:data] || ""),
      created_at: timestamp,
      agent_id: chunk_data[:agent_id],
      metadata: chunk_data[:metadata] || %{}
    }

    result =
      Memento.transaction!(fn ->
        case Memento.Query.write(chunk) do
          :ok ->
            publish_event(:chunk_created, %{chunk_id: chunk_id, type: chunk.type})
            {:ok, chunk_id}

          error ->
            error
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_metrics, metric_name, aggregation_level}, _from, state) do
    result =
      Memento.transaction!(fn ->
        # Simple query for now - can be optimized with time-based aggregation
        metrics =
          Memento.Query.select(
            MetricTable,
            {:==, :metric_name, metric_name}
          )

        {:ok, metrics}
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:record_metric, metric_name, value, metadata}, state) do
    metric_id = generate_metric_id()
    timestamp = DateTime.utc_now()

    metric = %MetricTable{
      id: metric_id,
      metric_name: metric_name,
      value: value,
      timestamp: timestamp,
      aggregation_level: :raw,
      metadata: metadata
    }

    Memento.transaction!(fn ->
      Memento.Query.write(metric)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:get_key, key}, _from, state) do
    result =
      Memento.transaction!(fn ->
        case Memento.Query.read(KeyValueTable, key) do
          nil -> {:error, :not_found}
          %{value: value} -> {:ok, value}
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:store_key, key, value}, _from, state) do
    timestamp = DateTime.utc_now()

    result =
      Memento.transaction!(fn ->
        record = %KeyValueTable{
          key: key,
          value: value,
          created_at: timestamp,
          updated_at: timestamp
        }

        Memento.Query.write(record)
        :ok
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_thunderbit_blackboard, thunderbit_id}, _from, state) do
    result =
      Memento.transaction!(fn ->
        case Memento.Query.select(ThunderbitTable, [
               {:==, :thunderbit_id, thunderbit_id},
               {:==, :data_type, :blackboard}
             ]) do
          [] -> {:error, :not_found}
          [%{data: data} | _] -> {:ok, data}
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:store_thunderbit_blackboard, thunderbit_id, blackboard}, _from, state) do
    timestamp = DateTime.utc_now()
    id = generate_thunderbit_data_id()

    result =
      Memento.transaction!(fn ->
        record = %ThunderbitTable{
          id: id,
          thunderbit_id: thunderbit_id,
          data_type: :blackboard,
          data: blackboard,
          created_at: timestamp,
          updated_at: timestamp
        }

        Memento.Query.write(record)
        :ok
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:store_thunderbit_state, thunderbit_id, state_data}, _from, state) do
    timestamp = DateTime.utc_now()
    id = generate_thunderbit_data_id()

    result =
      Memento.transaction!(fn ->
        record = %ThunderbitTable{
          id: id,
          thunderbit_id: thunderbit_id,
          data_type: :state,
          data: state_data,
          created_at: timestamp,
          updated_at: timestamp
        }

        Memento.Query.write(record)
        :ok
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_thunderbit_state, thunderbit_id}, _from, state) do
    result =
      Memento.transaction!(fn ->
        records =
          Memento.Query.select(ThunderbitTable, [
            {:==, :thunderbit_id, thunderbit_id},
            {:==, :data_type, :state}
          ])

        Enum.each(records, fn record ->
          Memento.Query.delete(ThunderbitTable, record.id)
        end)

        :ok
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_thunderbit_blackboard, thunderbit_id}, _from, state) do
    result =
      Memento.transaction!(fn ->
        records =
          Memento.Query.select(ThunderbitTable, [
            {:==, :thunderbit_id, thunderbit_id},
            {:==, :data_type, :blackboard}
          ])

        Enum.each(records, fn record ->
          Memento.Query.delete(ThunderbitTable, record.id)
        end)

        :ok
      end)

    {:reply, result, state}
  end

  # Private helper functions

  ## Private Functions

  defp setup_tables do
    tables = [AgentTable, ChunkTable, MetricTable, ThunderbitTable, KeyValueTable]

    try do
      Enum.each(tables, fn table ->
        case Memento.Table.create(table) do
          {:atomic, :ok} -> :ok
          # Handle direct :ok return
          :ok -> :ok
          {:aborted, {:already_exists, _}} -> :ok
          {:error, {:already_exists, _}} -> :ok
          {:aborted, reason} -> throw({:table_error, table, reason})
        end
      end)

      :ok
    catch
      {:table_error, table, reason} ->
        {:error, {table, reason}}
    end
  end

  defp generate_agent_id do
    "agent_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_chunk_id do
    "chunk_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_metric_id do
    "metric_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_thunderbit_data_id do
    "tb_data_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp apply_filters(items, filters) when map_size(filters) == 0, do: items

  defp apply_filters(items, filters) do
    Enum.filter(items, fn item ->
      Enum.all?(filters, fn {key, value} ->
        Map.get(item, key) == value
      end)
    end)
  end

  defp publish_event(event_type, data) do
    name = "system.memory." <> Atom.to_string(event_type)
    attrs = %{
      name: name,
      type: event_type,
      source: :thunder_memory,
      payload: data,
      meta: %{pipeline: :realtime}
    }
    case Thunderline.Event.new(attrs) do
      {:ok, ev} ->
        case Thunderline.EventBus.publish_event(ev) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("[ThunderMemory] publish failed #{inspect(reason)} type=#{event_type}")
        end
      {:error, errs} -> Logger.warning("[ThunderMemory] build event failed #{inspect(errs)} type=#{event_type}")
    end
  end
end
