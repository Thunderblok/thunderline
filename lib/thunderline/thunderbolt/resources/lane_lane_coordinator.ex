defmodule Thunderline.Thunderbolt.Resources.LaneCoordinator do
  @moduledoc """
  LaneCoordinator Resource - Coordination state and control for lane management.

  This resource tracks the active coordination state for each dimensional lane
  and interfaces with the THUNDERCELL compute plane for runtime coordination.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource, AshEvents.Events]
  require Logger

  postgres do
    table "thunderlane_coordinators"
    repo Thunderline.Repo
  end

  # ============================================================================
  # JSON API
  # ============================================================================

  json_api do
    type "lane_coordinator"

    routes do
      base("/coordinators")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      patch(:coordinate, route: "/:id/coordinate")
      patch(:sync_status, route: "/:id/sync")
      patch(:heartbeat, route: "/:id/heartbeat")
      patch(:pause, route: "/:id/pause")
      patch(:resume, route: "/:id/resume")
      patch(:shutdown, route: "/:id/shutdown")
    end
  end

  # ============================================================================
  # GRAPHQL
  # ============================================================================

  graphql do
    type :lane_coordinator

    queries do
      get :get_coordinator, :read
      list :list_coordinators, :read
      list :active_coordinators, :active_coordinators
    end

    mutations do
      create :create_coordinator, :create
      update :update_coordinator, :update
      update :coordinate_lane, :coordinate
      update :sync_coordinator_status, :sync_status
      update :pause_coordinator, :pause
      update :resume_coordinator, :resume
      update :shutdown_coordinator, :shutdown
    end
  end

  # ============================================================================
  # EVENTS
  # ============================================================================

  events do
    event_log(Thunderline.Thunderflow.Events.Event)
    current_action_versions(create: 1, update: 1, destroy: 1)
  end

  # ============================================================================
  # ACTIONS
  # ============================================================================

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :lane_dimension,
        :name,
        :description,
        :topology_shape,
        :target_ups,
        :max_coordination_latency_ms,
        :max_queue_size,
        :config,
        :metadata
      ]

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :initializing)
        |> Ash.Changeset.change_attribute(:coordinator_node, to_string(Node.self()))
      end

      change after_action(&start_coordinator_process/2)
    end

    update :update do
      accept [
        :name,
        :description,
        :topology_shape,
        :target_ups,
        :max_coordination_latency_ms,
        :max_queue_size,
        :config,
        :metadata
      ]
    end

    update :coordinate do
      accept [:active_ruleset_id, :active_ruleset_version]

      change before_action(&validate_ruleset/1)
      change after_action(&deploy_ruleset_to_lane/2)
    end

    update :sync_status do
      accept [
        :status,
        :cells_managed,
        :updates_per_second,
        :coordination_latency_ms,
        :event_queue_size,
        :events_processed,
        :events_dropped,
        :coupling_buffers,
        :coupling_backpressure,
        :error_count,
        :last_error,
        :last_error_at
      ]

      change set_attribute(:last_sync_at, &DateTime.utc_now/0)
    end

    update :heartbeat do
      accept []
      change set_attribute(:last_heartbeat_at, &DateTime.utc_now/0)
    end

    update :pause do
      accept []
      change set_attribute(:status, :paused)
      change after_action(&pause_coordinator_process/2)
    end

    update :resume do
      accept []
      change set_attribute(:status, :active)
      change after_action(&resume_coordinator_process/2)
    end

    update :shutdown do
      accept []
      change set_attribute(:status, :shutdown)
      change after_action(&shutdown_coordinator_process/2)
    end

    read :active_coordinators do
      filter expr(status == :active)
    end

    read :by_dimension do
      argument :dimension, :atom, allow_nil?: false
      filter expr(lane_dimension == ^arg(:dimension))
    end

    read :with_ruleset do
      argument :ruleset_id, :uuid, allow_nil?: false
      filter expr(active_ruleset_id == ^arg(:ruleset_id))
    end
  end

  # ============================================================================
  # ATTRIBUTES
  # ============================================================================

  attributes do
    uuid_primary_key :id

    # Core Identity
    attribute :lane_dimension, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:x, :y, :z]]

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    # Active Configuration
    attribute :active_ruleset_id, :uuid, public?: true
    attribute :active_ruleset_version, :integer, public?: true

    # Coordination State
    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      default: :initializing,
      constraints: [one_of: [:initializing, :active, :paused, :error, :shutdown]]

    # Topology Configuration
    attribute :topology_shape, :map,
      allow_nil?: false,
      public?: true,
      default: %{
        width: 128,
        height: 128,
        depth: 64
      }

    # Runtime Metrics
    attribute :cells_managed, :integer, public?: true, default: 0
    attribute :updates_per_second, :float, public?: true, default: 0.0
    attribute :last_sync_at, :utc_datetime_usec, public?: true
    attribute :coordination_latency_ms, :float, public?: true

    # GenServer Process State
    attribute :coordinator_pid, :string, public?: true
    attribute :coordinator_node, :string, public?: true
    attribute :last_heartbeat_at, :utc_datetime_usec, public?: true

    # Cross-Lane Coupling State
    attribute :coupling_enabled, :boolean, allow_nil?: false, public?: true, default: true
    attribute :coupling_buffers, :map, public?: true, default: %{}
    attribute :coupling_backpressure, :map, public?: true, default: %{}

    # Event Processing State
    attribute :event_queue_size, :integer, public?: true, default: 0
    attribute :events_processed, :integer, public?: true, default: 0
    attribute :events_dropped, :integer, public?: true, default: 0

    # Performance Targets
    attribute :target_ups, :float, allow_nil?: false, public?: true, default: 1000.0
    attribute :max_coordination_latency_ms, :float, allow_nil?: false, public?: true, default: 5.0
    attribute :max_queue_size, :integer, allow_nil?: false, public?: true, default: 10000

    # Error Tracking
    attribute :error_count, :integer, public?: true, default: 0
    attribute :last_error, :string, public?: true
    attribute :last_error_at, :utc_datetime_usec, public?: true

    # Configuration
    attribute :config, :map, public?: true, default: %{}
    attribute :metadata, :map, public?: true, default: %{}

    # Timestamps
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  # ============================================================================
  # RELATIONSHIPS
  # ============================================================================

  relationships do
    belongs_to :active_ruleset, Thunderline.Thunderbolt.Resources.RuleSet do
      attribute_writable? true
      public? true
    end

    has_many :lane_metrics, Thunderline.Thunderbolt.Resources.LaneMetrics do
      public? true
    end

    has_many :cell_topologies, Thunderline.Thunderbolt.Resources.CellTopology do
      public? true
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp start_coordinator_process(_changeset, coordinator) do
    case maybe_start_lane_coordinator(coordinator) do
      {:ok, pid} ->
        coordinator
        |> Ash.Changeset.for_update(:update, %{
          coordinator_pid: inspect(pid),
          status: :active,
          last_heartbeat_at: DateTime.utc_now()
        })
        |> Ash.update()

      {:error, reason} ->
        coordinator
        |> Ash.Changeset.for_update(:update, %{
          status: :error,
          last_error: "Failed to start coordinator: #{inspect(reason)}",
          last_error_at: DateTime.utc_now()
        })
        |> Ash.update()
    end
  end

  defp validate_ruleset(changeset) do
    case Ash.Changeset.get_attribute(changeset, :active_ruleset_id) do
      nil ->
        changeset

      ruleset_id ->
        case Ash.get(Thunderline.Thunderbolt.Resources.RuleSet, ruleset_id) do
          {:ok, %{status: :active}} ->
            changeset

          {:ok, _} ->
            Ash.Changeset.add_error(changeset,
              field: :active_ruleset_id,
              message: "RuleSet must be in active status"
            )

          {:error, _} ->
            Ash.Changeset.add_error(changeset,
              field: :active_ruleset_id,
              message: "RuleSet not found"
            )
        end
    end
  end

  defp deploy_ruleset_to_lane(_changeset, coordinator) do
    # Signal the coordinator GenServer to deploy the new ruleset
    case parse_pid(coordinator.coordinator_pid) do
      {:ok, pid} ->
        maybe_deploy_ruleset(pid, coordinator.active_ruleset_id)
        {:ok, coordinator}

      :error ->
        {:ok, coordinator}
    end
  end

  defp pause_coordinator_process(_changeset, coordinator) do
    signal_coordinator(coordinator, :pause)
    {:ok, coordinator}
  end

  defp resume_coordinator_process(_changeset, coordinator) do
    signal_coordinator(coordinator, :resume)
    {:ok, coordinator}
  end

  defp shutdown_coordinator_process(_changeset, coordinator) do
    signal_coordinator(coordinator, :shutdown)
    {:ok, coordinator}
  end

  defp signal_coordinator(coordinator, signal) do
    case parse_pid(coordinator.coordinator_pid) do
      {:ok, pid} ->
        safe_call(pid, signal)
      :error ->
        :ok
    end
  end

  defp maybe_start_lane_coordinator(coordinator) do
    if Code.ensure_loaded?(Thunderline.Thunderbolt.LaneCoordinator.Supervisor) and
         function_exported?(Thunderline.Thunderbolt.LaneCoordinator.Supervisor, :start_coordinator, 1) do
      Thunderline.Thunderbolt.LaneCoordinator.Supervisor.start_coordinator(coordinator)
    else
      {:error, :lane_coordinator_supervisor_unavailable}
    end
  end

  defp maybe_deploy_ruleset(pid, ruleset_id) do
    if Code.ensure_loaded?(Thunderline.Thunderbolt.LaneCoordinator.GenServer) and
         function_exported?(Thunderline.Thunderbolt.LaneCoordinator.GenServer, :deploy_ruleset, 2) do
      Thunderline.Thunderbolt.LaneCoordinator.GenServer.deploy_ruleset(pid, ruleset_id)
    else
      Logger.debug("[LaneCoordinator] coordinator GenServer unavailable, skipping deploy")
      :ok
    end
  end

  defp parse_pid(nil), do: :error

  defp parse_pid(pid_string) when is_binary(pid_string) do
    candidate =
      pid_string
      |> String.trim()
      |> String.trim_leading("#PID")

    if candidate == "" do
      :error
    else
      candidate
      |> String.to_charlist()
      |> safe_list_to_pid()
    end
  rescue
    ArgumentError -> :error
  end

  defp parse_pid(_), do: :error

  defp safe_list_to_pid(charlist) do
    try do
      {:ok, :erlang.list_to_pid(charlist)}
    rescue
      _ -> :error
    end
  end

  defp safe_call(pid, message) do
    try do
      GenServer.call(pid, message)
    catch
      :exit, _ -> :ok
      _type, _reason -> :ok
    end
  end
end
