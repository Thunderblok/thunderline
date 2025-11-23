defmodule Thunderline.Repo.Migrations.FixObanInsertedAtDefault do
  use Ecto.Migration

  def up do
    # No-op migration: The database already has the correct default value
    # for inserted_at via fragment("timezone('UTC', now())"). The issue
    # was in application code sending explicit NULL values which override
    # the database default. This is fixed in the application layer.
    :ok
  end

  def down do
    :ok
  end
end
