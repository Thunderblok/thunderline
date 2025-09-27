defmodule Thunderline.Repo.Migrations.CreateProbeAttractorSummaries do
  use Ecto.Migration

  def change do
    create table(:probe_attractor_summaries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :run_id, references(:probe_runs, type: :uuid, on_delete: :delete_all), null: false
      add :points, :integer, null: false, default: 0
      add :delay_rows, :integer, null: false, default: 0
      add :m, :integer, null: false, default: 3
      add :tau, :integer, null: false, default: 1
      add :corr_dim, :float, null: false, default: 0.0
      add :lyap, :float, null: false, default: 0.0
      add :lyap_r2, :float
      add :lyap_window, :string
      add :reliable, :boolean, null: false, default: false
      add :note, :text
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:probe_attractor_summaries, [:corr_dim])
    create index(:probe_attractor_summaries, [:lyap])
    create unique_index(:probe_attractor_summaries, [:run_id])
  end
end
