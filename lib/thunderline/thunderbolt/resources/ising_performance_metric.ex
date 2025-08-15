defmodule Thunderline.Thunderbolt.Resources.IsingPerformanceMetric do
  @moduledoc """
  Tracks performance benchmarks and system capabilities.

  Used for sizing problems, predicting runtimes, and monitoring performance regressions.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Thunderline.Thunderbolt.Domain

  postgres do
    table "ising_performance_metrics"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :benchmark_name, :string do
      description "Name/type of benchmark"
      allow_nil? false
    end

    attribute :system_info, :map do
      description "System information (CPU, memory, EXLA backend, etc.)"
      allow_nil? false
    end

    attribute :problem_size, :map do
      description "Problem dimensions (grid size, number of vertices, etc.)"
      allow_nil? false
    end

    attribute :algorithm_config, :map do
      description "Algorithm configuration used"
      allow_nil? false
    end

    attribute :spins_per_second, :float do
      description "Spin updates per second achieved"
    end

    attribute :energy_evaluations_per_second, :float do
      description "Energy evaluations per second"
    end

    attribute :memory_usage_mb, :float do
      description "Peak memory usage in MB"
    end

    attribute :compilation_time_ms, :integer do
      description "EXLA kernel compilation time"
    end

    attribute :execution_time_ms, :integer do
      description "Pure execution time (excluding compilation)"
    end

    attribute :total_time_ms, :integer do
      description "Total benchmark time"
    end

    attribute :backend_info, :map do
      description "Backend acceleration information"
      default %{}
    end

    attribute :scaling_factor, :float do
      description "Performance scaling factor vs baseline"
    end

    attribute :quality_metrics, :map do
      description "Solution quality metrics (final energy, convergence, etc.)"
      default %{}
    end

    create_timestamp :created_at

    attribute :environment_tags, {:array, :string} do
      description "Environment tags (dev, prod, gpu, cpu, etc.)"
      default []
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :record_benchmark do
      description "Record a new benchmark result"

      argument :benchmark_result, :map, allow_nil?: false

      change fn changeset, _context ->
        result = Ash.Changeset.get_argument(changeset, :benchmark_result)

        changeset
        |> Ash.Changeset.change_attribute(:benchmark_name, Map.get(result, :benchmark_name, "unknown"))
        |> Ash.Changeset.change_attribute(:system_info, Map.get(result, :system_info, %{}))
        |> Ash.Changeset.change_attribute(:problem_size, Map.get(result, :problem_size, %{}))
        |> Ash.Changeset.change_attribute(:algorithm_config, Map.get(result, :algorithm_config, %{}))
        |> Ash.Changeset.change_attribute(:spins_per_second, Map.get(result, :spins_per_second))
        |> Ash.Changeset.change_attribute(:energy_evaluations_per_second, Map.get(result, :energy_evaluations_per_second))
        |> Ash.Changeset.change_attribute(:memory_usage_mb, Map.get(result, :memory_usage_mb))
        |> Ash.Changeset.change_attribute(:compilation_time_ms, Map.get(result, :compilation_time_ms))
        |> Ash.Changeset.change_attribute(:execution_time_ms, Map.get(result, :execution_time_ms))
        |> Ash.Changeset.change_attribute(:total_time_ms, Map.get(result, :total_time_ms))
        |> Ash.Changeset.change_attribute(:backend_info, Map.get(result, :backend_info, %{}))
        |> Ash.Changeset.change_attribute(:quality_metrics, Map.get(result, :quality_metrics, %{}))
        |> Ash.Changeset.change_attribute(:environment_tags, Map.get(result, :environment_tags, []))
      end
    end

    read :by_benchmark_name do
      description "Get metrics for a specific benchmark"

      argument :benchmark_name, :string, allow_nil?: false

      filter expr(benchmark_name == ^arg(:benchmark_name))
      prepare build(sort: [created_at: :desc])
    end

    read :list do
      primary? true
      prepare build(sort: [created_at: :desc])
    end

    read :performance_trends do
      description "Get performance trends over time"

      argument :benchmark_name, :string
      argument :days_back, :integer, default: 30

      filter expr(
        if not is_nil(^arg(:benchmark_name)) do
          benchmark_name == ^arg(:benchmark_name)
        else
          true
        end and
        created_at >= ago(^arg(:days_back), :day)
      )

      prepare build(sort: [created_at: :asc])
    end
  end

  aggregates do
    # TODO: Add aggregates after confirming proper syntax
    # average :avg_spins_per_second, :spins_per_second, :average
    max :max_spins_per_second, :spins_per_second
    min :min_spins_per_second, :spins_per_second

    # TODO: Add aggregates after confirming proper syntax
    # avg :avg_memory_usage, :memory_usage_mb
    # avg :avg_execution_time, :execution_time_ms
  end

  calculations do
    calculate :performance_score, :float, expr(
      spins_per_second / (memory_usage_mb + 1.0) *
      1000.0 / (execution_time_ms + 1.0)
    ) do
      description "Composite performance score"
    end

    calculate :efficiency_rating, :string, expr(
      cond do
        spins_per_second > 1_000_000 -> "excellent"
        spins_per_second > 500_000 -> "good"
        spins_per_second > 100_000 -> "fair"
        true -> "poor"
      end
    ) do
      description "Human-readable efficiency rating"
    end
  end

  code_interface do
    define :create
    define :record_benchmark
    define :read
    define :by_benchmark_name
    define :performance_trends
  end

  def analyze_performance_regression(metrics) when is_list(metrics) do
    if length(metrics) < 2 do
      %{regression_detected: false, reason: "insufficient_data"}
    else
      # Sort by creation time
      sorted_metrics = Enum.sort_by(metrics, & &1.created_at, DateTime)

      # Compare recent vs baseline performance
      recent_count = max(div(length(sorted_metrics), 4), 2)
      recent_metrics = Enum.take(sorted_metrics, -recent_count)
      baseline_metrics = Enum.take(sorted_metrics, recent_count)

      recent_avg = recent_metrics |> Enum.map(& &1.spins_per_second) |> Enum.sum() |> Kernel./(length(recent_metrics))
      baseline_avg = baseline_metrics |> Enum.map(& &1.spins_per_second) |> Enum.sum() |> Kernel./(length(baseline_metrics))

      regression_threshold = 0.1  # 10% degradation
      performance_ratio = recent_avg / baseline_avg

      if performance_ratio < (1 - regression_threshold) do
        %{
          regression_detected: true,
          performance_degradation: (1 - performance_ratio) * 100,
          recent_avg_performance: recent_avg,
          baseline_avg_performance: baseline_avg,
          recommendation: "investigate_recent_changes"
        }
      else
        %{
          regression_detected: false,
          performance_ratio: performance_ratio,
          trend: if(performance_ratio > 1.05, do: "improving", else: "stable")
        }
      end
    end
  end
end
