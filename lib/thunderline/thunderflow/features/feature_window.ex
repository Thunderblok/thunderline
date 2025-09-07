defmodule Thunderline.Features.FeatureWindow do
  @moduledoc """
  Unified feature window across event sources.
  Partial windows (status :open) may lack labels; fill action finalizes to :filled.
  Superseded windows retained for provenance.

  Domain Placement: Thunderflow (feature assembly stage). Modeling/rescoring & expert
  orchestration occurs in Thunderbolt (MoE/DecisionTrace downstream).
  """
  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "feature_windows"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false
  attribute :kind, :atom, allow_nil?: false
    attribute :key, :string, allow_nil?: false
    attribute :window_start, :utc_datetime, allow_nil?: false
    attribute :window_end, :utc_datetime, allow_nil?: false
    attribute :status, :atom, allow_nil?: false, default: :open, constraints: [one_of: [:open, :filled, :superseded]]
    attribute :features, :map, allow_nil?: false, default: %{}
    attribute :label_spec, :map, allow_nil?: false, default: %{}
    attribute :labels, :map, allow_nil?: true
    attribute :feature_schema_version, :integer, allow_nil?: false
    attribute :provenance, :map, allow_nil?: false, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :label_filled?, :boolean, expr(not is_nil(labels))
  end

  actions do
    defaults [:read]

    create :ingest_window do
      accept [:tenant_id, :kind, :key, :window_start, :window_end, :features, :label_spec, :feature_schema_version, :provenance]
    end

    update :fill_labels do
      accept [:labels, :status, :provenance]
      change fn changeset, _ ->
        case Ash.Changeset.get_attribute(changeset, :status) do
          :filled -> changeset
          _ -> Ash.Changeset.change_attribute(changeset, :status, :filled)
        end
      end
    end

    update :supersede do
      accept [:status]
      change fn cs, _ -> Ash.Changeset.change_attribute(cs, :status, :superseded) end
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  policies do
    # Create-specific policy: for creates we can't reference resource attrs directly in filters.
    policy [action(:ingest_window), action_type(:create)] do
      authorize_if changing_attributes(tenant_id: [equals_actor: :tenant_id])
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end

    # Read and updates authorized by tenant match
    policy action([:fill_labels, :supersede, :read]) do
      authorize_if expr(tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) in [:maintenance])
    end
  end

  code_interface do
    define :ingest_window
    define :fill_labels
    define :supersede
    define :read
  end
end
