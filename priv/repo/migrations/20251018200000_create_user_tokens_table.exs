defmodule Thunderline.Repo.Migrations.CreateUserTokensTable do
  @moduledoc """
  Migration: Create user_tokens table for VaultUserToken resource.

  Supports authentication tokens for:
  - Password resets
  - Email confirmations
  - Session tokens
  - Magic link authentication
  """
  use Ecto.Migration

  def up do
    create table(:user_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime, default: fragment("now()"))
    end

    create index(:user_tokens, [:user_id])
    create index(:user_tokens, [:context])
    create unique_index(:user_tokens, [:token])
  end

  def down do
    drop table(:user_tokens)
  end
end
