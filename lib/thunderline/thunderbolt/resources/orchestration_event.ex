defmodule Thunderline.Thunderbolt.Resources.OrchestrationEvent do
  @moduledoc """
  OrchestrationEvent Resource - Event logging for mesh operations

  Records all significant orchestration events, decisions, and actions taken
  by the Thunderbolt system. Provides audit trail, debugging information,
  and performance analytics for 144-bit mesh management.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]
  import Ash.Resource.Change.Builtins
  import Ash.Resource.Change.Builtins


  json_api do
    type "orchestration_event"

    routes do
      base "/orchestration-events"
      get :read
      index :read
      post :create
      get :timeline, route: "/timeline"
      get :audit_trail, route: "/audit/:chunk_id"
    end
  end

  attributes do
    uuid_primary_key :id

    # Event identification
    attribute :event_type, :atom, constraints: [
      one_of: [
        :chunk_created, :chunk_destroyed, :chunk_activated, :chunk_optimized,
        :activation_rule_triggered, :activation_rule_trained, :resource_allocated,
        :resource_rebalanced, :resource_scaled, :health_check_performed,
        :health_degraded, :health_recovered, :remediation_triggered,
        :ml_prediction_made, :optimization_completed, :error_occurred,
        :system_event, :user_action, :external_trigger
      ]
    ], allow_nil?: false

    attribute :event_category, :atom, constraints: [
      one_of: [:lifecycle, :performance, :health, :scaling, :ml_ai, :error, :audit]
    ], default: :lifecycle

    attribute :severity, :atom, constraints: [
      one_of: [:debug, :info, :warning, :error, :critical]
    ], default: :info

    # Event content
    attribute :title, :string, allow_nil?: false
    attribute :description, :string
    attribute :event_data, :map, default: %{}
    attribute :context_data, :map, default: %{}

    # Performance and metrics
    attribute :duration_ms, :integer
    attribute :resource_impact, :map, default: %{}
    attribute :performance_metrics, :map, default: %{}

    # Tracing and correlation
    attribute :correlation_id, :string
    attribute :trace_id, :string
    attribute :parent_event_id, :uuid
    attribute :session_id, :string

    # System context
    attribute :cluster_node, :string, default: "localhost"
    attribute :system_version, :string
    attribute :triggered_by, :string  # user_id, system, external_api, etc.

    # Result and outcome
    attribute :status, :atom, constraints: [
      one_of: [:pending, :in_progress, :completed, :failed, :cancelled]
    ], default: :completed

    attribute :result_data, :map, default: %{}
    attribute :error_details, :map, default: %{}

    # Foreign keys for relationships
    attribute :chunk_id, :uuid
    attribute :activation_rule_id, :uuid
    attribute :resource_allocation_id, :uuid

    timestamps()
  end

  relationships do
  belongs_to :chunk, Thunderline.Thunderbolt.Resources.Chunk do
      attribute_writable? true
    end

  belongs_to :activation_rule, Thunderline.Thunderbolt.Resources.ActivationRule do
      attribute_writable? true
    end

  belongs_to :resource_allocation, Thunderline.Thunderbolt.Resources.ResourceAllocation do
      attribute_writable? true
    end

    # Self-referential for event hierarchies
    belongs_to :parent_event, __MODULE__ do
      source_attribute :parent_event_id
      destination_attribute :id
    end

    has_many :child_events, __MODULE__ do
      source_attribute :id
      destination_attribute :parent_event_id
    end
  end

  calculations do
    calculate :event_age_hours, :decimal, expr(
      datetime_diff(now(), inserted_at, :hour)
    )

    calculate :is_error_event, :boolean, expr(
      severity in [:error, :critical] or status == :failed
    )

    calculate :has_performance_impact, :boolean, expr(
      not is_nil(duration_ms) and duration_ms > 1000
    )

    calculate :event_summary, :string, expr(
      "#{event_type}: #{title} (#{status})"
    )
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :log_event do
      accept [
        :event_type, :event_category, :severity, :title, :description,
        :event_data, :context_data, :duration_ms, :resource_impact,
        :performance_metrics, :correlation_id, :trace_id, :triggered_by,
        :status, :result_data
      ]

      change before_action(&generate_trace_ids/1)
      change after_action(&broadcast_event/2)
    end

    create :log_chunk_event do
      accept [
        :event_type, :event_category, :severity, :title, :description,
        :event_data, :context_data, :chunk_id
      ]

      change before_action(&enrich_chunk_context/1)
      change after_action(&update_chunk_event_history/2)
    end

    create :log_error_event do
      accept [
        :title, :description, :event_data, :error_details, :chunk_id,
        :correlation_id, :trace_id
      ]

      change set_attribute(:event_type, :error_occurred)
      change set_attribute(:event_category, :error)
      change set_attribute(:severity, :error)
      change set_attribute(:status, :failed)
      change after_action(&trigger_error_alerts/2)
    end

    update :complete_event do
      accept [:status, :result_data, :duration_ms, :performance_metrics]
      change before_action(&calculate_event_duration/1)
      change after_action(&broadcast_completion/2)
    end

    read :timeline do
      argument :hours_back, :integer, default: 24
      argument :chunk_id, :uuid

      # TODO: Fix prepare build syntax for Ash 3.x
      # prepare build(fn query, context ->
      #   query = Ash.Query.sort(query, inserted_at: :desc)

      #   query = if context.arguments[:chunk_id] do
      #     chunk_id_value = context.arguments[:chunk_id]
      #     Ash.Query.filter(query, expr(chunk_id == ^chunk_id_value))
      #   else
      #     query
      #   end

      #   hours_back = context.arguments[:hours_back]
      #   Ash.Query.filter(query, expr(inserted_at > ago(^hours_back, :hour)))
      # end)
    end

    read :audit_trail do
      argument :chunk_id, :uuid, allow_nil?: false

      filter expr(chunk_id == ^arg(:chunk_id))
      # TODO: Fix prepare build syntax for Ash 3.x
      # prepare build(fn query, _context ->
      #   Ash.Query.sort(query, inserted_at: :desc)
      #   |> Ash.Query.load([:parent_event, :child_events])
      # end)
    end

    read :error_events do
      filter expr(is_error_event == true)
    end

    read :performance_events do
      filter expr(has_performance_impact == true)
    end

    read :recent_events do
      argument :minutes_back, :integer, default: 60

      filter expr(inserted_at > ago(^arg(:minutes_back), :minute))
    end

    read :events_by_type do
      argument :event_type, :atom, allow_nil?: false
      filter expr(event_type == ^arg(:event_type))
    end

    read :events_by_correlation do
      argument :correlation_id, :string, allow_nil?: false
      filter expr(correlation_id == ^arg(:correlation_id))
    end
  end

  # TODO: Configure pub_sub when proper extension is available
  # pub_sub do
  #   publish :event_logged, ["thunderbolt:events:logged", :event_type]
  #   publish :error_event_logged, ["thunderbolt:events:error", :chunk_id]
  #   publish :critical_event_logged, ["thunderbolt:events:critical", :chunk_id]
  # end

  # IN-MEMORY CONFIGURATION (sqlite removed)
  # Using :embedded data layer for in-memory events

  # Private action implementations
  defp generate_trace_ids(changeset) do
    # Generate correlation and trace IDs if not provided
    correlation_id = Ash.Changeset.get_attribute(changeset, :correlation_id) ||
                    Ecto.UUID.generate()
    trace_id = Ash.Changeset.get_attribute(changeset, :trace_id) ||
               Ecto.UUID.generate()

    changeset
    |> Ash.Changeset.change_attribute(:correlation_id, correlation_id)
    |> Ash.Changeset.change_attribute(:trace_id, trace_id)
  end

  defp broadcast_event(_changeset, event) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:events",
      {:event_logged, event}
    )

    # Broadcast critical events to special channels
    if event.severity == :critical do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "thunderbolt:alerts:critical",
        {:critical_event, event}
      )
    end

    {:ok, event}
  end

  defp enrich_chunk_context(changeset) do
    # TODO: Add chunk-specific context data
    # Could include chunk status, health metrics, resource allocation, etc.
    changeset
  end

  defp update_chunk_event_history(_changeset, event) do
    # TODO: Update chunk's event history statistics
    {:ok, event}
  end

  defp trigger_error_alerts(_changeset, event) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:alerts:error",
      {:error_event, event}
    )
    {:ok, event}
  end

  defp calculate_event_duration(changeset) do
    # If duration not provided, calculate from inserted_at to now
    duration = Ash.Changeset.get_attribute(changeset, :duration_ms)

    if is_nil(duration) do
      # TODO: Calculate actual duration if we tracked start time
      # For now, use a placeholder
      Ash.Changeset.change_attribute(changeset, :duration_ms, 0)
    else
      changeset
    end
  end

  defp broadcast_completion(_changeset, event) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:events:completed",
      {:event_completed, event}
    )
    {:ok, event}
  end
end
