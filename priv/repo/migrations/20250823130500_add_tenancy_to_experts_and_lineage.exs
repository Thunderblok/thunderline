defmodule Thunderline.Repo.Migrations.AddTenancyToExpertsAndLineage do
  use Ecto.Migration

  @doc """
  We add tenant_id columns without defaults, backfill any pre-existing rows with
  uuid_generate_v4() (from uuid-ossp extension already in use), then enforce NOT NULL & indexes.
  """
  def up do
    alter table(:experts) do
      add :tenant_id, :uuid
    end
    execute "UPDATE experts SET tenant_id = uuid_generate_v4() WHERE tenant_id IS NULL"
    execute "ALTER TABLE experts ALTER COLUMN tenant_id SET NOT NULL"
    create index(:experts, [:tenant_id, :status])

    alter table(:lineage_edges) do
      add :tenant_id, :uuid
    end
    execute "UPDATE lineage_edges SET tenant_id = uuid_generate_v4() WHERE tenant_id IS NULL"
    execute "ALTER TABLE lineage_edges ALTER COLUMN tenant_id SET NOT NULL"
    create index(:lineage_edges, [:tenant_id, :day_bucket])
  end

  def down do
    drop_if_exists index(:experts, [:tenant_id, :status])
    alter table(:experts) do
      remove :tenant_id
    end

    drop_if_exists index(:lineage_edges, [:tenant_id, :day_bucket])
    alter table(:lineage_edges) do
      remove :tenant_id
    end
  end
end
