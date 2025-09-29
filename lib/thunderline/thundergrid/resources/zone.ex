defmodule Thunderline.Thundergrid.Resources.Zone do
  @moduledoc """
  Zone Resource - Migrated from Thundervault

  Hexagonal zones in the Thunderline grid system for agent deployment.
  Now properly located in Thundergrid for spatial coordinate management.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "zones"
    repo Thunderline.Repo
  end

  import Ash.Resource.Change.Builtins

  graphql do
    type :zone
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :spawn_zone do
      accept [:q, :r, :aspect, :entropy, :energy_level, :max_agents, :properties]

      change set_attribute(:agent_count, 0)
      change set_attribute(:is_active, true)
    end

    update :add_agent do
      accept []
      require_atomic? false

      change increment(:agent_count)

      validate fn changeset, _context ->
        current_count = Ash.Changeset.get_attribute(changeset, :agent_count) || 0
        max_agents = Ash.Changeset.get_attribute(changeset, :max_agents) || 10

        if current_count >= max_agents do
          {:error, "Zone at maximum agent capacity"}
        else
          :ok
        end
      end
    end

    update :remove_agent do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        current_count = Ash.Changeset.get_attribute(changeset, :agent_count) || 0
        new_count = max(0, current_count - 1)
        Ash.Changeset.change_attribute(changeset, :agent_count, new_count)
      end
    end

    update :adjust_entropy do
      argument :delta, :decimal, allow_nil?: false
      require_atomic? false

      change fn changeset, context ->
        current_entropy = Ash.Changeset.get_attribute(changeset, :entropy) || Decimal.new("0.0")
        delta = context.arguments.delta
        new_entropy = Decimal.add(current_entropy, delta)

        clamped_entropy =
          Decimal.max(Decimal.new("0.0"), Decimal.min(new_entropy, Decimal.new("1.0")))

        Ash.Changeset.change_attribute(changeset, :entropy, clamped_entropy)
      end
    end

    update :deactivate do
      accept []
      require_atomic? false
      change set_attribute(:is_active, false)
    end

    update :activate do
      accept []
      require_atomic? false
      change set_attribute(:is_active, true)
    end

    read :by_coordinates do
      argument :q, :integer, allow_nil?: false
      argument :r, :integer, allow_nil?: false

      filter expr(q == ^arg(:q) and r == ^arg(:r))
      get? true
    end

    read :by_aspect do
      argument :aspect, :atom, allow_nil?: false
      filter expr(aspect == ^arg(:aspect))
    end

    read :active_zones do
      filter expr(is_active == true)
    end

    read :available_zones do
      filter expr(is_active == true and agent_count < max_agents)
      prepare build(sort: [agent_count: :asc, entropy: :asc])
    end

    read :high_entropy_zones do
      filter expr(entropy >= 0.7)
      prepare build(sort: [entropy: :desc])
    end

    read :in_radius do
      argument :center_q, :integer, allow_nil?: false
      argument :center_r, :integer, allow_nil?: false
      argument :radius, :integer, allow_nil?: false, default: 1

      # Hexagonal distance calculation: max(|q1-q2|, |r1-r2|, |q1+r1-q2-r2|)
      filter expr(
               max(
                 abs(q - ^arg(:center_q)),
                 abs(r - ^arg(:center_r)),
                 abs(q + r - (^arg(:center_q) + ^arg(:center_r)))
               ) <= ^arg(:radius)
             )
    end
  end

  validations do
    validate present([:q, :r, :aspect])
    validate numericality(:entropy, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    validate numericality(:energy_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    validate numericality(:agent_count, greater_than_or_equal_to: 0)
    validate numericality(:max_agents, greater_than: 0)

    # Ensure coordinates create valid hexagonal grid position
    validate fn changeset, _context ->
      q = Ash.Changeset.get_attribute(changeset, :q)
      r = Ash.Changeset.get_attribute(changeset, :r)

      if q && r do
        # In axial coordinates, q + r + s = 0 (where s = -q - r)
        # This is always true, but we validate reasonable bounds
        if abs(q) > 1000 or abs(r) > 1000 do
          {:error, "Zone coordinates must be within reasonable bounds (-1000 to 1000)"}
        else
          :ok
        end
      else
        :ok
      end
    end
  end

  attributes do
    uuid_primary_key :id

    # Axial coordinates for hexagonal grid
    attribute :q, :integer do
      allow_nil? false
      description "Q coordinate (horizontal)"
      public? true
    end

    attribute :r, :integer do
      allow_nil? false
      description "R coordinate (diagonal)"
      public? true
    end

    # Zone properties
    attribute :aspect, :atom do
      allow_nil? false
      default :neutral
      description "Zone classification type"
      public? true
    end

    attribute :entropy, :decimal do
      allow_nil? false
      default Decimal.new("0.0")
      constraints min: 0, max: 1
      description "Chaos level in zone (0.0 to 1.0)"
      public? true
    end

    attribute :energy_level, :decimal do
      allow_nil? false
      default Decimal.new("0.5")
      constraints min: 0, max: 1
      description "Available energy in zone"
      public? true
    end

    attribute :agent_count, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Number of agents currently in zone"
      public? true
    end

    attribute :max_agents, :integer do
      allow_nil? false
      default 10
      constraints min: 1
      description "Maximum agents allowed in zone"
      public? true
    end

    attribute :properties, :map do
      allow_nil? false
      default %{}
      description "Zone-specific properties and metadata"
      public? true
    end

    attribute :is_active, :boolean do
      allow_nil? false
      default true
      description "Whether zone is active for agent deployment"
      public? true
    end

    timestamps()
  end

  relationships do
    # TODO: Add zone_id field to CoreAgent before enabling this relationship
    # has_many :agents, Thunderline.Thunderbolt.Resources.CoreAgent do
    #   destination_attribute :zone_id
    #   description "Agents currently deployed in this zone"
    # end

    has_many :zone_events, Thunderline.Thundergrid.Resources.ZoneEvent do
      destination_attribute :zone_id
      description "Events that occurred in this zone"
    end
  end

  # TODO: Re-enable aggregates when agent relationships are properly established
  # aggregates do
  #   count :agent_count_agg, :agents
  #   avg :average_agent_success_rate, :agents, :success_rate do
  #     authorize? false
  #   end
  # end

  calculations do
    calculate :hex_distance_from_origin, :integer, expr(max(abs(q), abs(r), abs(q + r)))

    calculate :is_overcrowded, :boolean, expr(agent_count >= max_agents)

    calculate :capacity_ratio, :decimal, expr(agent_count / max_agents) do
      description "Agent capacity utilization ratio"
    end

    calculate :zone_stability, :decimal, expr(1.0 - entropy) do
      description "Zone stability (inverse of entropy)"
    end
  end

  # TODO: Re-enable policies once AshAuthentication is properly configured
  # policies do
  #   policy action_type(:read) do
  #     authorize_if always()
  #   end

  #   policy action_type([:create, :update]) do
  #     authorize_if actor_present()
  #   end

  #   policy action_type(:destroy) do
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end
  # end
end
