defmodule Thunderline.Thundergrid.Resources.ChunkState do
  @moduledoc """
  ChunkState Resource - Real-time Cellular Automata State Management

  This resource provides GraphQL interface to thundercore.unikernel computational state
  via the Thunderlane bridge. Enables real-time queries and subscriptions to CA chunks.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: Ash.DataLayer.Ets

  alias Thunderline.Thunderlane

  attributes do
    uuid_v7_primary_key :id

    attribute :chunk_id, :string do
      allow_nil? false
      description "Unique identifier for the CA chunk in unikernel"
    end

    attribute :size, :map do
      allow_nil? false
      description "Chunk dimensions {x, y, z}"
      default %{x: 64, y: 64, z: 64}
    end

    attribute :tick_rate, :integer do
      allow_nil? false
      description "Ticks per second for CA computation"
      default 60
    end

    attribute :active, :boolean do
      allow_nil? false
      description "Whether the chunk is actively computing"
      default false
    end

    attribute :voxel_count, :integer do
      allow_nil? false
      description "Total number of voxels in the chunk"
      default 0
    end

    attribute :active_voxels, :integer do
      allow_nil? false
      description "Number of active/living voxels"
      default 0
    end

    attribute :ca_rules, :map do
      allow_nil? false
      description "Cellular automata rule configuration"
      default %{
        birth_rules: [3],
        survival_rules: [2, 3],
        neighborhood: :moore,
        boundary_conditions: :periodic
      }
    end

    attribute :performance_metrics, :map do
      description "Real-time performance data from unikernel"
      default %{}
    end

    attribute :last_tick, :integer do
      description "Last computed tick number"
      default 0
    end

    attribute :state_snapshot, :binary do
      description "Compressed voxel grid state"
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :spawn_chunk do
      description "Spawn a new CA chunk in the unikernel"

      argument :size, :map do
        allow_nil? false
        description "Chunk size {x, y, z}"
      end

      argument :ca_rules, :map do
        description "Initial CA rule configuration"
      end

      change fn changeset, _context ->
        size = Ash.Changeset.get_argument(changeset, :size)
        ca_rules = Ash.Changeset.get_argument(changeset, :ca_rules)

        # Generate unique chunk ID
        chunk_id = "chunk_#{System.unique_integer([:positive])}"

        # Calculate voxel count
        voxel_count = size.x * size.y * size.z

        changeset
        |> Ash.Changeset.change_attribute(:chunk_id, chunk_id)
        |> Ash.Changeset.change_attribute(:size, size)
        |> Ash.Changeset.change_attribute(:voxel_count, voxel_count)
        |> Ash.Changeset.change_attribute(:ca_rules, ca_rules || %{
          birth_rules: [3],
          survival_rules: [2, 3],
          neighborhood: :moore,
          boundary_conditions: :periodic
        })
      end

      change after_action(fn changeset, chunk_state, _context ->
        # Spawn chunk in unikernel via Thunderlane
        size_tuple = {chunk_state.size.x, chunk_state.size.y, chunk_state.size.z}

        case Thunderlane.spawn_chunk(size_tuple) do
          {:ok, _unikernel_response} ->
            # Set CA rules
            Thunderlane.set_ca_rules(chunk_state.chunk_id, chunk_state.ca_rules)
            {:ok, chunk_state}

          {:error, reason} ->
            {:error, "Failed to spawn chunk in unikernel: #{inspect(reason)}"}
        end
      end)
    end

    update :set_ca_rules do
      description "Update cellular automata rules for the chunk"
      require_atomic? false

      argument :ca_rules, :map do
        allow_nil? false
        description "New CA rule configuration"
      end

      change fn changeset, _context ->
        ca_rules = Ash.Changeset.get_argument(changeset, :ca_rules)
        Ash.Changeset.change_attribute(changeset, :ca_rules, ca_rules)
      end

      change after_action(fn changeset, chunk_state, _context ->
        # Update rules in unikernel
        case Thunderlane.set_ca_rules(chunk_state.chunk_id, chunk_state.ca_rules) do
          {:ok, _} ->
            {:ok, chunk_state}

          {:error, reason} ->
            {:error, "Failed to update CA rules: #{inspect(reason)}"}
        end
      end)
    end

    update :start_computation do
      description "Start tick generation for the chunk"
      require_atomic? false

      argument :tick_rate, :integer do
        description "Ticks per second"
        default 60
      end

      change fn changeset, _context ->
        tick_rate = Ash.Changeset.get_argument(changeset, :tick_rate)

        changeset
        |> Ash.Changeset.change_attribute(:tick_rate, tick_rate)
        |> Ash.Changeset.change_attribute(:active, true)
      end

      change after_action(fn changeset, chunk_state, _context ->
        case Thunderlane.start_tick_generation(chunk_state.chunk_id, chunk_state.tick_rate) do
          {:ok, _} ->
            {:ok, chunk_state}

          {:error, reason} ->
            {:error, "Failed to start computation: #{inspect(reason)}"}
        end
      end)
    end

    update :stop_computation do
      description "Stop tick generation for the chunk"
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :active, false)
      end

      change after_action(fn changeset, chunk_state, _context ->
        case Thunderlane.stop_tick_generation(chunk_state.chunk_id) do
          {:ok, _} ->
            {:ok, chunk_state}

          {:error, reason} ->
            {:error, "Failed to stop computation: #{inspect(reason)}"}
        end
      end)
    end

    read :get_realtime_state do
      description "Get real-time state from unikernel"

      get? true

      filter expr(chunk_id == ^arg(:chunk_id))

      argument :chunk_id, :string do
        allow_nil? false
      end

      prepare fn query, _context ->
        # This will trigger the custom data layer to fetch from unikernel
        query
      end
    end
  end

  calculations do
    calculate :utilization_percentage, :float do
      description "Percentage of active voxels"

      calculation fn records, _context ->
        Enum.map(records, fn record ->
          if record.voxel_count > 0 do
            (record.active_voxels / record.voxel_count) * 100
          else
            0.0
          end
        end)
      end
    end

    calculate :performance_score, :float do
      description "Performance score based on tick rate and utilization"

      calculation fn records, _context ->
        Enum.map(records, fn record ->
          utilization = if record.voxel_count > 0 do
            (record.active_voxels / record.voxel_count) * 100
          else
            0.0
          end

          # Score based on tick rate achievement and utilization
          tick_efficiency = case record.performance_metrics do
            %{actual_tick_rate: actual} when is_number(actual) ->
              min(actual / record.tick_rate, 1.0)
            _ -> 0.0
          end

          (tick_efficiency * 50) + (utilization * 50) / 100
        end)
      end
    end
  end

  identities do
    identity :unique_chunk_id, [:chunk_id] do
      pre_check_with Thunderline.Thundergrid.Domain
    end
  end

  # Real-time state management functions
  defmodule RealtimeState do
    @moduledoc """
    Real-time state management for CA chunks
    """

    alias Phoenix.PubSub

    @doc """
    Subscribe to real-time updates for a chunk
    """
    def subscribe_to_chunk(chunk_id) do
      PubSub.subscribe(Thunderline.PubSub, "chunk_updates:#{chunk_id}")
    end

    @doc """
    Broadcast chunk state update
    """
    def broadcast_chunk_update(chunk_id, state_data) do
      PubSub.broadcast(
        Thunderline.PubSub,
        "chunk_updates:#{chunk_id}",
        {:chunk_state_update, chunk_id, state_data}
      )
    end

    @doc """
    Get live performance metrics
    """
    def get_live_metrics(chunk_id) do
      case Thunderlane.get_chunk_state(chunk_id) do
        {:ok, unikernel_state} ->
          {:ok, transform_unikernel_state(unikernel_state)}

        error ->
          error
      end
    end

    defp transform_unikernel_state(unikernel_data) do
      # Transform unikernel data format to ChunkState attributes
      %{
        active_voxels: Map.get(unikernel_data, :active_voxel_count, 0),
        last_tick: Map.get(unikernel_data, :current_tick, 0),
        performance_metrics: Map.get(unikernel_data, :performance, %{}),
        state_snapshot: Map.get(unikernel_data, :voxel_grid_data)
      }
    end
  end
end
