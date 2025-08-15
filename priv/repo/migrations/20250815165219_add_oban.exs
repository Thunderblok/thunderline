defmodule Thunderline.Repo.Migrations.AddOban do
  use Ecto.Migration

  def up do
    # The Oban table and constraints already exist from previous setup
    # This migration is a no-op to avoid conflicts with existing constraints
    :ok
  end

  def down do
    # No-op since we didn't create anything
    :ok
  end
end
