defmodule Thunderline.Thunderflow.Resources.ProbeRun do
  @moduledoc """
  ProbeRun - represents a multi-lap provider probing session for drift / quality assessment.

  Runs are executed asynchronously via Oban (queue :probe) by the
  ProbeRunProcessor worker. Creating a run schedules the processor job.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban.Resource]

  postgres do
    table "probe_runs"
    repo Thunderline.Repo

    custom_indexes do
      index [:status]
      index [:provider]
      index [:model]
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :provider,
        :model,
        :prompt_path,
        :laps,
        :samples,
        :embedding_dim,
        :embedding_ngram,
        :condition,
        :attractor_m,
        :attractor_tau,
        :attractor_min_points
      ]

      change set_attribute(:status, :pending)

      change after_action(fn changeset, result, _ctx ->
               # Enqueue processor job unless running in test (sandbox ownership issues with async Oban)
               if Mix.env() != :test do
                 %{id: id} = result

                 %{run_id: id}
                 |> Thunderline.Thunderflow.Probing.Workers.ProbeRunProcessor.new()
                 |> Oban.insert()
               end

               {:ok, result, changeset}
             end)
    end

    update :update_status do
      accept [:status, :started_at, :completed_at, :error_message, :intrinsic_reward]
    end

    update :fail do
      change set_attribute(:status, :error)
      accept [:error_message]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :string do
      allow_nil? false
    end

    attribute :model, :string do
      allow_nil? true
    end

    attribute :prompt_path, :string do
      allow_nil? false
      description "File path to prompt text used for this run"
    end

    attribute :laps, :integer do
      allow_nil? false
      default 5
      constraints min: 1, max: 10_000
    end

    attribute :samples, :integer do
      allow_nil? false
      default 1
      constraints min: 1, max: 100
    end

    attribute :embedding_dim, :integer do
      allow_nil? false
      default 512
      constraints min: 64, max: 4096
    end

    attribute :embedding_ngram, :integer do
      allow_nil? false
      default 3
      constraints min: 1, max: 8
    end

    attribute :condition, :string do
      allow_nil? true
    end

    # Optional attractor override parameters for summary worker.
    attribute :attractor_m, :integer do
      allow_nil? true
      constraints min: 1, max: 16
    end

    attribute :attractor_tau, :integer do
      allow_nil? true
      constraints min: 1, max: 128
    end

    attribute :attractor_min_points, :integer do
      allow_nil? true
      constraints min: 5, max: 100_000
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :running, :completed, :error]
    end

    attribute :error_message, :string do
      allow_nil? true
    end

    attribute :started_at, :utc_datetime do
      allow_nil? true
    end

    attribute :completed_at, :utc_datetime do
      allow_nil? true
    end

    attribute :intrinsic_reward, :decimal do
      allow_nil? true
      description "IGPO intrinsic reward score (0.0-1.0) measuring information gain/novelty across laps"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    # Relationship renamed to avoid collision with numeric :laps attribute
    has_many :lap_samples, Thunderline.Thunderflow.Resources.ProbeLap do
      destination_attribute :run_id
    end

    has_one :attractor_summary, Thunderline.Thunderflow.Resources.ProbeAttractorSummary do
      destination_attribute :run_id
    end
  end
end
