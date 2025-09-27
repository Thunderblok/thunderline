defmodule Thunderline.Repo.Migrations.AddTenancyToExpertsAndLineage do
  use Ecto.Migration

  def up do
    alter table(:experts) do
      add :tenant_id, :uuid
    end

    alter table(:lineage_edges) do
      add :tenant_id, :uuid
    end

    flush()

    execute(&try_db_backfill/0, fn -> :ok end)

    execute "ALTER TABLE experts       ALTER COLUMN tenant_id SET NOT NULL"
    execute "ALTER TABLE lineage_edges ALTER COLUMN tenant_id SET NOT NULL"

    execute "CREATE INDEX IF NOT EXISTS experts_tenant_id_status_idx ON experts(tenant_id, status)"

    execute "CREATE INDEX IF NOT EXISTS lineage_edges_tenant_id_day_idx ON lineage_edges(tenant_id, day_bucket)"
  end

  def down do
    execute "DROP INDEX IF EXISTS experts_tenant_id_status_idx"
    execute "DROP INDEX IF EXISTS lineage_edges_tenant_id_day_idx"
    alter table(:experts), do: remove(:tenant_id)
    alter table(:lineage_edges), do: remove(:tenant_id)
  end

  defp try_db_backfill do
    repo = Ecto.Migration.repo()

    has_uuid_ossp =
      repo.query!("SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='uuid-ossp')").rows
      |> hd()
      |> hd()

    has_pgcrypto =
      repo.query!("SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pgcrypto')").rows
      |> hd()
      |> hd()

    cond do
      has_uuid_ossp ->
        repo.query!(
          "UPDATE experts       SET tenant_id = uuid_generate_v4() WHERE tenant_id IS NULL"
        )

        repo.query!(
          "UPDATE lineage_edges SET tenant_id = uuid_generate_v4() WHERE tenant_id IS NULL"
        )

      has_pgcrypto ->
        repo.query!(
          "UPDATE experts       SET tenant_id = gen_random_uuid() WHERE tenant_id IS NULL"
        )

        repo.query!(
          "UPDATE lineage_edges SET tenant_id = gen_random_uuid() WHERE tenant_id IS NULL"
        )

      true ->
        backfill_with_elixir(repo, "experts")
        backfill_with_elixir(repo, "lineage_edges")
    end
  end

  defp backfill_with_elixir(repo, table) do
    repo.transaction(fn ->
      {:ok, %{rows: rows}} = repo.query("SELECT id FROM #{table} WHERE tenant_id IS NULL")

      Enum.each(rows, fn [id] ->
        repo.query!("UPDATE #{table} SET tenant_id = $1 WHERE id = $2", [Ecto.UUID.generate(), id])
      end)
    end)
  end
end
