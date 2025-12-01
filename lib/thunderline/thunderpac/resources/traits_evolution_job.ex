defmodule Thunderline.Thunderpac.Resources.TraitsEvolutionJob do
  @moduledoc """
  Tracks PAC trait evolution jobs (HC-Ω-6).

  An evolution job represents a single TPE optimization run for a PAC,
  pulling recent reflex events and using Cerebros multivariate TPE
  to suggest updated trait vectors.

  ## Job Lifecycle

  ```
  :pending → :running → :completed | :failed | :cancelled
  ```

  ## Fields

  - `pac_id` - Target PAC for evolution
  - `tpe_params` - TPE configuration and hyperparameters
  - `fitness_window` - Time window for collecting metrics
  - `result` - Evolution result with new traits
  - `status` - Job status

  ## Integration Points

  - **Thunderbit.Reflex** - Sources reflex events for fitness evaluation
  - **Cerebros.TPEBridge** - Runs multivariate TPE optimization
  - **Thunderpac.Evolution** - Applies evolved traits to PAC
  - **Oban** - Schedules and executes evolution workers
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderpac.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban]

  require Logger

  postgres do
    table "thunderpac_traits_evolution_jobs"
    repo Thunderline.Repo

    references do
      reference :pac, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:status], name: "traits_evolution_jobs_status_idx"
      index [:pac_id], name: "traits_evolution_jobs_pac_idx"
      index [:scheduled_at], name: "traits_evolution_jobs_scheduled_idx"
      index [:completed_at], name: "traits_evolution_jobs_completed_idx"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # STATE MACHINE
  # ═══════════════════════════════════════════════════════════════

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:start, from: [:pending], to: :running)
      transition(:complete, from: [:running], to: :completed)
      transition(:fail, from: [:running], to: :failed)
      transition(:cancel, from: [:pending, :running], to: :cancelled)
      transition(:retry, from: [:failed], to: :pending)
    end
  end

  oban do
    triggers do
      trigger :process_evolution do
        action :start
        queue :pac_evolution
        scheduler_cron "*/10 * * * *"
        worker_module_name Thunderline.Thunderpac.Workers.EvolutionTriggerWorker
        scheduler_module_name Thunderline.Thunderpac.Schedulers.EvolutionScheduler

        where expr(status == :pending)
        on_error :fail
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :schedule, args: [:pac_id]
    define :start
    define :record_iteration, args: [:fitness, {:optional, :traits}]
    define :complete, args: [:result, {:optional, :metrics_summary}]
    define :fail, args: [:error]
    define :cancel, args: [{:optional, :reason}]
    define :retry
    define :set_initial_traits, args: [:traits]
    define :update_reflex_count, args: [:count]
    define :pending_jobs, action: :pending_jobs
    define :running_jobs, action: :running_jobs
    define :for_pac, args: [:pac_id]
    define :recent_completed, args: [{:optional, :since}]
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :schedule do
      description "Schedule a new evolution job for a PAC"

      accept [
        :pac_id,
        :tpe_params,
        :fitness_window_ms,
        :evolution_profile,
        :max_iterations,
        :convergence_threshold,
        :priority,
        :metadata
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :pending)
        |> Ash.Changeset.change_attribute(:scheduled_at, DateTime.utc_now())
      end

      change after_action(fn _changeset, job, _context ->
               emit_job_event(job, :scheduled)
               {:ok, job}
             end)
    end

    update :start do
      description "Start the evolution job"
      accept []
      require_atomic? false

      change transition_state(:running)

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
      end

      change after_action(fn _changeset, job, _context ->
               emit_job_event(job, :started)
               {:ok, job}
             end)
    end

    update :record_iteration do
      description "Record a TPE iteration result"
      accept []
      require_atomic? false

      argument :fitness, :float, allow_nil?: false
      argument :traits, {:array, :float}, allow_nil?: true

      change fn changeset, context ->
        fitness = context.arguments.fitness
        current_history = Ash.Changeset.get_attribute(changeset, :fitness_history) || []
        current_best = Ash.Changeset.get_attribute(changeset, :best_fitness)
        current_count = Ash.Changeset.get_attribute(changeset, :iteration_count) || 0

        changeset
        |> Ash.Changeset.change_attribute(:fitness_history, current_history ++ [fitness])
        |> Ash.Changeset.change_attribute(:iteration_count, current_count + 1)
        |> maybe_update_best_fitness(fitness, current_best)
      end
    end

    update :complete do
      description "Complete the evolution job with results"
      accept []
      require_atomic? false

      argument :result, :map, allow_nil?: false
      argument :metrics_summary, :map, allow_nil?: true

      change transition_state(:completed)

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
        |> Ash.Changeset.change_attribute(:result, context.arguments.result)
        |> Ash.Changeset.change_attribute(:metrics_summary, context.arguments[:metrics_summary])
      end

      change after_action(fn _changeset, job, _context ->
               emit_job_event(job, :completed, %{result: job.result})
               {:ok, job}
             end)
    end

    update :fail do
      description "Mark job as failed"
      accept []
      require_atomic? false

      argument :error, :string, allow_nil?: false

      change transition_state(:failed)

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
        |> Ash.Changeset.change_attribute(:error_message, context.arguments.error)
      end

      change after_action(fn _changeset, job, _context ->
               emit_job_event(job, :failed, %{error: job.error_message})
               {:ok, job}
             end)
    end

    update :cancel do
      description "Cancel a pending or running job"
      accept []
      require_atomic? false

      argument :reason, :string, allow_nil?: true

      change transition_state(:cancelled)

      change fn changeset, context ->
        reason = context.arguments[:reason] || "Manually cancelled"

        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_message, reason)
      end

      change after_action(fn _changeset, job, _context ->
               emit_job_event(job, :cancelled)
               {:ok, job}
             end)
    end

    update :retry do
      description "Retry a failed job"
      accept []
      require_atomic? false

      change transition_state(:pending)

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:started_at, nil)
        |> Ash.Changeset.change_attribute(:completed_at, nil)
        |> Ash.Changeset.change_attribute(:duration_ms, nil)
        |> Ash.Changeset.change_attribute(:error_message, nil)
        |> Ash.Changeset.change_attribute(:scheduled_at, DateTime.utc_now())
      end

      change after_action(fn _changeset, job, _context ->
               emit_job_event(job, :retried)
               {:ok, job}
             end)
    end

    update :set_initial_traits do
      description "Set initial traits from PAC at job start"
      accept []
      require_atomic? false

      argument :traits, {:array, :float}, allow_nil?: false

      change fn changeset, context ->
        Ash.Changeset.change_attribute(changeset, :initial_traits, context.arguments.traits)
      end
    end

    update :update_reflex_count do
      description "Update the count of processed reflex events"
      accept []
      require_atomic? false

      argument :count, :integer, allow_nil?: false

      change fn changeset, context ->
        Ash.Changeset.change_attribute(changeset, :reflex_events_count, context.arguments.count)
      end
    end

    read :pending_jobs do
      description "Get all pending evolution jobs"
      filter expr(status == :pending)
      prepare build(sort: [priority: :desc, scheduled_at: :asc])
    end

    read :running_jobs do
      description "Get all running evolution jobs"
      filter expr(status == :running)
    end

    read :for_pac do
      description "Get evolution jobs for a specific PAC"
      argument :pac_id, :uuid, allow_nil?: false
      filter expr(pac_id == ^arg(:pac_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :recent_completed do
      description "Get recently completed jobs"
      argument :since, :utc_datetime_usec, allow_nil?: true

      filter expr(status == :completed)

      prepare fn query, context ->
        since =
          context.arguments[:since] || DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

        Ash.Query.filter(query, expr(completed_at >= ^since))
      end

      prepare build(sort: [completed_at: :desc], limit: 100)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
    end

    attribute :tpe_params, :map do
      allow_nil? false
      default %{}
      public? true
      description "TPE configuration and hyperparameters"
    end

    attribute :fitness_window_ms, :integer do
      allow_nil? false

      # 5 minutes
      default 300_000
      public? true
      description "Time window for collecting reflex events (ms)"
    end

    attribute :evolution_profile, :atom do
      allow_nil? false
      default :balanced
      public? true
      constraints one_of: [:explorer, :exploiter, :balanced, :resilient, :aggressive]
      description "Evolution profile to use"
    end

    attribute :max_iterations, :integer do
      allow_nil? false
      default 50
      public? true
      description "Maximum TPE iterations"
    end

    attribute :convergence_threshold, :float do
      allow_nil? false
      default 0.01
      public? true
      description "Fitness improvement threshold for early stopping"
    end

    attribute :reflex_events_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Number of reflex events processed"
    end

    attribute :initial_traits, {:array, :float} do
      allow_nil? true
      public? true
      description "PAC traits at job start"
    end

    attribute :result, :map do
      allow_nil? true
      public? true
      description "Evolution result with new traits and metrics"
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
      description "Error message if job failed"
    end

    attribute :metrics_summary, :map do
      allow_nil? true
      public? true
      description "Summary of metrics used for fitness evaluation"
    end

    attribute :iteration_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Number of TPE iterations completed"
    end

    attribute :best_fitness, :float do
      allow_nil? true
      public? true
      description "Best fitness achieved"
    end

    attribute :fitness_history, {:array, :float} do
      allow_nil? false
      default []
      public? true
      description "Fitness values per iteration"
    end

    attribute :scheduled_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the job was scheduled"
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the job started running"
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the job completed"
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      public? true
      description "Total job duration in milliseconds"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 1
      public? true
      description "Job priority (higher = more urgent)"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
      description "Additional job metadata"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # RELATIONSHIPS
  # ═══════════════════════════════════════════════════════════════

  relationships do
    belongs_to :pac, Thunderline.Thunderpac.Resources.PAC do
      allow_nil? false
      public? true
      attribute_writable? true
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp maybe_update_best_fitness(changeset, fitness, nil) do
    Ash.Changeset.change_attribute(changeset, :best_fitness, fitness)
  end

  defp maybe_update_best_fitness(changeset, fitness, current_best) when fitness > current_best do
    Ash.Changeset.change_attribute(changeset, :best_fitness, fitness)
  end

  defp maybe_update_best_fitness(changeset, _fitness, _current_best), do: changeset

  defp emit_job_event(job, event_type, extra \\ %{}) do
    payload =
      Map.merge(
        %{
          job_id: job.id,
          pac_id: job.pac_id,
          status: job.status,
          profile: job.evolution_profile,
          timestamp: DateTime.utc_now()
        },
        extra
      )

    # Broadcast to PAC channel
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "pac:evolution:#{job.pac_id}",
      {:evolution_job, event_type, payload}
    )

    # Broadcast to global evolution channel
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "evolution:jobs",
      {:evolution_job, event_type, payload}
    )

    :telemetry.execute(
      [:thunderline, :pac, :evolution_job, event_type],
      %{count: 1},
      %{job_id: job.id, pac_id: job.pac_id, profile: job.evolution_profile}
    )

    :ok
  end
end
