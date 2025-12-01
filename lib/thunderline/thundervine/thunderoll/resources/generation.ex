defmodule Thunderline.Thundervine.Thunderoll.Resources.Generation do
  @moduledoc """
  Ash resource for Thunderoll experiment generations.

  A generation represents one iteration of the EGGROLL optimization loop,
  recording fitness statistics and the parameter delta produced.

  ## Fields

  - `index` - Generation number (0-indexed)
  - `fitness_stats` - Fitness statistics (min, max, mean, std)
  - `best_fitness` - Best fitness in this generation
  - `population_summary` - Aggregated population metrics
  - `update_delta_ref` - Reference to stored parameter delta
  - `duration_ms` - Time to complete generation
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "thunderoll_generations"
    repo Thunderline.Repo

    references do
      reference :experiment, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:experiment_id, :index], name: "thunderoll_generations_exp_idx_unique", unique: true
      index [:experiment_id], name: "thunderoll_generations_experiment_idx"
    end
  end

  graphql do
    type :thunderoll_generation
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :record, action: :record
    define :for_experiment, action: :for_experiment, args: [:experiment_id]
    define :latest_for_experiment, action: :latest, args: [:experiment_id]
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :record do
      description "Record a generation's results"

      accept [
        :experiment_id,
        :index,
        :fitness_stats,
        :best_fitness,
        :population_summary,
        :update_delta_ref,
        :duration_ms
      ]

      change set_attribute(:status, :completed)
    end

    read :for_experiment do
      description "Get all generations for an experiment"

      argument :experiment_id, :uuid, allow_nil?: false

      filter expr(experiment_id == ^arg(:experiment_id))
      prepare build(sort: [index: :asc])
    end

    read :latest do
      description "Get the latest generation for an experiment"

      argument :experiment_id, :uuid, allow_nil?: false

      filter expr(experiment_id == ^arg(:experiment_id))
      prepare build(sort: [index: :desc], limit: 1)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :index, :integer do
      allow_nil? false
      public? true
      description "Generation number (0-indexed)"
    end

    attribute :fitness_stats, :map do
      allow_nil? true
      public? true
      description "Fitness statistics {min, max, mean, std, median}"
    end

    attribute :best_fitness, :float do
      allow_nil? true
      public? true
      description "Best fitness achieved in this generation"
    end

    attribute :population_summary, :map do
      allow_nil? true
      public? true
      description "Aggregated population metrics"
    end

    attribute :update_delta_ref, :string do
      allow_nil? true
      public? true
      description "Reference to stored parameter delta (file/S3/etc)"
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      public? true
      description "Generation execution time in milliseconds"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :completed, :failed]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # RELATIONSHIPS
  # ═══════════════════════════════════════════════════════════════

  relationships do
    belongs_to :experiment, Thunderline.Thundervine.Thunderoll.Resources.Experiment do
      allow_nil? false
      public? true
      attribute_writable? true
    end
  end
end
