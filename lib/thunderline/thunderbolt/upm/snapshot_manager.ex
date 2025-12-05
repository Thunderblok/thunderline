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
  require Ash.Query

  alias Thunderline.Thunderbolt.Resources.UpmSnapshot
  alias Thunderline.Thundercrown.Policies.UPMPolicy
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
              storage_path: storage_path,
              size_bytes: byte_size(final_data),
              metadata:
                Map.merge(params.metadata, %{
                  compression: compression_used,
                  original_size: byte_size(model_data),
                  storage_size: byte_size(final_data)
                })
            })

          case UpmSnapshot.record(snapshot_params) do
            {:ok, snapshot} ->
              Logger.info("""
              [UPM.SnapshotManager] Created snapshot
                id: #{snapshot.id}
                trainer_id: #{params.trainer_id}
                version: #{params.version}
                size: #{byte_size(final_data)} bytes
                path: #{storage_path}
              """)

              # Emit telemetry event
              :telemetry.execute(
                [:upm, :snapshot, :create],
                %{
                  size_bytes: snapshot.size_bytes,
                  original_size: byte_size(model_data),
                  compression_ratio: byte_size(model_data) / snapshot.size_bytes
                },
                %{
                  snapshot_id: snapshot.id,
                  trainer_id: snapshot.trainer_id,
                  version: snapshot.version,
                  mode: snapshot.mode,
                  compression: compression_used
                }
              )

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
              # Parse JSON if it's JSON data
              case Jason.decode(decompressed) do
                {:ok, parsed} -> {:ok, parsed}
                # Return raw binary if not JSON
                {:error, _} -> {:ok, decompressed}
              end
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
  Activates a snapshot with ThunderCrown policy authorization.

  Enforces rollout policy based on snapshot mode:
  - Shadow mode: Always allowed (observational only)
  - Canary mode: Requires tenant in canary list
  - Active mode: Requires 336+ hour shadow validation period
  - Admin roles bypass all policy checks

  ## Parameters

  - `snapshot_id` - The snapshot to activate
  - `opts` - Options map:
    - `:actor` - Actor context for authorization (required for non-shadow modes)
    - `:tenant` - Tenant context for canary validation
    - `:correlation_id` - Event correlation ID (optional, auto-generated)

  ## Returns

  - `{:ok, snapshot}` - Activation successful and policy authorized
  - `{:error, {:policy_violation, reason}}` - Authorization denied by policy
  - `{:error, {:snapshot_not_found, reason}}` - Snapshot doesn't exist
  - `{:error, {:activation_failed, reason}}` - Database update failed
  - `{:error, {:deactivation_failed, reason}}` - Previous snapshot deactivation failed

  ## Examples

      # Shadow mode activation (no auth required)
      {:ok, snapshot} = SnapshotManager.activate_snapshot(snapshot_id)

      # Canary mode activation (requires tenant)
      {:ok, snapshot} = SnapshotManager.activate_snapshot(
        snapshot_id,
        %{actor: current_user, tenant: current_tenant}
      )

      # Admin bypass (any mode)
      {:ok, snapshot} = SnapshotManager.activate_snapshot(
        snapshot_id,
        %{actor: %{role: :system}}
      )
  """
  @spec activate_snapshot(binary(), map()) :: {:ok, UpmSnapshot.t()} | {:error, term()}
  def activate_snapshot(snapshot_id, opts \\ %{}) do
    correlation_id = Map.get(opts, :correlation_id, UUID.v7())

    # Extract authorization context
    actor = Map.get(opts, :actor)
    tenant = Map.get(opts, :tenant)

    case Ash.get(UpmSnapshot, snapshot_id) do
      {:ok, snapshot} ->
        # Enforce ThunderCrown policy authorization (HC-22 Task #3)
        case UPMPolicy.can_activate_snapshot?(actor, snapshot, tenant) do
          :ok ->
            # Policy authorized - proceed with activation
            case deactivate_previous_active(snapshot.trainer_id, snapshot_id) do
              :ok ->
                # Activate this snapshot
                case UpmSnapshot.activate(snapshot.id) do
                  {:ok, updated_snapshot} ->
                    Logger.info("""
                    [UPM.SnapshotManager] Activated snapshot
                      id: #{snapshot_id}
                      trainer_id: #{snapshot.trainer_id}
                      version: #{snapshot.version}
                      mode: #{snapshot.mode}
                      actor: #{inspect(actor)}
                    """)

                    # Emit telemetry event
                    :telemetry.execute(
                      [:upm, :snapshot, :activate],
                      %{},
                      %{
                        snapshot_id: updated_snapshot.id,
                        trainer_id: updated_snapshot.trainer_id,
                        version: updated_snapshot.version,
                        mode: updated_snapshot.mode,
                        actor: actor,
                        tenant: tenant
                      }
                    )

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
            # Policy denied activation - log and return violation error
            Logger.warning("""
            [UPM.SnapshotManager] Policy violation prevented snapshot activation
              snapshot_id: #{snapshot_id}
              mode: #{snapshot.mode}
              reason: #{inspect(reason)}
              actor: #{inspect(actor)}
              tenant: #{inspect(tenant)}
            """)

            {:error, {:policy_violation, reason}}
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
        case UpmSnapshot.rollback(snapshot.id) do
          {:ok, updated_snapshot} ->
            Logger.warning("""
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

    query =
      UpmSnapshot
      |> Ash.Query.filter(trainer_id == ^trainer_id)

    query =
      if status_filter do
        Ash.Query.filter(query, status == ^status_filter)
      else
        query
      end

    query =
      query
      |> Ash.Query.limit(limit)
      |> Ash.Query.sort(version: :desc)

    case Ash.read(query) do
      {:ok, snapshots} -> {:ok, snapshots}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the currently active snapshot for a trainer.
  """
  @spec get_active_snapshot(binary()) :: {:ok, UpmSnapshot.t() | nil} | {:error, term()}
  def get_active_snapshot(trainer_id) do
    query =
      UpmSnapshot
      |> Ash.Query.filter(trainer_id == ^trainer_id and status == :activated)
      |> Ash.Query.sort(activated_at: :desc)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [snapshot]} -> {:ok, snapshot}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a snapshot and its associated file from storage.

  Returns `:ok` on success or `{:error, reason}` on failure.
  Cannot delete active snapshots - they must be deactivated first.

  ## Examples

      iex> delete_snapshot(snapshot_id)
      :ok

      iex> delete_snapshot(active_snapshot_id)
      {:error, :cannot_delete_active_snapshot}

  """
  @spec delete_snapshot(binary()) :: :ok | {:error, term()}
  def delete_snapshot(snapshot_id) do
    with {:ok, snapshot} <- Ash.get(UpmSnapshot, snapshot_id),
         :ok <- check_not_active(snapshot),
         :ok <- delete_snapshot_file(snapshot),
         :ok <- Ash.destroy(snapshot) do
      Logger.info("""
      [UPM.SnapshotManager] Deleted snapshot
        id: #{snapshot.id}
        trainer_id: #{snapshot.trainer_id}
        version: #{snapshot.version}
      """)

      :ok
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, :snapshot_not_found}

      {:error, reason} ->
        Logger.error("""
        [UPM.SnapshotManager] Failed to delete snapshot
          id: #{snapshot_id}
          reason: #{inspect(reason)}
        """)

        {:error, reason}
    end
  end

  @doc """
  Cleans up old snapshots based on retention policy.
  """
  @spec cleanup_old_snapshots(binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cleanup_old_snapshots(trainer_id, opts \\ []) do
    retention_days = Keyword.get(opts, :retention_days, 30)

    cutoff_date =
      DateTime.utc_now() |> DateTime.add(-retention_days, :day) |> DateTime.add(-5, :second)

    query =
      UpmSnapshot
      |> Ash.Query.filter(
        trainer_id == ^trainer_id and status in [:created, :rolled_back, :archived]
      )
      |> Ash.Query.load([:inserted_at])

    case Ash.read(query) do
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
        :upm_snapshot_storage_path,
        "/var/lib/thunderline/upm/snapshots"
      )

    Path.join([base_path, trainer_id, "v#{version}", "#{snapshot_id}.bin"])
  end

  defp maybe_compress(data) do
    compression =
      Application.get_env(:thunderline, :upm_snapshot_compression, :zstd)

    case compression do
      :zstd ->
        if Code.ensure_loaded?(:ezstd) do
          # Use apply to avoid compile-time warning about undefined module
          {:ok, compressed} = apply(:ezstd, :compress, [data])
          {compressed, "zstd"}
        else
          # Fall back to gzip if ezstd not available
          compressed = :zlib.gzip(data)
          {compressed, "gzip"}
        end

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
    if Code.ensure_loaded?(:ezstd) do
      # Use apply to avoid compile-time warning about undefined module
      {:ok, decompressed} = apply(:ezstd, :decompress, [data])
      decompressed
    else
      # Can't decompress zstd without ezstd module
      raise "Cannot decompress zstd data: :ezstd module not available"
    end
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

  # Helper for delete_snapshot/1 - check if snapshot is not active
  defp check_not_active(%{status: :active}) do
    {:error, :cannot_delete_active_snapshot}
  end

  defp check_not_active(_snapshot), do: :ok

  # Helper for delete_snapshot/1 - delete the physical file
  defp delete_snapshot_file(%{storage_path: path}) do
    case File.rm(path) do
      :ok -> :ok
      # File already gone, that's fine
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:file_deletion_failed, reason}}
    end
  end

  defp deactivate_previous_active(trainer_id, exclude_id) do
    query =
      UpmSnapshot
      |> Ash.Query.filter(
        trainer_id == ^trainer_id and status == :activated and id != ^exclude_id
      )

    case Ash.read(query) do
      {:ok, snapshots} ->
        Enum.each(snapshots, fn snapshot ->
          case UpmSnapshot.deactivate(snapshot.id) do
            {:ok, _} ->
              Logger.debug("[UPM.SnapshotManager] Deactivated snapshot #{snapshot.id}")

            {:error, reason} ->
              Logger.warning(
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
    case Thunderline.Event.new(
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
         ) do
      {:ok, event} ->
        # Publish to EventBus for saga/worker consumption
        Thunderline.Thunderflow.EventBus.publish_event(event)

        # Also broadcast to PubSub for real-time notifications
        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "ai:upm:snapshot:activated",
          {:event_bus, event}
        )

        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_rollback_event(snapshot, correlation_id) do
    case Thunderline.Event.new(
           name: "ai.upm.rollback",
           source: :bolt,
           payload: %{
             snapshot_id: snapshot.id,
             trainer_id: snapshot.trainer_id,
             version: snapshot.version,
             reason: "manual_rollback"
           },
           correlation_id: correlation_id
         ) do
      {:ok, event} ->
        Thunderline.Thunderflow.EventBus.publish_event(event)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
