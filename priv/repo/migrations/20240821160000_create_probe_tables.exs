defmodule Thunderline.Repo.Migrations.CreateProbeTables do
  use Ecto.Migration

  def change do
    create table(:probe_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :model, :string
      add :prompt_path, :string, null: false
      add :laps, :integer, null: false, default: 5
      add :samples, :integer, null: false, default: 1
      add :embedding_dim, :integer, null: false, default: 512
      add :embedding_ngram, :integer, null: false, default: 3
      add :condition, :string
  add :attractor_m, :integer
  add :attractor_tau, :integer
  add :attractor_min_points, :integer
      add :status, :string, null: false
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:probe_runs, [:status])
    create index(:probe_runs, [:provider])
    create index(:probe_runs, [:model])

    create table(:probe_laps, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :run_id, references(:probe_runs, type: :uuid, on_delete: :delete_all), null: false
      add :lap_index, :integer, null: false
      add :response_preview, :text
      add :char_entropy, :float, null: false, default: 0.0
      add :lexical_diversity, :float, null: false, default: 0.0
      add :repetition_ratio, :float, null: false, default: 0.0
      add :cosine_to_prev, :float, null: false, default: 0.0
      add :elapsed_ms, :integer, null: false, default: 0
      add :embedding, {:array, :float}, null: false, default: []
      add :js_divergence_vs_baseline, :float
      add :topk_overlap_vs_baseline, :float
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:probe_laps, [:run_id, :lap_index])
  end
end
