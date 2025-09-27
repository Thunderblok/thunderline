defmodule Thunderline.Thunderlink.Voice.Device do
  @moduledoc """
  Voice Device Resource (Thunderlink) – migrated from Thundercom.
  """
  use Ash.Resource,
    domain: Thunderline.Thunderlink.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "voice_devices"
    repo Thunderline.Repo
  end

  # Link domain policy purged (WARHORSE)

  code_interface do
    define :register
    define :update_devices
    define :mark_ice_result
    define :deactivate
  end

  actions do
    defaults [:read]

    create :register do
      accept [:principal_id, :input_device_id, :output_device_id, :metadata]
      change &ensure_metadata/2
      change &touch_last_ice/2
    end

    update :update_devices do
      accept [:input_device_id, :output_device_id]
    end

    update :mark_ice_result do
      accept [:last_ice_ok]
      change &touch_last_ice/2
    end

    update :deactivate do
      accept []
      change fn cs, _ -> Ash.Changeset.change_attribute(cs, :last_ice_ok, false) end
      change &touch_last_ice/2
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :principal_id, :uuid, allow_nil?: false
    attribute :input_device_id, :string, allow_nil?: true
    attribute :output_device_id, :string, allow_nil?: true
    attribute :last_ice_ok, :boolean, allow_nil?: false, default: false
    attribute :last_ice_ts, :utc_datetime, allow_nil?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_principal, [:principal_id]
  end

  defp touch_last_ice(changeset, _ctx),
    do: Ash.Changeset.change_attribute(changeset, :last_ice_ts, DateTime.utc_now())

  defp ensure_metadata(changeset, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :metadata) do
      %{} -> changeset
      _ -> Ash.Changeset.change_attribute(changeset, :metadata, %{})
    end
  end
end
