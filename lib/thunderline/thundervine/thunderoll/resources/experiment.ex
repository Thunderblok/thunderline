defmodule Thunderline.Thundervine.Thunderoll.Resources.Experiment do
  @moduledoc """
  Ash resource for Thunderoll experiments.

  An experiment represents a complete EGGROLL optimization run,
  tracking configuration, progress, and results.

  ## Lifecycle

  ```
  :pending → :running → :completed | :failed | :aborted
  ```

  ## Fields

  - `name` - Human-readable experiment name
  - `base_model_ref` - Reference to model/PAC being optimized
  - `rank` - Low-rank perturbation dimension
  - `population_size` - Number of population members
  - `sigma` - Perturbation standard deviation
  - `max_generations` - Maximum generations before stopping
  - `fitness_spec` - Fitness function configuration
  - `status` - Current experiment status
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  require Logger

  graphql do
    type :thunderoll_experiment
  end

  postgres do
    table "thunderoll_experiments"
    repo Thunderline.Repo

    custom_indexes do
      index [:status], name: "thunderoll_experiments_status_idx"
      index [:base_model_ref], name: "thunderoll_experiments_model_idx"
      index [:inserted_at], name: "thunderoll_experiments_created_idx"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :create_experiment, action: :start
    define :begin_running, action: :begin_running
    define :complete, action: :complete, args: [:final_fitness, {:optional, :total_evaluations}]
    define :fail, action: :fail, args: [{:optional, :error_message}]
    define :abort, action: :abort
    define :get_by_id, action: :read, get_by: [:id]
    define :list_running, action: :running
    define :list_pending, action: :pending
    define :list_recent, action: :recent
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :start do
      description "Create a new Thunderoll experiment"

      accept [
        :name,
        :base_model_ref,
        :rank,
        :population_size,
        :sigma,
        :max_generations,
        :fitness_spec,
        :convergence_criteria,
        :backend,
        :metadata
      ]

      change set_attribute(:status, :pending)
    end

    update :begin_running do
      description "Mark experiment as running"
      accept []
      require_atomic? false

      change set_attribute(:status, :running)

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
      end
    end

    update :complete do
      description "Mark experiment as completed"
      accept []
      require_atomic? false

      argument :final_fitness, :float, allow_nil?: false
      argument :total_evaluations, :integer, allow_nil?: true

      change set_attribute(:status, :completed)

      change fn changeset, context ->
        now = DateTime.utc_now()
        started_at = Ash.Changeset.get_attribute(changeset, :started_at)

        duration_ms =
          if started_at do
            DateTime.diff(now, started_at, :millisecond)
          else
            0
          end

        changeset
        |> Ash.Changeset.change_attribute(:completed_at, now)
        |> Ash.Changeset.change_attribute(:duration_ms, duration_ms)
        |> Ash.Changeset.change_attribute(:final_fitness, context.arguments.final_fitness)
        |> Ash.Changeset.change_attribute(
          :total_evaluations,
          context.arguments[:total_evaluations]
        )
      end
    end

    update :fail do
      description "Mark experiment as failed"
      accept []
      require_atomic? false

      argument :error_message, :string, allow_nil?: true

      change set_attribute(:status, :failed)

      change fn changeset, context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_message, context.arguments[:error_message])
      end
    end

    update :abort do
      description "Abort a running experiment"
      accept []
      require_atomic? false

      change set_attribute(:status, :aborted)

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end
    end

    read :running do
      description "Get all running experiments"
      filter expr(status == :running)
    end

    read :pending do
      description "Get all pending experiments"
      filter expr(status == :pending)
      prepare build(sort: [inserted_at: :asc])
    end

    read :recent do
      description "Get recently completed experiments"
      filter expr(status == :completed)
      prepare build(sort: [completed_at: :desc], limit: 20)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :base_model_ref, :string do
      allow_nil? true
      public? true
      description "Reference to the model/PAC being optimized"
    end

    attribute :rank, :integer do
      allow_nil? false
      default 1
      public? true
      description "Low-rank perturbation dimension"
    end

    attribute :population_size, :integer do
      allow_nil? false
      public? true
      description "Number of population members"
    end

    attribute :sigma, :float do
      allow_nil? false
      default 0.02
      public? true
      description "Perturbation standard deviation"
    end

    attribute :max_generations, :integer do
      allow_nil? false
      default 100
      public? true
      description "Maximum generations before stopping"
    end

    attribute :fitness_spec, :map do
      allow_nil? false
      default %{}
      public? true
      description "Fitness function configuration"
    end

    attribute :convergence_criteria, :map do
      allow_nil? false
      default %{}
      public? true
      description "Convergence detection criteria"
    end

    attribute :backend, :atom do
      allow_nil? false
      default :nx_native
      public? true
      constraints one_of: [:nx_native, :remote_jax]
      description "Compute backend to use"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :completed, :failed, :aborted]
    end

    attribute :current_generation, :integer do
      allow_nil? false
      default 0
      public? true
      description "Current generation index"
    end

    attribute :final_fitness, :float do
      allow_nil? true
      public? true
      description "Best fitness achieved"
    end

    attribute :total_evaluations, :integer do
      allow_nil? true
      public? true
      description "Total fitness evaluations performed"
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # RELATIONSHIPS
  # ═══════════════════════════════════════════════════════════════

  relationships do
    has_many :generations, Thunderline.Thundervine.Thunderoll.Resources.Generation do
      destination_attribute :experiment_id
    end
  end
end
