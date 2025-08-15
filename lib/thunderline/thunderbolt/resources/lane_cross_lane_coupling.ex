defmodule Thunderline.Thunderbolt.Resources.CrossLaneCoupling do
  @moduledoc """
  CrossLaneCoupling Resource - Configuration and state for inter-lane coupling.

  This resource manages the α-gain coupling configurations between dimensional
  lanes and tracks coupling performance metrics for optimization.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource, AshEvents.Events]

  postgres do
    table "thunderlane_cross_lane_coupling"
    repo Thunderline.Repo
  end

  # ============================================================================
  # JSON API
  # ============================================================================

  json_api do
    type "cross_lane_coupling"

    routes do
      base("/couplings")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      patch(:tune_alpha, route: "/:id/tune-alpha")
      patch(:activate, route: "/:id/activate")
      patch(:deactivate, route: "/:id/deactivate")
      patch(:measure_performance, route: "/:id/measure")
      patch(:record_error, route: "/:id/error")
    end
  end

  # ============================================================================
  # GRAPHQL
  # ============================================================================

  graphql do
    type :cross_lane_coupling

    queries do
      get :get_coupling, :read
      list :list_couplings, :read
      list :active_couplings, :active_couplings
      list :adaptive_couplings, :adaptive_couplings
      list :couplings_needing_tuning, :needs_tuning
    end

    mutations do
      create :create_coupling, :create
      update :update_coupling, :update
      update :tune_coupling_alpha, :tune_alpha
      update :activate_coupling, :activate
      update :deactivate_coupling, :deactivate
      update :measure_coupling_performance, :measure_performance
      update :record_coupling_error, :record_error
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
        :source_lane,
        :target_lane,
        :name,
        :alpha_gain,
        :coupling_type,
        :coupling_function,
        :coupling_params,
        :spatial_kernel,
        :kernel_params,
        :temporal_delay,
        :temporal_window,
        :adaptive_enabled,
        :adaptation_rate,
        :adaptation_bounds,
        :config,
        :metadata,
        :ruleset_id
      ]

      change fn changeset, _ ->
        # Auto-generate name if not provided
        source = Ash.Changeset.get_attribute(changeset, :source_lane)
        target = Ash.Changeset.get_attribute(changeset, :target_lane)

        name =
          Ash.Changeset.get_attribute(changeset, :name) ||
            "#{source}_to_#{target}_coupling"

        changeset
        |> Ash.Changeset.change_attribute(:name, name)
        |> Ash.Changeset.change_attribute(:status, :inactive)
      end

      change after_action(&initialize_coupling_pipeline/2)
    end

    update :update do
      accept [
        :name,
        :alpha_gain,
        :coupling_type,
        :coupling_function,
        :coupling_params,
        :spatial_kernel,
        :kernel_params,
        :temporal_delay,
        :temporal_window,
        :adaptive_enabled,
        :adaptation_rate,
        :adaptation_bounds,
        :config,
        :metadata
      ]

      change after_action(&reconfigure_coupling_pipeline/2)
    end

    update :tune_alpha do
      accept [:alpha_gain]

      change before_action(&validate_alpha_bounds/1)
      change after_action(&apply_alpha_tuning/2)
    end

    update :activate do
      accept []
      change set_attribute(:status, :active)
      change after_action(&activate_coupling_pipeline/2)
    end

    update :deactivate do
      accept []
      change set_attribute(:status, :inactive)
      change after_action(&deactivate_coupling_pipeline/2)
    end

    update :measure_performance do
      accept [
        :coupling_strength,
        :mutual_information,
        :phase_coherence,
        :energy_transfer,
        :stability_measure,
        :buffer_size,
        :events_coupled,
        :coupling_latency_ms,
        :health_score
      ]

      change after_action(&update_performance_trend/2)
    end

    update :record_error do
      accept [:last_error]

      change fn changeset, _ ->
        current_errors = Ash.Changeset.get_data(changeset).error_count || 0

        changeset
        |> Ash.Changeset.change_attribute(:error_count, current_errors + 1)
        |> Ash.Changeset.change_attribute(:last_error_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:status, :error)
      end
    end

    read :active_couplings do
      filter expr(status == :active)
    end

    read :by_lanes do
      argument :source, :atom, allow_nil?: false
      argument :target, :atom, allow_nil?: false
      filter expr(source_lane == ^arg(:source) and target_lane == ^arg(:target))
    end

    read :for_ruleset do
      argument :ruleset_id, :uuid, allow_nil?: false
      filter expr(ruleset_id == ^arg(:ruleset_id))
    end

    read :adaptive_couplings do
      filter expr(adaptive_enabled == true)
    end

    read :needs_tuning do
      filter expr(performance_trend == :degrading or health_score < 0.7)
    end
  end

  # ============================================================================
  # ATTRIBUTES
  # ============================================================================

  attributes do
    uuid_primary_key :id

    # Coupling Identity
    attribute :source_lane, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:x, :y, :z]]

    attribute :target_lane, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:x, :y, :z]]

    attribute :name, :string, public?: true

    # Foreign Keys for Relationships
    attribute :rule_set_id, :uuid, public?: true

    # Core Coupling Parameters
    attribute :alpha_gain, :float,
      allow_nil?: false,
      public?: true,
      default: 0.25,
      constraints: [min: 0.0, max: 1.0]

    attribute :coupling_type, :atom,
      allow_nil?: false,
      public?: true,
      default: :symmetric,
      constraints: [one_of: [:symmetric, :asymmetric, :dynamic]]

    # Coupling Function Configuration
    attribute :coupling_function, :atom,
      allow_nil?: false,
      public?: true,
      default: :linear,
      constraints: [one_of: [:linear, :sigmoid, :exponential, :polynomial, :custom]]

    attribute :coupling_params, :map, public?: true, default: %{}

    # Spatial Configuration
    attribute :spatial_kernel, :atom,
      allow_nil?: false,
      public?: true,
      default: :cross_3x3,
      constraints: [one_of: [:cross_3x3, :moore_3x3, :von_neumann, :gaussian, :custom]]

    attribute :kernel_params, :map, public?: true, default: %{}

    # Temporal Configuration
    attribute :temporal_delay, :integer,
      allow_nil?: false,
      public?: true,
      default: 0,
      constraints: [min: 0, max: 10]

    attribute :temporal_window, :integer,
      allow_nil?: false,
      public?: true,
      default: 1,
      constraints: [min: 1, max: 32]

    # Adaptive/Dynamic Configuration
    attribute :adaptive_enabled, :boolean, allow_nil?: false, public?: true, default: false

    attribute :adaptation_rate, :float,
      public?: true,
      default: 0.01,
      constraints: [min: 0.0, max: 0.1]

    attribute :adaptation_bounds, :map, public?: true, default: %{min: 0.0, max: 1.0}

    # Performance Metrics
    attribute :coupling_strength, :float, public?: true
    attribute :mutual_information, :float, public?: true
    attribute :phase_coherence, :float, public?: true
    attribute :energy_transfer, :float, public?: true
    attribute :stability_measure, :float, public?: true

    # Runtime State
    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      default: :inactive,
      constraints: [one_of: [:inactive, :active, :tuning, :error]]

    attribute :buffer_size, :integer, public?: true, default: 0
    attribute :events_coupled, :integer, public?: true, default: 0
    attribute :coupling_latency_ms, :float, public?: true

    # Error and Health Tracking
    attribute :error_count, :integer, public?: true, default: 0
    attribute :last_error, :string, public?: true
    attribute :last_error_at, :utc_datetime_usec, public?: true

    attribute :health_score, :float,
      public?: true,
      default: 1.0,
      constraints: [min: 0.0, max: 1.0]

    # Optimization Tracking
    attribute :tuning_history, :map, public?: true, default: %{}

    attribute :performance_trend, :atom,
      public?: true,
      constraints: [one_of: [:improving, :stable, :degrading, :unknown]]

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
    belongs_to :ruleset, Thunderline.Thunderbolt.Resources.RuleSet do
      attribute_writable? true
      public? true
    end

    has_many :coupling_metrics, Thunderline.Thunderbolt.Resources.LaneMetrics do
      public? true
    end
  end

  # ============================================================================
  # IDENTITIES
  # ============================================================================

  identities do
    identity :unique_lane_coupling, [:source_lane, :target_lane, :ruleset_id]
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp initialize_coupling_pipeline(_changeset, coupling) do
    # Initialize the Broadway coupling pipeline for this lane pair
    Thunderline.Thunderbolt.LaneCouplingPipeline.initialize_coupling(coupling)

    # Emit coupling creation event
    Thunderline.EventBus.emit_realtime(:coupling_created, %{
      coupling_id: coupling.id,
      source_lane: coupling.source_lane,
      target_lane: coupling.target_lane,
      alpha_gain: coupling.alpha_gain
    })

    {:ok, coupling}
  end

  defp reconfigure_coupling_pipeline(_changeset, coupling) do
    # Reconfigure the existing coupling pipeline
    Thunderline.Thunderbolt.LaneCouplingPipeline.reconfigure_coupling(coupling)

    {:ok, coupling}
  end

  defp validate_alpha_bounds(changeset) do
    alpha = Ash.Changeset.get_attribute(changeset, :alpha_gain)
    bounds = Ash.Changeset.get_data(changeset).adaptation_bounds || %{min: 0.0, max: 1.0}

    min_alpha = Map.get(bounds, :min, 0.0)
    max_alpha = Map.get(bounds, :max, 1.0)

    if alpha < min_alpha or alpha > max_alpha do
      Ash.Changeset.add_error(changeset,
        field: :alpha_gain,
        message: "Alpha gain #{alpha} outside bounds [#{min_alpha}, #{max_alpha}]"
      )
    else
      changeset
    end
  end

  defp apply_alpha_tuning(_changeset, coupling) do
    # Real-time alpha gain update to all active coordinators
    Thunderline.EventBus.emit_realtime(:alpha_tuned, %{
      coupling_id: coupling.id,
      source_lane: coupling.source_lane,
      target_lane: coupling.target_lane,
      new_alpha: coupling.alpha_gain
    })

    # Update tuning history
    history = coupling.tuning_history || %{}
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    updated_history = Map.put(history, timestamp, coupling.alpha_gain)

    coupling
    |> Ash.Changeset.for_update(:update, %{tuning_history: updated_history})
    |> Ash.update()
  end

  defp activate_coupling_pipeline(_changeset, coupling) do
    Thunderline.Thunderbolt.LaneCouplingPipeline.activate_coupling(coupling.id)

    Thunderline.EventBus.emit_realtime(:coupling_activated, %{
      coupling_id: coupling.id,
      source_lane: coupling.source_lane,
      target_lane: coupling.target_lane
    })

    {:ok, coupling}
  end

  defp deactivate_coupling_pipeline(_changeset, coupling) do
    Thunderline.Thunderbolt.LaneCouplingPipeline.deactivate_coupling(coupling.id)

    Thunderline.EventBus.emit_realtime(:coupling_deactivated, %{
      coupling_id: coupling.id,
      source_lane: coupling.source_lane,
      target_lane: coupling.target_lane
    })

    {:ok, coupling}
  end

  defp update_performance_trend(_changeset, coupling) do
    # Analyze performance trend from recent measurements
    trend = calculate_performance_trend(coupling)

    coupling
    |> Ash.Changeset.for_update(:update, %{performance_trend: trend})
    |> Ash.update()
  end

  defp calculate_performance_trend(coupling) do
    # Simple trend analysis - in production, use more sophisticated metrics
    case coupling.health_score do
      score when score > 0.8 -> :improving
      score when score > 0.6 -> :stable
      score when score > 0.0 -> :degrading
      _ -> :unknown
    end
  end
end
