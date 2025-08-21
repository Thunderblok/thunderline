defmodule Thunderline.Thunderflow.Resources.ProbeLap do
  @moduledoc "Single lap sample in a probe run (metrics + embedding)."
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "probe_laps"
    repo Thunderline.Repo
    custom_indexes do
      index [:run_id, :lap_index], unique: true
    end
  end

  actions do
    defaults [:read, :create]
  end

  attributes do
    uuid_primary_key :id

    attribute :run_id, :uuid do
      allow_nil? false
    end

    attribute :lap_index, :integer do
      allow_nil? false
      constraints min: 0
    end

    attribute :response_preview, :string do
      allow_nil? true
    end

    attribute :char_entropy, :float do
      allow_nil? false
      default 0.0
    end

    attribute :lexical_diversity, :float do
      allow_nil? false
      default 0.0
    end

    attribute :repetition_ratio, :float do
      allow_nil? false
      default 0.0
    end

    attribute :cosine_to_prev, :float do
      allow_nil? false
      default 0.0
    end

    attribute :elapsed_ms, :integer do
      allow_nil? false
      default 0
    end

    attribute :embedding, {:array, :float} do
      allow_nil? false
      default []
    end

    attribute :js_divergence_vs_baseline, :float do
      allow_nil? true
    end

    attribute :topk_overlap_vs_baseline, :float do
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
