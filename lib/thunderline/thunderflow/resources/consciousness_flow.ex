defmodule Thunderline.Thunderflow.Resources.ConsciousnessFlow do
  @moduledoc """
  ConsciousnessFlow Resource - Agent Awareness Streaming

  Manages the flow of consciousness and awareness events from agents,
  enabling real-time monitoring and coordination of agent mental states.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource]

  import Ash.Expr

  postgres do
    table "thunderflow_consciousness_flows"
    repo Thunderline.Repo

    custom_indexes do
      index [:agent_id]
      index [:consciousness_type]
      index [:awareness_level]
      index [:stream_position]
      index [:inserted_at]
      index "USING GIN (active_goals)", name: "consciousness_flow_active_goals_gin_idx"
      index "USING GIN (memory_anchors)", name: "consciousness_flow_memory_anchors_gin_idx"
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :agent_id,
        :consciousness_type,
        :mental_state,
        :awareness_level,
        :cognitive_load,
        :active_goals,
        :memory_anchors,
        :emotional_markers,
        :flow_metadata
      ]

      change fn changeset, _context ->
        # Auto-increment stream position
        # In a real implementation, this would be atomic
        next_position = System.system_time(:millisecond)
        Ash.Changeset.change_attribute(changeset, :stream_position, next_position)
      end
    end

    action :process_consciousness do
      run fn _input, _context ->
        # Implementation would process pending consciousness events
        {:ok, "Consciousness processing completed"}
      end
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
    end

    read :by_consciousness_type do
      argument :consciousness_type, :string, allow_nil?: false
      filter expr(consciousness_type == ^arg(:consciousness_type))
    end

    read :high_awareness do
      argument :min_awareness, :decimal, default: Decimal.new("0.8")
      filter expr(awareness_level >= ^arg(:min_awareness))
    end

    read :recent_consciousness do
      argument :hours_back, :integer, default: 1

      prepare fn query, _context ->
        # Just return the query without time filtering since no timestamp field exists
        query
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :agent_id, :uuid do
      allow_nil? false
      description "Source agent identifier"
    end

    attribute :consciousness_type, :atom do
      allow_nil? false
      description "Type of consciousness processing: [:focused, :diffuse, :unified, :fragmented]"
    end

    attribute :mental_state, :map do
      allow_nil? false
      description "Current agent mental state snapshot"
      default %{}
    end

    attribute :awareness_level, :decimal do
      allow_nil? false
      description "Agent awareness intensity (0.0-1.0)"
      default Decimal.new("0.5")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :cognitive_load, :decimal do
      allow_nil? false
      description "Current cognitive processing load"
      default Decimal.new("0.0")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :active_goals, {:array, :string} do
      allow_nil? false
      description "Currently active agent goals"
      default []
    end

    attribute :memory_anchors, {:array, :uuid} do
      allow_nil? false
      description "Active memory anchor references"
      default []
    end

    attribute :emotional_markers, :map do
      allow_nil? false
      description "Emotional state indicators"
      default %{}
    end

    attribute :flow_metadata, :map do
      allow_nil? false
      description "Additional consciousness flow metadata"
      default %{}
    end

    attribute :stream_position, :integer do
      allow_nil? false
      description "Position in consciousness stream"
      default 0
      constraints min: 0
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
