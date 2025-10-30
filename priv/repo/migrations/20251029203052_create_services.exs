defmodule Thunderline.Repo.Migrations.CreateServices do
  use Ecto.Migration

  def change do
    create table(:services, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :host, :string, null: false
      add :port, :integer
      add :status, :string, default: "registering", null: false
      add :capabilities, {:array, :string}, default: []
      add :metadata, :map, default: %{}
      add :last_heartbeat, :utc_datetime

      timestamps()
    end

    create index(:services, [:type])
    create index(:services, [:status])
    create index(:services, [:last_heartbeat])
    create unique_index(:services, [:name], name: :services_name_unique_index)
  end
end
