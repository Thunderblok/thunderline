defmodule Thunderline.Thundergate.Resources.FederatedMessage do
  @moduledoc """
  FederatedMessage Resource - Cross-Realm Message Federation

  Manages federated messages flowing between realms, ensuring proper
  routing, security, and delivery across the Thunderline federation.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource]
  import Ash.Resource.Change.Builtins


  attributes do
    uuid_primary_key :id

    attribute :source_realm_id, :uuid do
      allow_nil? false
      description "Originating realm"
    end

    attribute :target_realm_id, :uuid do
      allow_nil? true
      description "Target realm (null for broadcast)"
    end

    attribute :message_type, :string do
      allow_nil? false
      description "Type of federated message: activity, follow, unfollow, like, share, announce, delete"
    end

    attribute :message_content, :map do
      allow_nil? false
      description "Message payload and metadata"
      default %{}
    end

    attribute :signature, :string do
      allow_nil? false
      description "Cryptographic signature"
      constraints max_length: 1024
    end

    attribute :delivery_status, :atom do
      allow_nil? false
      description "Message delivery status"
      default :pending
      constraints one_of: [:pending, :delivered, :failed, :rejected]
    end

    attribute :delivery_attempts, :integer do
      allow_nil? false
      description "Number of delivery attempts"
      default 0
      constraints min: 0
    end

    attribute :delivered_at, :utc_datetime do
      allow_nil? true
      description "Delivery timestamp"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :federate_message do
      accept [:source_realm_id, :target_realm_id, :message_type, :message_content, :signature]
    end

    update :mark_delivered do
      accept [:delivery_status, :delivered_at]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:delivery_status, :delivered)
        |> Ash.Changeset.change_attribute(:delivered_at, DateTime.utc_now())
      end
    end

    update :increment_attempts do
      change fn changeset, _context ->
        current_attempts = Ash.Changeset.get_attribute(changeset, :delivery_attempts) || 0
        Ash.Changeset.change_attribute(changeset, :delivery_attempts, current_attempts + 1)
      end
    end

    destroy :cleanup_old_messages do
      filter expr(inserted_at < ago(7, :day) and delivery_status == :delivered)
    end
  end

  relationships do
    belongs_to :source_realm, Thunderline.Thundergate.Resources.FederatedRealm do
      source_attribute :source_realm_id
      destination_attribute :id
    end

    belongs_to :target_realm, Thunderline.Thundergate.Resources.FederatedRealm do
      source_attribute :target_realm_id
      destination_attribute :id
    end
  end

  postgres do
    table "thundercom_federated_messages"
    repo Thundercom.Repo

    custom_indexes do
      index [:source_realm_id]
      index [:target_realm_id]
      index [:delivery_status]
      index [:message_type]
      index [:inserted_at]
    end
  end
end
