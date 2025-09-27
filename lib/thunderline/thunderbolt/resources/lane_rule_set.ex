defmodule Thunderline.Thunderbolt.Resources.RuleSet do
  @moduledoc """
  RuleSet Resource - Versioned, signed rule configurations for lane processing.

  This is the core data contract between the Elixir control plane and Erlang
  THUNDERCELL compute plane. All rule configurations flow through this resource.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource, AshEvents.Events]

  require Logger

  postgres do
    table "thunderlane_rulesets"
    repo Thunderline.Repo
  end

  # ============================================================================
  # JSON API
  # ============================================================================

  json_api do
    type "ruleset"

    routes do
      base("/rulesets")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      patch(:activate, route: "/:id/activate")
      patch(:tune_alpha_gains, route: "/:id/tune-alpha")
      patch(:optimize, route: "/:id/optimize")
    end
  end

  # ============================================================================
  # GRAPHQL
  # ============================================================================

  graphql do
    type :ruleset

    queries do
      get :get_ruleset, :read
      list :list_rulesets, :read
      list :active_rulesets, :active_rulesets
      get :latest_ruleset, :latest_version
    end

    mutations do
      create :create_ruleset, :create
      update :update_ruleset, :update
      update :activate_ruleset, :activate
      update :tune_ruleset_alphas, :tune_alpha_gains
      update :optimize_ruleset, :optimize
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
        :name,
        :description,
        :x_lane_rule,
        :y_lane_rule,
        :z_lane_rule,
        :x_lane_params,
        :y_lane_params,
        :z_lane_params,
        :alpha_xy,
        :alpha_xz,
        :alpha_yx,
        :alpha_yz,
        :alpha_zx,
        :alpha_zy,
        :schedule_type,
        :schedule_params,
        :boundaries,
        :parameter_bounds,
        :objective_function,
        :metadata
      ]

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:version, 1)
        |> Ash.Changeset.change_attribute(:status, :draft)
      end

      change after_action(&generate_signature/2)
    end

    update :update do
      accept [
        :name,
        :description,
        :x_lane_rule,
        :y_lane_rule,
        :z_lane_rule,
        :x_lane_params,
        :y_lane_params,
        :z_lane_params,
        :alpha_xy,
        :alpha_xz,
        :alpha_yx,
        :alpha_yz,
        :alpha_zx,
        :alpha_zy,
        :schedule_type,
        :schedule_params,
        :boundaries,
        :parameter_bounds,
        :objective_function,
        :metadata
      ]

      change before_action(&increment_version/1)
      change after_action(&generate_signature/2)
    end

    update :activate do
      accept []

      change set_attribute(:status, :active)
      change set_attribute(:deployed_at, &DateTime.utc_now/0)
      change after_action(&deploy_to_thundercells/2)
    end

    update :tune_alpha_gains do
      accept [:alpha_xy, :alpha_xz, :alpha_yx, :alpha_yz, :alpha_zx, :alpha_zy]

      change before_action(&increment_version/1)
      change after_action(&broadcast_alpha_update/2)
    end

    update :optimize do
      accept [:performance_score]

      change before_action(&increment_version/1)
      change after_action(&trigger_cerebros_optimization/2)
    end

    read :active_rulesets do
      filter expr(status == :active)
    end

    read :by_version do
      argument :version, :integer, allow_nil?: false
      filter expr(version == ^arg(:version))
    end

    read :latest_version do
      prepare build(sort: [version: :desc], limit: 1)
    end
  end

  # ============================================================================
  # ATTRIBUTES
  # ============================================================================

  attributes do
    uuid_primary_key :id

    # Core Identity
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    # Lane Rules Configuration
    attribute :x_lane_rule, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:majority_hysteresis, :diffusion_threshold, :lifelike, :wavelet]]

    attribute :y_lane_rule, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:majority_hysteresis, :diffusion_threshold, :lifelike, :wavelet]]

    attribute :z_lane_rule, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:majority_hysteresis, :diffusion_threshold, :lifelike, :wavelet]]

    # Lane Rule Parameters
    attribute :x_lane_params, :map, public?: true, default: %{}
    attribute :y_lane_params, :map, public?: true, default: %{}
    attribute :z_lane_params, :map, public?: true, default: %{}

    # Cross-Lane Coupling (α-gains)
    attribute :alpha_xy, :float,
      allow_nil?: false,
      public?: true,
      default: 0.35,
      constraints: [min: 0.0, max: 1.0]

    attribute :alpha_xz, :float,
      allow_nil?: false,
      public?: true,
      default: 0.15,
      constraints: [min: 0.0, max: 1.0]

    attribute :alpha_yx, :float,
      allow_nil?: false,
      public?: true,
      default: 0.35,
      constraints: [min: 0.0, max: 1.0]

    attribute :alpha_yz, :float,
      allow_nil?: false,
      public?: true,
      default: 0.20,
      constraints: [min: 0.0, max: 1.0]

    attribute :alpha_zx, :float,
      allow_nil?: false,
      public?: true,
      default: 0.15,
      constraints: [min: 0.0, max: 1.0]

    attribute :alpha_zy, :float,
      allow_nil?: false,
      public?: true,
      default: 0.25,
      constraints: [min: 0.0, max: 1.0]

    # Scheduling Configuration
    attribute :schedule_type, :atom,
      allow_nil?: false,
      public?: true,
      default: :hybrid_event_wave,
      constraints: [one_of: [:sync_sweep, :async_event, :hybrid_event_wave]]

    attribute :schedule_params, :map, public?: true, default: %{}

    # Boundary Conditions
    attribute :boundaries, :map, public?: true, default: %{wrap: true}

    # Parameter Bounds (for optimization)
    attribute :parameter_bounds, :map, public?: true, default: %{}

    # Objective Function (for Cerebros optimization)
    attribute :objective_function, :map,
      public?: true,
      default: %{
        name: "pathflow_robustness",
        metrics: ["latency_ms_p95", "stability", "energy_per_update", "accuracy"],
        weights: [0.3, 0.2, 0.2, 0.3]
      }

    # Status and Deployment
    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      default: :draft,
      constraints: [one_of: [:draft, :active, :deprecated, :archived]]

    attribute :deployed_at, :utc_datetime_usec, public?: true
    attribute :performance_score, :float, public?: true

    # Security and Validation
    attribute :signature, :string, public?: true
    attribute :signature_algorithm, :string, public?: true, default: "ed25519"
    attribute :signed_by, :string, public?: true

    # Metadata
    attribute :metadata, :map, public?: true, default: %{}

    attribute :lane_configuration_id, :uuid do
      description "Lane configuration that uses this rule set"
      allow_nil? true
      public? true
    end

    # Timestamps
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  # ============================================================================
  # RELATIONSHIPS
  # ============================================================================

  relationships do
    has_many :lane_metrics, Thunderline.Thunderbolt.Resources.LaneMetrics do
      public? true
    end

    has_many :coupling_configs, Thunderline.Thunderbolt.Resources.CrossLaneCoupling do
      public? true
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp increment_version(changeset) do
    current_version = Ash.Changeset.get_attribute(changeset, :version) || 0
    Ash.Changeset.change_attribute(changeset, :version, current_version + 1)
  end

  defp generate_signature(changeset, ruleset) do
    # Generate cryptographic signature for ruleset integrity
    ruleset_data = serialize_for_signature(ruleset)
    signature = :crypto.sign(:eddsa, :ed25519, ruleset_data, get_signing_key())

    ruleset
    |> Ash.Changeset.for_update(:update, %{
      signature: Base.encode64(signature),
      signed_by: "thunderlane_control_plane"
    })
    |> Ash.update()
  end

  defp deploy_to_thundercells(_changeset, ruleset) do
    # Broadcast ruleset to all active ThunderCells
    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "system.ruleset.deployed",
             source: :bolt,
             type: :ruleset_deployed,
             payload: %{
               ruleset_id: ruleset.id,
               version: ruleset.version,
               ruleset: serialize_for_deployment(ruleset)
             },
             meta: %{pipeline: :realtime}
           ) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("[RuleSet] publish deployed failed: #{inspect(reason)}")
      end
    end

    # Send to ErlangBridge for distribution
    Thunderline.ErlangBridge.deploy_ruleset(ruleset)

    {:ok, ruleset}
  end

  defp broadcast_alpha_update(_changeset, ruleset) do
    # Real-time alpha gain updates
    alpha_deltas = %{
      alpha_xy: ruleset.alpha_xy,
      alpha_xz: ruleset.alpha_xz,
      alpha_yx: ruleset.alpha_yx,
      alpha_yz: ruleset.alpha_yz,
      alpha_zx: ruleset.alpha_zx,
      alpha_zy: ruleset.alpha_zy
    }

    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "system.ruleset.alpha_gains_updated",
             source: :bolt,
             type: :alpha_gains_updated,
             payload: %{
               ruleset_id: ruleset.id,
               version: ruleset.version,
               alpha_deltas: alpha_deltas
             },
             meta: %{pipeline: :realtime}
           ) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("[RuleSet] publish alpha_gains_updated failed: #{inspect(reason)}")
      end
    end

    {:ok, ruleset}
  end

  defp trigger_cerebros_optimization(_changeset, ruleset) do
    # Trigger Cerebros learning plane optimization when the optional Thunderlearn tuner is available
    maybe_optimize_with_thunderlearn(ruleset)

    {:ok, ruleset}
  end

  defp maybe_optimize_with_thunderlearn(ruleset) do
    if Code.ensure_loaded?(Thunderlearn.LocalTuner) and
         function_exported?(Thunderlearn.LocalTuner, :optimize_async, 1) do
      Thunderlearn.LocalTuner.optimize_async(ruleset)
    else
      Logger.debug("[RuleSet] Thunderlearn.LocalTuner unavailable, skipping optimization")
      :ok
    end
  end

  defp serialize_for_signature(ruleset) do
    # Create canonical representation for signing
    %{
      id: ruleset.id,
      version: ruleset.version,
      lanes: %{
        x: %{rule: ruleset.x_lane_rule, params: ruleset.x_lane_params},
        y: %{rule: ruleset.y_lane_rule, params: ruleset.y_lane_params},
        z: %{rule: ruleset.z_lane_rule, params: ruleset.z_lane_params}
      },
      coupling: %{
        alpha_xy: ruleset.alpha_xy,
        alpha_xz: ruleset.alpha_xz,
        alpha_yx: ruleset.alpha_yx,
        alpha_yz: ruleset.alpha_yz,
        alpha_zx: ruleset.alpha_zx,
        alpha_zy: ruleset.alpha_zy
      },
      schedule: ruleset.schedule_type,
      boundaries: ruleset.boundaries
    }
    |> Jason.encode!()
  end

  defp serialize_for_deployment(ruleset) do
    # Format for THUNDERCELL consumption
    %{
      id: ruleset.id,
      version: ruleset.version,
      lanes: %{
        x: %{rule: ruleset.x_lane_rule, params: ruleset.x_lane_params},
        y: %{rule: ruleset.y_lane_rule, params: ruleset.y_lane_params},
        z: %{rule: ruleset.z_lane_rule, params: ruleset.z_lane_params}
      },
      coupling: %{
        alpha_xy: ruleset.alpha_xy,
        alpha_xz: ruleset.alpha_xz,
        alpha_yx: ruleset.alpha_yx,
        alpha_yz: ruleset.alpha_yz,
        alpha_zx: ruleset.alpha_zx,
        alpha_zy: ruleset.alpha_zy
      },
      schedule: ruleset.schedule_type,
      schedule_params: ruleset.schedule_params,
      boundaries: ruleset.boundaries,
      signature: ruleset.signature
    }
  end

  defp get_signing_key do
    # TODO: Implement secure key management
    Application.get_env(:thunderline, :ruleset_signing_key) ||
      :crypto.strong_rand_bytes(32)
  end
end
