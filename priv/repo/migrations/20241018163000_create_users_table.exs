defmodule Thunderline.Repo.Migrations.CreateUsersTable do
  @moduledoc """
  Creates users table for VaultUser resource.
  """

  use Ecto.Migration

  def up do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :email, :citext, null: false
      add :hashed_password, :text, null: false
      add :first_name, :text
      add :last_name, :text
      add :avatar_url, :text
      add :role, :text, null: false, default: "user"
      add :confirmed_at, :utc_datetime_usec
      add :last_login_at, :utc_datetime_usec
      add :login_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
  end

  def down do
    drop table(:users)
  end
end
