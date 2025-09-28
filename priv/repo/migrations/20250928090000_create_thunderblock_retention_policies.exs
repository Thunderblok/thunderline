defmodule Thunderline.Repo.Migrations.CreateThunderblockRetentionPolicies do
  use Ecto.Migration

  def change do
    create table(:thunderblock_retention_policies, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :resource, :text, null: false
      add :scope_type, :text, null: false, default: "global"
      add :scope_id, :uuid
      add :ttl_seconds, :bigint
      add :keep_versions, :integer
      add :action, :text, null: false, default: "delete"
      add :grace_seconds, :bigint, null: false, default: 0
      add :metadata, :map, null: false, default: %{}
      add :notes, :text
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:thunderblock_retention_policies, [:resource, :scope_type, :scope_id],
             name: :thunderblock_retention_policies_scope_index
           )

    create index(:thunderblock_retention_policies, [:scope_type, :scope_id])
    create index(:thunderblock_retention_policies, [:is_active])
  end
end
