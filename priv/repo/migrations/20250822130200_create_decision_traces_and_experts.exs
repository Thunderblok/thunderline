defmodule Thunderline.Repo.Migrations.CreateDecisionTracesAndExperts do
  use Ecto.Migration

  def change do
    create table(:experts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :version, :text, null: false
      add :status, :string, null: false, default: "active"
      add :latency_budget_ms, :integer
      add :metrics, :map, null: false, default: %{}
      add :model_artifact_ref, :text
      timestamps(type: :utc_datetime)
    end
    create unique_index(:experts, [:name, :version])

    create table(:decision_traces, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :uuid, null: false
      add :feature_window_id, references(:feature_windows, type: :uuid, on_delete: :delete_all), null: false
      add :router_version, :text, null: false
      add :gate_scores, :map, null: false, default: %{}
      add :selected_experts, :map, null: false, default: %{}
      add :actions, :map, null: false, default: %{}
      add :blended_action, :map
      add :pnl_snapshot, :map
      add :risk_flags, :map, null: false, default: %{}
      add :behavior_embedding, :binary
      add :hash, :binary, null: false
      timestamps(type: :utc_datetime)
    end
    create index(:decision_traces, [:feature_window_id])
    create index(:decision_traces, [:tenant_id, :inserted_at])
  end
end
