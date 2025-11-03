defmodule Thunderline.Thunderbolt.UPM.SnapshotManager do
  @moduledoc """
  Snapshot manager for UPM that handles persistence to ThunderBlock vault.

  Manages snapshot versioning, checksum validation, and storage path
  coordination with ThunderBlock vault.

  ## Responsibilities

  - Create and persist snapshots to ThunderBlock vault
  - Validate snapshot checksums
  - Manage storage paths and retrieval
  - Coordinate snapshot activation with ThunderCrown policies
  - Track snapshot lineage and rollback history

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.SnapshotManager,
        storage_base_path: "/var/lib/thunderline/upm/snapshots",
        compression: :zstd,
        retention_days: 30

  ## Storage Path Format

  Snapshots stored at: `<base_path>/<trainer_id>/<version>/<snapshot_id>.bin`
  """

  require Logger

  alias Thunderline.Thunderbolt.Resources.{UpmSnapshot, UpmTrainer}
  alias Thunderline.UUID

  @type snapshot_params :: %{
          trainer_id: binary(),
          tenant_id: binary() | nil,
          version: non_neg_integer(),
          mode: atom(),
          status: atom(),
          checksum: binary(),
          size_bytes: non_neg_integer(),
          metadata: map()
        }

  @doc """
  Creates a new snapshot and persists model data to storage.

  ## Parameters

  - `params` - Snapshot metadata (trainer_id, version, mode, etc.)
  - `model_data` - Binary model data to persist

  ## Returns

  - `{:ok, snapshot}` - Successfully created snapshot resource
  - `{:error, reason}` - Failed to create snapshot
  """
  @spec create_snapshot(snapshot_params(), binary()) :: {:ok, UpmSnapshot.t()} | {:error, term()}
  def create_snapshot(params, model_data) when is_binary(model_data) do
    snapshot_id = UUID.v7()

    # Validate checksum
    calculated_checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

    if calculated_checksum != params.checksum do
      Logger.error("""
      [UPM.SnapshotManager] Checksum mismatch
        expected: #{params.checksum}
        calculated: #{calculated_checksum}
      """)

      {:error, :checksum_mismatch}
    else
      # Determine storage path
      storage_path = build_storage_path(params.trainer_id, params.version, snapshot_id)

      # Compress if configured
      {final_data, compression_used} = maybe_compress(model_data)

      # Persist to storage
      case write_to_storage(storage_path, final_data) do
        :ok ->
          # Create snapshot resource
          snapshot_params =
            Map.merge(params, %{
              id: snapshot_id,
              storage_path: storage_path,
              size_bytes: byte_size(final_data),
              metadata:
                Map.merge(params.metadata, %{
                  compression: compression_used,
                  original_size: byte_size(model_data),
                  storage_size: byte_size(final_data)
                })
            })

          case UpmSnapshot.record(snapshot_params) |> Ash.create() do
            {:ok, snapshot} ->
              Logger.info("""
              [UPM.SnapshotManager] Created snapshot
                id: #{snapshot_id}
                trainer_id: #{params.trainer_id}
                version: #{params.version}
                size: #{byte_size(final_data)} bytes
                path: #{storage_path}
              """)

              {:ok, snapshot}

            {:error, reason} ->
              # Cleanup storage on failure
              cleanup_storage(storage_path)
              {:error, {:snapshot_creation_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:storage_write_failed, reason}}
      end
    end
  end

  @doc """
  Loads a snapshot's model data from storage.

  ## Parameters

  - `snapshot_id` - UUID of snapshot to load

  ## Returns

  - `{:ok, model_data}` - Binary model data
  - `{:error, reason}` - Failed to load snapshot
  """
  @spec load_snapshot(binary()) :: {:ok, binary()} | {:error, term()}
  def load_snapshot(snapshot_id) do
    case Ash.get(UpmSnapshot, snapshot_id) do
      {:ok, snapshot} ->
        case read_from_storage(snapshot.storage_path) do
          {:ok, data} ->
            # Decompress if needed
            decompressed = maybe_decompress(data, snapshot.metadata["compression"])

            # Validate checksum
            calculated_checksum =
              :crypto.hash(:sha256, decompressed) |> Base.encode16(case: :lower)

            if calculated_checksum == snapshot.checksum do
              {:ok, decompressed}
            else
              Logger.error("""
              [UPM.SnapshotManager] Checksum validation failed on load
                snapshot_id: #{snapshot_id}
                expected: #{snapshot.checksum}
                calculated: #{calculated_checksum}
              """)

              {:error, :checksum_mismatch}
            end

          {:error, reason} ->
            {:error, {:storage_read_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:snapshot_not_found, reason}}
    end
  end

  @doc """
  Activates a snapshot (promotes from shadow to active).

  This should be called after ThunderCrown policy approval.
  """
  @spec activate_snapshot(binary(), map()) :: {:ok, UpmSnapshot.t()} | {:error, term()}
  def activate_snapshot(snapshot_id, opts \\ %{}) do
    correlation_id = Map.get(opts, :correlation_id, UUID.v7())

    case Ash.get(UpmSnapshot, snapshot_id) do
      {:ok, snapshot} ->
        # Deactivate previous active snapshot (if any)
        case deactivate_previous_active(snapshot.trainer_id, snapshot_id) do
          :ok ->
            # Activate this snapshot
            case UpmSnapshot.activate(snapshot.id) |> Ash.update() do
              {:ok, updated_snapshot} ->
                Logger.info("""
                [UPM.SnapshotManager] Activated snapshot
                  id: #{snapshot_id}
                  trainer_id: #{snapshot.trainer_id}
                  version: #{snapshot.version}
                """)

                # Emit activation event
                emit_activation_event(updated_snapshot, correlation_id)

                {:ok, updated_snapshot}

              {:error, reason} ->
                {:error, {:activation_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:deactivation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:snapshot_not_found, reason}}
    end
  end

  @doc """
  Rolls back to a previous snapshot.

  Deactivates current active snapshot and promotes specified snapshot.
  """
  @spec rollback_to_snapshot(binary(), map()) :: {:ok, UpmSnapshot.t()} | {:error, term()}
  def rollback_to_snapshot(snapshot_id, opts \\ %{}) do
    correlation_id = Map.get(opts, :correlation_id, UUID.v7())

    case Ash.get(UpmSnapshot, snapshot_id) do
      {:ok, snapshot} ->
        case UpmSnapshot.rollback(snapshot.id) |> Ash.update() do
          {:ok, updated_snapshot} ->
            Logger.warn("""
            [UPM.SnapshotManager] Rolled back to snapshot
              id: #{snapshot_id}
              trainer_id: #{snapshot.trainer_id}
              version: #{snapshot.version}
            """)

            # Emit rollback event
            emit_rollback_event(updated_snapshot, correlation_id)

            {:ok, updated_snapshot}

          {:error, reason} ->
            {:error, {:rollback_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:snapshot_not_found, reason}}
    end
  end

  @doc """
  Lists all snapshots for a trainer.
  """
  @spec list_snapshots(binary(), keyword()) :: {:ok, [UpmSnapshot.t()]} | {:error, term()}
  def list_snapshots(trainer_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    query = [trainer_id: trainer_id]
    query = if status_filter, do: Keyword.put(query, :status, status_filter), else: query

    case Ash.read(UpmSnapshot, filter: query, limit: limit, sort: [version: :desc]) do
      {:ok, snapshots} -> {:ok, snapshots}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the currently active snapshot for a trainer.
  """
  @spec get_active_snapshot(binary()) :: {:ok, UpmSnapshot.t() | nil} | {:error, term()}
  def get_active_snapshot(trainer_id) do
    case Ash.read(UpmSnapshot, filter: [trainer_id: trainer_id, status: :active], limit: 1) do
      {:ok, [snapshot]} -> {:ok, snapshot}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cleans up old snapshots based on retention policy.
  """
  @spec cleanup_old_snapshots(binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cleanup_old_snapshots(trainer_id, opts \\ []) do
    retention_days = Keyword.get(opts, :retention_days, 30)
    cutoff_date = DateTime.utc_now() |> DateTime.add(-retention_days, :day)

    case Ash.read(UpmSnapshot,
           filter: [trainer_id: trainer_id, status: :superseded],
           load: [:inserted_at]
         ) do
      {:ok, snapshots} ->
        old_snapshots =
          Enum.filter(snapshots, fn s ->
            DateTime.compare(s.inserted_at, cutoff_date) == :lt
          end)

        deleted_count =
          Enum.reduce(old_snapshots, 0, fn snapshot, acc ->
            case delete_snapshot(snapshot.id) do
              :ok -> acc + 1
              {:error, _} -> acc
            end
          end)

        Logger.info("""
        [UPM.SnapshotManager] Cleaned up snapshots
          trainer_id: #{trainer_id}
          deleted: #{deleted_count}
          cutoff: #{DateTime.to_iso8601(cutoff_date)}
        """)

        {:ok, deleted_count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Helpers

  defp build_storage_path(trainer_id, version, snapshot_id) do
    base_path =
      Application.get_env(
        :thunderline,
        [__MODULE__, :storage_base_path],
        "/var/lib/thunderline/upm/snapshots"
      )

    Path.join([base_path, trainer_id, "v#{version}", "#{snapshot_id}.bin"])
  end

  defp maybe_compress(data) do
    compression =
      Application.get_env(:thunderline, [__MODULE__, :compression], :zstd)

    case compression do
      :zstd ->
        {:ok, compressed} = :ezstd.compress(data)
        {compressed, "zstd"}

      :gzip ->
        compressed = :zlib.gzip(data)
        {compressed, "gzip"}

      :none ->
        {data, "none"}

      _ ->
        {data, "none"}
    end
  end

  defp maybe_decompress(data, nil), do: data
  defp maybe_decompress(data, "none"), do: data

  defp maybe_decompress(data, "zstd") do
    {:ok, decompressed} = :ezstd.decompress(data)
    decompressed
  end

  defp maybe_decompress(data, "gzip") do
    :zlib.gunzip(data)
  end

  defp maybe_decompress(data, _), do: data

  defp write_to_storage(path, data) do
    # Ensure directory exists
    path |> Path.dirname() |> File.mkdir_p!()

    # Write data atomically (write to temp, then rename)
    temp_path = "#{path}.tmp"

    case File.write(temp_path, data) do
      :ok ->
        case File.rename(temp_path, path) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_from_storage(path) do
    File.read(path)
  end

  defp cleanup_storage(path) do
    File.rm(path)
  end

  defp delete_snapshot(snapshot_id) do
    case Ash.get(UpmSnapshot, snapshot_id) do
      {:ok, snapshot} ->
        # Delete from storage
        cleanup_storage(snapshot.storage_path)

        # Delete resource
        case Ash.destroy(snapshot) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deactivate_previous_active(trainer_id, exclude_id) do
    case Ash.read(UpmSnapshot, filter: [trainer_id: trainer_id, status: :active]) do
      {:ok, snapshots} ->
        snapshots
        |> Enum.reject(&(&1.id == exclude_id))
        |> Enum.each(fn snapshot ->
          case UpmSnapshot.rollback(snapshot.id) |> Ash.update() do
            {:ok, _} ->
              Logger.debug("[UPM.SnapshotManager] Deactivated snapshot #{snapshot.id}")

            {:error, reason} ->
              Logger.warn(
                "[UPM.SnapshotManager] Failed to deactivate snapshot #{snapshot.id}: #{inspect(reason)}"
              )
          end
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_activation_event(snapshot, correlation_id) do
    Thunderline.Thunderflow.EventBus.publish_event(%{
      name: "ai.upm.snapshot.activated",
      source: :bolt,
      payload: %{
        snapshot_id: snapshot.id,
        trainer_id: snapshot.trainer_id,
        version: snapshot.version,
        mode: snapshot.mode,
        checksum: snapshot.checksum
      },
      correlation_id: correlation_id
    })
  end

  defp emit_rollback_event(snapshot, correlation_id) do
    Thunderline.Thunderflow.EventBus.publish_event(%{
      name: "ai.upm.rollback",
      source: :bolt,
      payload: %{
        snapshot_id: snapshot.id,
        trainer_id: snapshot.trainer_id,
        version: snapshot.version,
        reason: "manual_rollback"
      },
      correlation_id: correlation_id
    })
  end
end
