defmodule Thunderline.Thundercom.Resources.VoiceDevice do
  @moduledoc """
  VoiceDevice Resource - Tracks a user's preferred input/output devices & last ICE success.

  This is user-scoped configuration (potentially ephemeral) but persisted for convenience.
  """
  use Ash.Resource,
    domain: Thunderline.Thundercom.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "voice_devices"
    repo Thunderline.Repo
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

  policies do
    # Owner-only operations
    policy action([:register, :update_devices, :mark_ice_result, :deactivate]) do
      authorize_if expr(principal_id == actor(:id))
    end

    policy action(:read) do
      authorize_if expr(principal_id == actor(:id))
    end
  end

  code_interface do
    define :register
    define :update_devices
    define :mark_ice_result
    define :deactivate
  end

  # --- Helpers -----------------------------------------------------------
  defp touch_last_ice(changeset, _ctx) do
    Ash.Changeset.change_attribute(changeset, :last_ice_ts, DateTime.utc_now())
  end

  defp ensure_metadata(changeset, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :metadata) do
      %{} -> changeset
      _ -> Ash.Changeset.change_attribute(changeset, :metadata, %{})
    end
  end
end
