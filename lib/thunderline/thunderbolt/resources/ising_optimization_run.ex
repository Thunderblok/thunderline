defmodule Thunderline.Thunderbolt.Resources.IsingOptimizationRun do
  @moduledoc """
  Represents a specific optimization run/execution.

  Tracks the results, parameters, and performance of individual optimization attempts.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Thunderline.Thunderbolt.Domain

  postgres do
    table "ising_optimization_runs"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :problem_id, :uuid do
      description "ID of the optimization problem this run belongs to"
      allow_nil? false
    end

    attribute :name, :string do
      description "Name for this optimization run"
    end

    attribute :algorithm, :atom do
      description "Optimization algorithm used"
      constraints one_of: [:simulated_annealing, :parallel_tempering, :distributed, :metropolis_hastings]
      allow_nil? false
    end

    attribute :parameters, :map do
      description "Algorithm parameters (temperatures, schedules, etc.)"
      allow_nil? false
    end

    attribute :status, :atom do
      description "Current status of the optimization run"
      constraints one_of: [:queued, :running, :completed, :failed, :timeout]
      default :queued
    end

    attribute :result, :map do
      description "Optimization result (final energy, spins, convergence info)"
    end

    attribute :energy_history, {:array, :float} do
      description "Energy values throughout optimization"
      default []
    end

    attribute :magnetization_history, {:array, :float} do
      description "Magnetization values throughout optimization"
      default []
    end

    attribute :final_energy, :float do
      description "Final energy achieved"
    end

    attribute :final_magnetization, :float do
      description "Final magnetization"
    end

    attribute :steps_completed, :integer do
      description "Number of optimization steps completed"
      default 0
    end

    attribute :runtime_ms, :integer do
      description "Total runtime in milliseconds"
    end

    attribute :converged, :boolean do
      description "Whether optimization converged to stopping criterion"
      default false
    end

    attribute :error_message, :string do
      description "Error message if optimization failed"
    end

    attribute :metrics, :map do
      description "Additional performance and quality metrics"
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :started_at, :utc_datetime do
      description "When optimization actually started"
    end

    attribute :completed_at, :utc_datetime do
      description "When optimization completed"
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    update :start_run do
      description "Mark optimization run as started"

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :running)
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
      end
    end

    update :complete_run do
      description "Mark optimization run as completed with results"

      argument :result, :map, allow_nil?: false
      argument :energy_history, {:array, :float}, default: []
      argument :magnetization_history, {:array, :float}, default: []

      change fn changeset, _context ->
        result = Ash.Changeset.get_argument(changeset, :result)
        energy_history = Ash.Changeset.get_argument(changeset, :energy_history)
        magnetization_history = Ash.Changeset.get_argument(changeset, :magnetization_history)

        now = DateTime.utc_now()

        changeset
        |> Ash.Changeset.change_attribute(:status, :completed)
        |> Ash.Changeset.change_attribute(:completed_at, now)
        |> Ash.Changeset.change_attribute(:result, result)
        |> Ash.Changeset.change_attribute(:energy_history, energy_history)
        |> Ash.Changeset.change_attribute(:magnetization_history, magnetization_history)
        |> Ash.Changeset.change_attribute(:final_energy, Map.get(result, :energy))
        |> Ash.Changeset.change_attribute(:final_magnetization, Map.get(result, :magnetization))
        |> Ash.Changeset.change_attribute(:steps_completed, Map.get(result, :steps, 0))
        |> Ash.Changeset.change_attribute(:runtime_ms, Map.get(result, :runtime_ms))
        |> Ash.Changeset.change_attribute(:converged, Map.get(result, :converged, false))
      end
    end

    update :fail_run do
      description "Mark optimization run as failed"

      argument :error_message, :string, allow_nil?: false

      change fn changeset, _context ->
        error_message = Ash.Changeset.get_argument(changeset, :error_message)

        changeset
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_message, error_message)
      end
    end

    read :by_problem do
      description "Get runs for a specific problem"

      argument :problem_id, :uuid, allow_nil?: false

      filter expr(problem_id == ^arg(:problem_id))
    end

    read :recent_runs do
      description "Get recent optimization runs"

      argument :limit, :integer, default: 10

      prepare build(sort: [created_at: :desc])
      pagination offset?: true, countable: true
    end

    read :successful_runs do
      description "Get successfully completed runs"

      filter expr(status == :completed and converged == true)
      prepare build(sort: [final_energy: :asc])
    end
  end

  relationships do
    belongs_to :problem, Thunderline.Thunderbolt.Resources.IsingOptimizationProblem do
      source_attribute :problem_id
      destination_attribute :id
    end
  end

  aggregates do
    # TODO: Add aggregates after confirming proper syntax
    # average :avg_energy, :energy_history, :average
    min :min_energy, :energy_history
    max :max_energy, :energy_history
  end

  code_interface do
    calculations do
    # TODO: Re-enable when calculation syntax is clarified
    # define_for Thunderline.ThunderIsing.Domain
  end
    define :create
    define :start_run
    define :complete_run
    define :fail_run
    define :read
    define :update
    define :destroy
    define :by_problem
    define :recent_runs
    define :successful_runs
  end

  def compute_convergence_metrics(run) when is_struct(run) do
    if length(run.energy_history) > 10 do
      energies = run.energy_history
      n = length(energies)

      # Final 10% of energies
      final_portion = energies |> Enum.take(max(div(n, 10), 10))
      mean_final = Enum.sum(final_portion) / length(final_portion)

      # Compute variance in final portion
      variance = final_portion
      |> Enum.map(&((&1 - mean_final) ** 2))
      |> Enum.sum()
      |> Kernel./(length(final_portion))

      # Energy improvement rate
      initial_energy = List.last(energies)
      final_energy = List.first(energies)
      improvement = initial_energy - final_energy
      improvement_rate = improvement / n

      %{
        final_variance: variance,
        energy_improvement: improvement,
        improvement_rate: improvement_rate,
        stability_score: 1.0 / (1.0 + variance),
        convergence_quality: min(1.0, improvement / abs(initial_energy))
      }
    else
      %{
        final_variance: nil,
        energy_improvement: nil,
        improvement_rate: nil,
        stability_score: nil,
        convergence_quality: nil
      }
    end
  end
end
