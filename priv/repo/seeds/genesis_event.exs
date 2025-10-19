#!/usr/bin/env elixir

# T-72h Directive #2: Genesis Event Seeder
#
# Inserts the first event into the ledger with:
# - Computed SHA256 hash of canonical event data
# - ECDSA signature (Ed25519) of the hash
# - previous_hash = nil (genesis has no predecessor)
# - ledger_version = 1
#
# This establishes the root of the event hash chain.
#
# Ownership: Renegade-S
# Command Code: rZX45120

Mix.install([])

# Start required applications
Application.ensure_all_started(:thunderline)

alias Thunderline.Repo
alias Thunderline.Thundercrown.SigningService

# Ensure signing service is started
{:ok, _pid} = SigningService.start_link()

# Genesis event data
genesis_event = %{
  id: Ecto.UUID.generate(),
  resource: "genesis",
  action: "initialize_ledger",
  action_type: "create",
  record_id: Ecto.UUID.generate(),
  data: %{
    message: "Event ledger genesis block",
    version: 1,
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
  },
  version: 1,
  domain: "crown",
  metadata: %{genesis: true, significance: "root_of_trust"},
  occurred_at: DateTime.utc_now(),
  inserted_at: DateTime.utc_now(),
  updated_at: DateTime.utc_now(),
  ledger_version: 1,
  previous_hash: nil
}

IO.puts("[Genesis] Creating event ledger genesis block...")

# Compute canonical hash
hash_input = %{
  id: genesis_event.id,
  name: "genesis.initialize_ledger",
  source: :crown,
  payload: genesis_event.data,
  at: genesis_event.occurred_at,
  correlation_id: nil
}

event_hash = SigningService.compute_event_hash(hash_input)

IO.puts("[Genesis] Computed event_hash: #{Base.encode16(event_hash, case: :lower)}")

# Sign event hash
case SigningService.sign_event(event_hash) do
  {:ok, signature, key_id} ->
    IO.puts("[Genesis] Signed with key_id: #{key_id}")

    # Insert genesis event
    genesis_with_ledger =
      genesis_event
      |> Map.put(:event_hash, event_hash)
      |> Map.put(:event_signature, signature)
      |> Map.put(:key_id, key_id)

    query = """
    INSERT INTO thunderline_events (
      id, resource, action, action_type, record_id, data, version,
      domain, metadata, occurred_at, inserted_at, updated_at,
      ledger_version, event_hash, event_signature, key_id, previous_hash
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
    """

    params = [
      genesis_with_ledger.id,
      genesis_with_ledger.resource,
      genesis_with_ledger.action,
      genesis_with_ledger.action_type,
      genesis_with_ledger.record_id,
      genesis_with_ledger.data,
      genesis_with_ledger.version,
      genesis_with_ledger.domain,
      genesis_with_ledger.metadata,
      genesis_with_ledger.occurred_at,
      genesis_with_ledger.inserted_at,
      genesis_with_ledger.updated_at,
      genesis_with_ledger.ledger_version,
      genesis_with_ledger.event_hash,
      genesis_with_ledger.event_signature,
      genesis_with_ledger.key_id,
      genesis_with_ledger.previous_hash
    ]

    case Repo.query(query, params) do
      {:ok, _result} ->
        IO.puts("[Genesis] ✓ Genesis event inserted successfully")
        IO.puts("[Genesis] Event ID: #{genesis_event.id}")
        IO.puts("[Genesis] Event Hash: #{Base.encode16(event_hash, case: :lower)}")

        # Verify signature
        case SigningService.verify_signature(event_hash, signature, key_id) do
          :ok ->
            IO.puts("[Genesis] ✓ Signature verified")
            IO.puts("[Genesis] Event ledger genesis complete!")

          {:error, reason} ->
            IO.puts("[Genesis] ✗ Signature verification failed: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, error} ->
        IO.puts("[Genesis] ✗ Failed to insert genesis event: #{inspect(error)}")
        System.halt(1)
    end

  {:error, reason} ->
    IO.puts("[Genesis] ✗ Failed to sign event: #{inspect(reason)}")
    System.halt(1)
end
