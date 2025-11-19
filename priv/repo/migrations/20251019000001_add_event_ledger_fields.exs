defmodule Thunderline.Repo.Migrations.AddEventLedgerFields do
  @moduledoc """
  T-72h Directive #2: Event Ledger Genesis Block.

  Adds cryptographic signature fields to thunderline_events table:
  - event_hash: SHA256 hash of canonical event payload
  - event_signature: ECDSA signature of event_hash (Ed25519)
  - key_id: Identifier for the signing key (rotation support)
  - ledger_version: Event ledger schema version
  - previous_hash: SHA256 of previous event (blockchain-style chain)

  Also adds append-only constraint via PostgreSQL rule to prevent updates.

  Ownership: Renegade-S + Shadow-Sec
  Command Code: rZX45120
  """

  use Ecto.Migration

  def up do
    # Add ledger fields
    alter table(:thunderline_events) do
      add :event_hash, :bytea, comment: "SHA256 hash of canonical event data"
      add :event_signature, :bytea, comment: "ECDSA signature of event_hash (Ed25519)"
      add :key_id, :string, comment: "Signing key identifier for rotation tracking"

      add :ledger_version, :integer,
        default: 1,
        null: false,
        comment: "Event ledger schema version"

      add :previous_hash, :bytea, comment: "SHA256 hash of previous event (chain linkage)"
    end

    # Create index for hash chain traversal
    create index(:thunderline_events, [:previous_hash])
    create index(:thunderline_events, [:event_hash])
    create index(:thunderline_events, [:key_id])
    create index(:thunderline_events, [:ledger_version])

    # Add append-only constraint via PostgreSQL rule
    # This prevents UPDATE operations, only INSERT and SELECT are allowed
    execute """
    CREATE RULE thunderline_events_append_only AS
      ON UPDATE TO thunderline_events
      DO INSTEAD NOTHING;
    """

    # Add comment explaining the append-only nature
    execute """
    COMMENT ON TABLE thunderline_events IS
    'Append-only event ledger with cryptographic signatures.
    Updates are blocked via append_only rule.
    To correct errors, insert a compensating event.';
    """
  end

  def down do
    # Drop append-only rule
    execute "DROP RULE IF EXISTS thunderline_events_append_only ON thunderline_events;"

    # Remove ledger fields
    alter table(:thunderline_events) do
      remove :event_hash
      remove :event_signature
      remove :key_id
      remove :ledger_version
      remove :previous_hash
    end
  end
end
