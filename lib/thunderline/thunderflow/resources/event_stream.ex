defmodule Thunderline.Thunderflow.Resources.EventStream do
  @moduledoc """
  EventStream Resource - High-Performance Streaming Infrastructure

  Core streaming resource that manages event streams with real-time processing,
  backpressure handling, and cross-domain integration.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource]

  postgres do
    table "thunderflow_event_streams"
    repo Thunderline.Repo

    custom_indexes do
      index [:stream_name], unique: true
      index [:stream_type]
      index [:source_domain]
      index [:status]
      index [:last_event_at]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :stream_name,
        :stream_type,
        :source_domain,
        :partition_count,
        :retention_hours,
        :throughput_config
      ]
    end

    update :update do
      accept [:stream_name, :throughput_config, :retention_hours]
    end

    update :pause do
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :paused)
      end
    end

    update :resume do
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :active)
      end
    end

    update :increment_event_count do
      require_atomic? false

      change fn changeset, _context ->
        current_count = Ash.Changeset.get_attribute(changeset, :event_count) || 0

        changeset
        |> Ash.Changeset.change_attribute(:event_count, current_count + 1)
        |> Ash.Changeset.change_attribute(:last_event_at, DateTime.utc_now())
      end
    end

    update :update_performance do
      accept [:performance_metrics]
    end

    action :replay_from_checkpoint do
      argument :checkpoint_id, :uuid, allow_nil?: false

      run fn input, context ->
        # Implementation would replay events from checkpoint
        {:ok, input.id}
      end
    end

    read :active_streams do
      filter expr(status == :active)
    end

    read :by_domain do
      argument :domain, :string, allow_nil?: false
      filter expr(source_domain == ^arg(:domain))
    end

    read :by_type do
      argument :stream_type, :string, allow_nil?: false
      filter expr(stream_type == ^arg(:stream_type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :stream_name, :string do
      allow_nil? false
      description "Unique stream identifier"
      constraints max_length: 100
    end

    attribute :stream_type, :atom do
      allow_nil? false
      description "Type of event stream"
      constraints one_of: [:consciousness, :system, :federation, :analytics, :audit]
    end

    attribute :source_domain, :atom do
      allow_nil? false
      description "Originating Thunderline domain"

      constraints one_of: [
                    :thundercore,
                    :thunderblock_vault,
                    :thundercom,
                    :thunderbit,
                    :thunderflow,
                    # thunderchief consolidated into thundercrown (HC-49)
                    :thundercrown,
                    :thunderblock,
                    :thunderbolt,
                    :thundergate,
                    :thundereye,
                    :thunderline_web
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current stream status"
      default :active
      constraints one_of: [:active, :paused, :stopped, :error, :draining]
    end

    attribute :partition_count, :integer do
      allow_nil? false
      description "Number of stream partitions"
      default 1
      constraints min: 1, max: 64
    end

    attribute :retention_hours, :integer do
      allow_nil? false
      description "Event retention period in hours"

      # 7 days
      default 168
      constraints min: 1
    end

    attribute :throughput_config, :map do
      allow_nil? false
      description "Throughput and backpressure configuration"

      default %{
        "max_events_per_second" => 1000,
        "batch_size" => 100,
        "backpressure_threshold" => 0.8
      }
    end

    attribute :event_count, :integer do
      allow_nil? false
      description "Total events processed"
      default 0
      constraints min: 0
    end

    attribute :last_event_at, :utc_datetime do
      allow_nil? true
      description "Timestamp of last event"
    end

    attribute :performance_metrics, :map do
      allow_nil? false
      description "Stream performance metrics"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
