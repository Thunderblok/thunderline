defmodule Thunderline.Thundercore.Resources.IdentityKernel do
  @moduledoc """
  Identity kernel resource - the seedpoint of PAC identity.

  The IdentityKernel represents the fundamental identity unit in Thunderline.
  It is the origin from which PAC instances derive their identity and is
  immutable once created.

  ## Identity Hierarchy

  ```
  IdentityKernel (seedpoint)
    └── PAC (agent instance)
        └── Memories
        └── Traits
        └── Zone memberships
  ```

  ## Fields

  - `kernel_id` - Primary identifier (UUID)
  - `seed` - 32-byte random seed for deterministic identity derivation
  - `created_at_tick` - System tick when kernel was created
  - `lineage` - Optional parent kernel for identity inheritance
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundercore.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  alias Thunderline.Thundercore.Resources.IdentityKernel

  @seed_bytes 32

  postgres do
    table "identity_kernels"
    repo Thunderline.Repo
  end

  admin do
    form do
      field :kernel_id, type: :default
      field :seed, type: :default
      field :lineage_id, type: :default
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kernel_id, :uuid do
      allow_nil? false
      public? true
      description "Unique kernel identifier"
    end

    attribute :seed, :binary do
      allow_nil? false
      public? true
      description "32-byte random seed for identity derivation"
    end

    attribute :created_at_tick, :integer do
      allow_nil? true
      public? true
      description "System tick when kernel was created"
    end

    attribute :metadata, :map do
      default %{}
      public? true
      description "Optional metadata for the kernel"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :lineage, IdentityKernel do
      allow_nil? true
      public? true
      description "Parent kernel for inheritance"
    end
  end

  identities do
    identity :unique_kernel_id, [:kernel_id]
  end

  actions do
    defaults [:read, :destroy]

    create :ignite do
      description "Create a new identity kernel (ignition)"
      accept [:metadata, :lineage_id]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:kernel_id, Ash.UUID.generate())
        |> Ash.Changeset.change_attribute(:seed, generate_seed())
        |> maybe_set_tick()
      end
    end

    create :derive do
      description "Derive a new kernel from a parent (lineage)"
      accept [:metadata]
      argument :parent_kernel_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        parent_id = Ash.Changeset.get_argument(changeset, :parent_kernel_id)

        changeset
        |> Ash.Changeset.change_attribute(:kernel_id, Ash.UUID.generate())
        |> Ash.Changeset.change_attribute(:seed, generate_seed())
        |> Ash.Changeset.change_attribute(:lineage_id, parent_id)
        |> maybe_set_tick()
      end
    end

    read :by_kernel_id do
      description "Find kernel by its unique kernel_id"
      argument :kernel_id, :uuid, allow_nil?: false

      filter expr(kernel_id == ^arg(:kernel_id))
    end
  end

  code_interface do
    define :ignite
    define :derive, args: [:parent_kernel_id]
    define :by_kernel_id, args: [:kernel_id], action: :by_kernel_id
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════

  defp generate_seed do
    :crypto.strong_rand_bytes(@seed_bytes)
  end

  defp maybe_set_tick(changeset) do
    # Try to get current tick from TickEmitter if running
    tick =
      try do
        Thunderline.Thundercore.TickEmitter.current_tick()
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end

    if tick do
      Ash.Changeset.change_attribute(changeset, :created_at_tick, tick)
    else
      changeset
    end
  end
end
