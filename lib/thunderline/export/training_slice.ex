defmodule Thunderline.Export.TrainingSlice do
  @moduledoc "NAS task export job (slice of feature windows + labels)."
  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "export_jobs"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :slice_spec, :map, allow_nil?: false, default: %{}
    attribute :status, :atom, allow_nil?: false, default: :pending, constraints: [one_of: [:pending, :running, :completed, :failed]]
    attribute :artifact_uri, :string
    attribute :error, :string
    attribute :completed_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
    create :enqueue do
      accept [:tenant_id, :slice_spec]
    end
    update :mark_completed do
      accept [:artifact_uri, :status, :completed_at]
      change fn cs,_ -> Ash.Changeset.change_attribute(cs, :status, :completed) end
    end
    update :mark_failed do
      accept [:error, :status]
      change fn cs,_ -> Ash.Changeset.change_attribute(cs, :status, :failed) end
    end
  end

  policies do
    policy action([:enqueue, :mark_completed, :mark_failed]) do
      authorize_if expr(not is_nil(actor(:id)))
    end
    policy action(:read) do
      authorize_if expr(not is_nil(actor(:id)))
    end
  end

  code_interface do
    define :enqueue
    define :mark_completed
    define :mark_failed
    define :read
  end
end
