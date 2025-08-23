defmodule Thunderline.Thunderflow.Resources.ProbeAttractorSummary do
  @moduledoc """
  Attractor dynamics summary for a completed probe run.

  Derived from the sequence of lap embeddings (delay embedding + heuristics)
  to characterize stability/chaos of model behavior. Created after a run
  completes (e.g., by a post-run worker or inline analyzer).
  """
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "probe_attractor_summaries"
    repo Thunderline.Repo
    custom_indexes do
      index [:corr_dim]
      index [:lyap]
    end
  end

  actions do
    defaults [:read, :create]

    update :recompute do
      accept [:m, :tau]
      argument :min_points, :integer, allow_nil?: true
  description "Recompute attractor summary (simple & Rosenstein) with optional new parameters. Updates canonical Lyapunov selection in-place."
      change fn changeset, _ ->
        # Custom change executed by service layer outside; placeholder to allow action invocation.
        {:ok, changeset}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :run_id, :uuid do
      allow_nil? false
    end

    attribute :points, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    attribute :delay_rows, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    attribute :m, :integer do
      allow_nil? false
      default 3
      constraints min: 1, max: 16
    end

    attribute :tau, :integer do
      allow_nil? false
      default 1
      constraints min: 1, max: 64
    end

    attribute :corr_dim, :float do
      allow_nil? false
      default 0.0
    end

    attribute :lyap, :float do
      allow_nil? false
      default 0.0
    end

    # Canonical chosen lyapunov exponent (simple vs Rosenstein). Updated by worker/service.
    attribute :lyap_canonical, :float do
      allow_nil? true
      description "Preferred Lyapunov exponent (Rosenstein if r2 >= threshold, else simple)"
    end

    # Rosenstein estimator auxiliary outputs
    attribute :lyap_r2, :float do
      allow_nil? true
    end

    attribute :lyap_window, :string do
      allow_nil? true
      description "Serialized window range start..end for Rosenstein fit"
    end

    attribute :reliable, :boolean do
      allow_nil? false
      default false
    end

    attribute :note, :string do
      allow_nil? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :run, Thunderline.Thunderflow.Resources.ProbeRun do
      attribute_type :uuid
      source_attribute :run_id
      allow_nil? false
    end
  end
end
