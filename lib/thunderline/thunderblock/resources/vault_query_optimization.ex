defmodule Thunderline.Thunderblock.Resources.VaultQueryOptimization do
  @moduledoc """
  QueryOptimization Resource - Database Performance Analytics

  Tracks query performance, identifies bottlenecks, and provides optimization
  recommendations for the ThunderBlock Vault persistence layer (legacy Thundervault lineage).
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  import Ash.Expr

  postgres do
    table "thunderblock_query_optimizations"
    repo Thunderline.Repo

    custom_indexes do
      index [:query_hash], unique: true, name: "query_optimizations_hash_idx"
      index [:avg_execution_time], name: "query_optimizations_avg_time_idx"
      index [:frequency], name: "query_optimizations_frequency_idx"
      index "USING GIN (optimization_suggestions)", name: "query_optimizations_suggestions_idx"
    end
  end

  code_interface do
    define :analyze_query
    define :update_stats, args: [:execution_time_ms]
    # TODO: Add performance_stats action before uncommenting
    # define :performance_stats, action: :performance_stats
    define :slow_queries
    define :frequent_queries
  end

  actions do
    defaults [:read]

    create :analyze_query do
      description "Analyze query performance"

      accept [
        :query_hash,
        :query_sql,
        :execution_time_ms,
        :rows_examined,
        :rows_returned,
        :index_usage,
        :execution_plan,
        :optimization_suggestions
      ]

      change fn changeset, _context ->
        execution_time = Ash.Changeset.get_attribute(changeset, :execution_time_ms)

        changeset
        |> Ash.Changeset.change_attribute(:avg_execution_time, execution_time)
      end

      upsert? true
      upsert_identity :unique_query_hash
      upsert_fields [:frequency, :avg_execution_time, :execution_time_ms, :updated_at]
    end

    update :update_stats do
      description "Update query execution statistics"
      accept [:frequency, :avg_execution_time, :execution_time_ms]
      require_atomic? false

      change fn changeset, _context ->
        current_freq = Ash.Changeset.get_attribute(changeset, :frequency) || 1
        current_avg = Ash.Changeset.get_attribute(changeset, :avg_execution_time)
        new_execution_time = Ash.Changeset.get_attribute(changeset, :execution_time_ms)

        new_freq = current_freq + 1

        new_avg =
          if current_avg && new_execution_time do
            total_time = Decimal.mult(current_avg, Decimal.new(current_freq))
            new_total = Decimal.add(total_time, new_execution_time)
            Decimal.div(new_total, Decimal.new(new_freq))
          else
            new_execution_time || current_avg
          end

        changeset
        |> Ash.Changeset.change_attribute(:frequency, new_freq)
        |> Ash.Changeset.change_attribute(:avg_execution_time, new_avg)
      end
    end

    read :performance_analysis do
      description "Analyze query performance patterns with sorting"
    end

    read :slow_queries do
      description "Identify slow queries for optimization"
    end

    read :frequent_queries do
      description "List frequently executed queries"
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :query_hash, :string do
      allow_nil? false
      description "Hash of the query for deduplication"
      constraints min_length: 64, max_length: 64
    end

    attribute :query_sql, :string do
      allow_nil? false
      description "SQL query text"
      constraints max_length: 10000
    end

    attribute :execution_time_ms, :decimal do
      allow_nil? false
      description "Query execution time in milliseconds"
      constraints min: Decimal.new("0.0")
    end

    attribute :rows_examined, :integer do
      allow_nil? true
      description "Number of rows examined"
      constraints min: 0
    end

    attribute :rows_returned, :integer do
      allow_nil? true
      description "Number of rows returned"
      constraints min: 0
    end

    attribute :index_usage, :map do
      allow_nil? false
      description "Index usage statistics"
      default %{}
    end

    attribute :execution_plan, :map do
      allow_nil? false
      description "Query execution plan"
      default %{}
    end

    attribute :optimization_suggestions, {:array, :string} do
      allow_nil? false
      description "Optimization recommendations"
      default []
    end

    attribute :frequency, :integer do
      allow_nil? false
      description "Number of times this query was executed"
      default 1
      constraints min: 1
    end

    attribute :avg_execution_time, :decimal do
      allow_nil? false
      description "Average execution time"
      constraints min: Decimal.new("0.0")
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_query_hash, [:query_hash]
  end
end
