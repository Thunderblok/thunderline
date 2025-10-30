defmodule Thunderline.Repo.Migrations.FixServicesSchema do
  use Ecto.Migration

  def change do
    # Rename type to service_type
    rename table(:services), :type, to: :service_type

    # Rename last_heartbeat to last_heartbeat_at
    rename table(:services), :last_heartbeat, to: :last_heartbeat_at

    # Add missing columns
    alter table(:services) do
      add :service_id, :string
      add :url, :string
    end

    # Rename timestamps to match Ash resource
    rename table(:services), :inserted_at, to: :registered_at
    # updated_at already matches

    # Add unique index for service_id
    create unique_index(:services, [:service_id], name: :services_service_id_unique_index)

    # Drop the old name unique index (we'll use service_id instead)
    drop index(:services, [:name], name: :services_name_unique_index)
  end
end
