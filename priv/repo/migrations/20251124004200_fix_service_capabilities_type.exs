defmodule Thunderline.Repo.Migrations.FixServiceCapabilitiesType do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE services ALTER COLUMN capabilities DROP DEFAULT"
    execute "ALTER TABLE services ALTER COLUMN capabilities TYPE jsonb USING '{}'::jsonb"
    execute "ALTER TABLE services ALTER COLUMN capabilities SET DEFAULT '{}'::jsonb"
  end

  def down do
    execute "ALTER TABLE services ALTER COLUMN capabilities DROP DEFAULT"
    execute "ALTER TABLE services ALTER COLUMN capabilities TYPE text[] USING ARRAY[]::text[]"
    execute "ALTER TABLE services ALTER COLUMN capabilities SET DEFAULT ARRAY[]::text[]"
  end
end
