defmodule Thunderline.Thundergrid.UnikernelDataLayer do
  @moduledoc """
  Custom Ash Data Layer for Unikernel Integration

  This data layer bridges Ash resources with the thundercore.unikernel
  computational state via the Thunderlane protocol bridge.

  Unlike traditional data layers that work with databases, this layer
  interfaces with real-time computational processes in the unikernel.
  """

  alias Thunderline.Thunderbolt.Thunderlane

  @behaviour Ash.DataLayer

  # Data Layer Configuration
  defstruct [:config]

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
  def can?(_, :sort), do: false
  def can?(_, :filter), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, :transact), do: false
  def can?(_, :multitenancy), do: false
  def can?(_, :upsert), do: false
  def can?(_, :composite_primary_key), do: false
  def can?(_, _), do: false

  @impl true
  def run_query(query, _resource) do
    # Extract filter conditions
    chunk_id = extract_chunk_id_filter(query)

    case chunk_id do
      nil ->
        # Return empty result for queries without chunk_id
        {:ok, []}

      chunk_id when is_binary(chunk_id) ->
        fetch_chunk_state_from_unikernel(chunk_id)
    end
  end

  @impl true
  def create(_resource, changeset) do
    # For ChunkState creation, the actual chunk spawning
    # happens in the after_action hook, not here

    # Generate a mock record for Ash to work with
    attributes = changeset.attributes

    record = struct(changeset.resource, attributes)
    {:ok, record}
  end

  @impl true
  def update(_resource, changeset) do
    # Updates are handled via Thunderlane in after_action hooks
    record = struct(changeset.resource, changeset.attributes)
    {:ok, record}
  end

  @impl true
  def destroy(_resource, _changeset) do
    # Chunk destruction would involve commanding the unikernel
    # to deallocate the computational resources
    {:ok, %{}}
  end

  @impl true
  def source(_resource) do
    "unikernel_chunks"
  end

  @impl true
  def resource_to_query(resource, _domain) do
    # Return base query for the resource
    Ash.Query.for_read(resource, :read)
  end

  # Private Functions

  defp extract_chunk_id_filter(query) do
    # Extract chunk_id from query filters
    case query.filter do
      %{expression: %{left: %{name: :chunk_id}, right: %{value: chunk_id}}} ->
        chunk_id

      _ ->
        nil
    end
  end

  defp fetch_chunk_state_from_unikernel(chunk_id) do
    case Thunderlane.get_chunk_state(chunk_id) do
      {:ok, unikernel_state} ->
        chunk_state = transform_unikernel_to_ash_record(chunk_id, unikernel_state)
        {:ok, [chunk_state]}

      {:error, :not_connected} ->
        # Return cached/placeholder data when unikernel is offline
        placeholder_record = create_placeholder_record(chunk_id)
        {:ok, [placeholder_record]}

      {:error, reason} ->
        {:error, "Failed to fetch chunk state: #{inspect(reason)}"}
    end
  end

  defp transform_unikernel_to_ash_record(chunk_id, unikernel_data) do
    %Thunderline.Thundergrid.Resources.ChunkState{
      id: Ash.UUID.generate(),
      chunk_id: chunk_id,
      size: Map.get(unikernel_data, :chunk_size, %{x: 64, y: 64, z: 64}),
      tick_rate: Map.get(unikernel_data, :tick_rate, 60),
      active: Map.get(unikernel_data, :is_active, false),
      voxel_count:
        calculate_voxel_count(Map.get(unikernel_data, :chunk_size, %{x: 64, y: 64, z: 64})),
      active_voxels: Map.get(unikernel_data, :active_voxel_count, 0),
      ca_rules:
        Map.get(unikernel_data, :ca_rules, %{
          birth_rules: [3],
          survival_rules: [2, 3],
          neighborhood: :moore,
          boundary_conditions: :periodic
        }),
      performance_metrics: Map.get(unikernel_data, :performance_metrics, %{}),
      last_tick: Map.get(unikernel_data, :current_tick, 0),
      state_snapshot: Map.get(unikernel_data, :voxel_grid_compressed),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  defp create_placeholder_record(chunk_id) do
    %Thunderline.Thundergrid.Resources.ChunkState{
      id: Ash.UUID.generate(),
      chunk_id: chunk_id,
      size: %{x: 64, y: 64, z: 64},
      tick_rate: 60,
      active: false,
      # 64^3
      voxel_count: 262_144,
      active_voxels: 0,
      ca_rules: %{
        birth_rules: [3],
        survival_rules: [2, 3],
        neighborhood: :moore,
        boundary_conditions: :periodic
      },
      performance_metrics: %{status: "unikernel_offline"},
      last_tick: 0,
      state_snapshot: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  defp calculate_voxel_count(%{x: x, y: y, z: z})
       when is_integer(x) and is_integer(y) and is_integer(z) do
    x * y * z
  end

  defp calculate_voxel_count(_), do: 0

  # Configuration for Ash
  def data_layer(opts \\ []) do
    struct(__MODULE__, config: opts)
  end
end
