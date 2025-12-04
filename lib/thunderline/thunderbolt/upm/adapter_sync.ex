defmodule Thunderline.Thunderbolt.UPM.AdapterSync do
  @moduledoc """
  Adapter synchronization worker for UPM.

  Pushes approved snapshots to ThunderBlock agents and tracks sync status.
  Coordinates with UpmAdapter resources to maintain agent-side sync state.

  ## Responsibilities

  - Monitor for `ai.upm.snapshot.activated` events
  - Push snapshot embeddings to ThunderBlock agents
  - Track adapter sync status (pending → syncing → synced)
  - Emit `[:upm, :adapter, :sync]` telemetry
  - Handle sync failures with retry logic
  - Support bulk sync operations during rollouts

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.AdapterSync,
        sync_batch_size: 100,
        sync_timeout_ms: 30_000,
        max_retries: 3,
        retry_backoff_ms: 1000

  ## Telemetry Events

  - `[:upm, :adapter, :sync, :start]` - Sync started
  - `[:upm, :adapter, :sync, :success]` - Sync completed successfully
  - `[:upm, :adapter, :sync, :failure]` - Sync failed
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Resources.{UpmAdapter, UpmSnapshot}
  alias Thunderline.Thunderbolt.UPM.SnapshotManager

  @type state :: %{
          sync_batch_size: pos_integer(),
          sync_timeout_ms: pos_integer(),
          max_retries: pos_integer(),
          retry_backoff_ms: pos_integer(),
          active_syncs: MapSet.t(binary())
        }

  # Client API

  @doc """
  Starts the adapter sync worker.

  ## Options

  - `:sync_batch_size` - Number of adapters to sync in parallel (default: 100)
  - `:sync_timeout_ms` - Timeout for individual sync operations (default: 30000)
  - `:max_retries` - Maximum retry attempts for failed syncs (default: 3)
  - `:retry_backoff_ms` - Backoff delay between retries (default: 1000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Synchronizes a specific adapter with a snapshot.

  ## Parameters

  - `adapter_id` - UUID of adapter to sync
  - `snapshot_id` - UUID of snapshot to sync to

  ## Returns

  - `:ok` - Sync queued successfully
  """
  @spec sync_adapter(binary(), binary()) :: :ok
  def sync_adapter(adapter_id, snapshot_id) do
    GenServer.cast(__MODULE__, {:sync_adapter, adapter_id, snapshot_id})
  end

  @doc """
  Synchronizes all adapters with a snapshot (bulk operation).

  Used during snapshot activation to push to all registered agents.
  """
  @spec sync_all_adapters(binary()) :: :ok
  def sync_all_adapters(snapshot_id) do
    GenServer.cast(__MODULE__, {:sync_all_adapters, snapshot_id})
  end

  @doc """
  Gets current sync statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    sync_batch_size = Keyword.get(opts, :sync_batch_size, 100)
    sync_timeout_ms = Keyword.get(opts, :sync_timeout_ms, 30_000)
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_backoff_ms = Keyword.get(opts, :retry_backoff_ms, 1000)

    state = %{
      sync_batch_size: sync_batch_size,
      sync_timeout_ms: sync_timeout_ms,
      max_retries: max_retries,
      retry_backoff_ms: retry_backoff_ms,
      active_syncs: MapSet.new()
    }

    # Subscribe to activation events
    subscribe_to_activation_events()

    Logger.info("""
    [UPM.AdapterSync] Initialized
      batch_size: #{sync_batch_size}
      timeout: #{sync_timeout_ms}ms
      max_retries: #{max_retries}
    """)

    {:ok, state}
  end

  @impl true
  def handle_cast({:sync_adapter, adapter_id, snapshot_id}, state) do
    # Mark as active sync
    new_active = MapSet.put(state.active_syncs, adapter_id)

    # Start async sync task
    Task.start(fn ->
      do_sync_adapter(adapter_id, snapshot_id, state)
    end)

    {:noreply, %{state | active_syncs: new_active}}
  end

  def handle_cast({:sync_all_adapters, snapshot_id}, state) do
    Logger.info("[UPM.AdapterSync] Starting bulk sync for snapshot #{snapshot_id}")

    # Get all adapters that need this snapshot
    case get_adapters_for_snapshot(snapshot_id) do
      {:ok, adapters} ->
        # Batch sync
        adapters
        |> Enum.chunk_every(state.sync_batch_size)
        |> Enum.each(fn batch ->
          Enum.each(batch, fn adapter ->
            Task.start(fn ->
              do_sync_adapter(adapter.id, snapshot_id, state)
            end)
          end)

          # Brief delay between batches to avoid overwhelming agents
          Process.sleep(100)
        end)

        Logger.info("""
        [UPM.AdapterSync] Bulk sync initiated
          snapshot_id: #{snapshot_id}
          adapter_count: #{length(adapters)}
          batches: #{ceil(length(adapters) / state.sync_batch_size)}
        """)

      {:error, reason} ->
        Logger.error("[UPM.AdapterSync] Failed to fetch adapters: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      active_syncs: MapSet.size(state.active_syncs),
      sync_batch_size: state.sync_batch_size,
      sync_timeout_ms: state.sync_timeout_ms
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:event_bus, %{name: "ai.upm.snapshot.activated", payload: payload}}, state) do
    snapshot_id = payload["snapshot_id"]

    Logger.info("[UPM.AdapterSync] Received activation event for snapshot #{snapshot_id}")

    # Trigger bulk sync
    sync_all_adapters(snapshot_id)

    {:noreply, state}
  end

  def handle_info({:sync_complete, adapter_id, result}, state) do
    # Remove from active syncs
    new_active = MapSet.delete(state.active_syncs, adapter_id)

    case result do
      :ok ->
        Logger.debug("[UPM.AdapterSync] Completed sync for adapter #{adapter_id}")

      {:error, reason} ->
        Logger.error(
          "[UPM.AdapterSync] Failed sync for adapter #{adapter_id}: #{inspect(reason)}"
        )
    end

    {:noreply, %{state | active_syncs: new_active}}
  end

  def handle_info(msg, state) do
    Logger.debug("[UPM.AdapterSync] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp subscribe_to_activation_events do
    # Subscribe to UPM snapshot activation events via PubSub
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:snapshot_activated")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "ai:upm:snapshot:activated")
    Logger.debug("[UPM.AdapterSync] Subscribed to snapshot activation events")
    :ok
  end

  defp get_adapters_for_snapshot(snapshot_id) do
    require Ash.Query
    # Get snapshot to determine mode
    case Ash.get(UpmSnapshot, snapshot_id) do
      {:ok, snapshot} ->
        # Get all adapters matching this mode
        query = UpmAdapter |> Ash.Query.filter(mode == ^snapshot.mode)
        case Ash.read(query) do
          {:ok, adapters} -> {:ok, adapters}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:snapshot_not_found, reason}}
    end
  end

  defp do_sync_adapter(adapter_id, snapshot_id, state, retry_count \\ 0) do
    start_time = System.monotonic_time(:millisecond)

    # Emit start telemetry
    emit_telemetry(:start, %{adapter_id: adapter_id, snapshot_id: snapshot_id})

    # Update adapter status to syncing
    case mark_adapter_syncing(adapter_id) do
      :ok ->
        # Load snapshot data
        case SnapshotManager.load_snapshot(snapshot_id) do
          {:ok, model_data} ->
            # Sync to agent (actual implementation would call ThunderBlock adapter endpoint)
            case sync_to_agent(adapter_id, snapshot_id, model_data, state.sync_timeout_ms) do
              :ok ->
                # Mark synced
                mark_adapter_synced(adapter_id)

                duration_ms = System.monotonic_time(:millisecond) - start_time

                # Emit success telemetry
                emit_telemetry(:success, %{
                  adapter_id: adapter_id,
                  snapshot_id: snapshot_id,
                  duration_ms: duration_ms
                })

                send(self(), {:sync_complete, adapter_id, :ok})
                :ok

              {:error, reason} ->
                handle_sync_failure(adapter_id, snapshot_id, reason, retry_count, state)
            end

          {:error, reason} ->
            Logger.error("""
            [UPM.AdapterSync] Failed to load snapshot
              adapter_id: #{adapter_id}
              snapshot_id: #{snapshot_id}
              error: #{inspect(reason)}
            """)

            mark_adapter_errored(adapter_id)
            send(self(), {:sync_complete, adapter_id, {:error, reason}})
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("[UPM.AdapterSync] Failed to mark adapter syncing: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_sync_failure(adapter_id, snapshot_id, reason, retry_count, state) do
    if retry_count < state.max_retries do
      Logger.warning("""
      [UPM.AdapterSync] Sync failed, retrying
        adapter_id: #{adapter_id}
        attempt: #{retry_count + 1}/#{state.max_retries}
        error: #{inspect(reason)}
      """)

      # Exponential backoff
      backoff_ms = (state.retry_backoff_ms * :math.pow(2, retry_count)) |> round()
      Process.sleep(backoff_ms)

      # Retry
      do_sync_adapter(adapter_id, snapshot_id, state, retry_count + 1)
    else
      Logger.error("""
      [UPM.AdapterSync] Sync failed permanently
        adapter_id: #{adapter_id}
        attempts: #{state.max_retries}
        error: #{inspect(reason)}
      """)

      mark_adapter_errored(adapter_id)

      # Emit failure telemetry
      emit_telemetry(:failure, %{
        adapter_id: adapter_id,
        snapshot_id: snapshot_id,
        reason: inspect(reason),
        attempts: state.max_retries
      })

      send(self(), {:sync_complete, adapter_id, {:error, reason}})
      {:error, :max_retries_exceeded}
    end
  end

  defp sync_to_agent(adapter_id, snapshot_id, model_data, timeout_ms) do
    # Placeholder for actual agent sync logic
    # This would:
    # 1. Fetch adapter details (agent endpoint, auth)
    # 2. Call ThunderBlock adapter HTTP/gRPC endpoint
    # 3. Push model embeddings/parameters
    # 4. Wait for acknowledgment

    Logger.debug("""
    [UPM.AdapterSync] Syncing to agent
      adapter_id: #{adapter_id}
      snapshot_id: #{snapshot_id}
      data_size: #{byte_size(model_data)} bytes
      timeout: #{timeout_ms}ms
    """)

    # Mock successful sync for now
    Process.sleep(100)
    :ok
  end

  defp mark_adapter_syncing(adapter_id) do
    case Ash.get(UpmAdapter, adapter_id) do
      {:ok, adapter} ->
        case UpmAdapter.mark_syncing(adapter.id) |> Ash.update() do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_adapter_synced(adapter_id) do
    case Ash.get(UpmAdapter, adapter_id) do
      {:ok, adapter} ->
        %{last_synced_at: DateTime.utc_now()}
        |> then(&UpmAdapter.mark_synced(adapter.id, &1))
        |> Ash.update()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_adapter_errored(adapter_id) do
    case Ash.get(UpmAdapter, adapter_id) do
      {:ok, adapter} ->
        case UpmAdapter.mark_errored(adapter.id) |> Ash.update() do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:upm, :adapter, :sync, event],
      %{count: 1},
      metadata
    )
  end
end
