defmodule Thunderline.Repo.Migrations.CreateVoiceDevices do
  use Ecto.Migration

  def change do
    create table(:voice_devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :principal_id, :uuid, null: false
      add :input_device_id, :text
      add :output_device_id, :text
      add :last_ice_ok, :boolean, null: false, default: false
      add :last_ice_ts, :utc_datetime
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:voice_devices, [:principal_id])
  end
end
