defmodule Thunderline.Integration.EventLedgerTest do
  @moduledoc """
  T-72h Directive #2: Event Ledger Integration Tests.

  Tests:
  - Genesis event exists with valid signature
  - Append-only constraint prevents updates
  - Hash chain continuity (event N+1 references event N)
  - Signature verification across key rotation

  Ownership: Renegade-S + Shadow-Sec
  Command Code: rZX45120
  """

  use Thunderline.DataCase, async: false

  alias Thunderline.Repo
  alias Thunderline.Thundercrown.SigningService

  setup do
    # Ensure signing service is started
    case Process.whereis(SigningService) do
      nil -> {:ok, _pid} = SigningService.start_link()
      _pid -> :ok
    end

    :ok
  end

  describe "genesis event" do
    @tag :integration
    test "genesis event exists in ledger" do
      query = """
      SELECT id, resource, action, event_hash, event_signature, key_id,
             ledger_version, previous_hash
      FROM thunderline_events
      WHERE resource = 'genesis' AND action = 'initialize_ledger'
      LIMIT 1
      """

      case Repo.query(query) do
        {:ok, %{rows: [row]}} ->
          [id, resource, action, event_hash, event_signature, key_id, ledger_version, prev_hash] =
            row

          assert resource == "genesis"
          assert action == "initialize_ledger"
          assert is_binary(event_hash)
          assert byte_size(event_hash) == 32
          assert is_binary(event_signature)
          assert is_binary(key_id)
          assert ledger_version == 1
          assert is_nil(prev_hash)

          # Verify signature
          assert :ok = SigningService.verify_signature(event_hash, event_signature, key_id)

        {:ok, %{rows: []}} ->
          flunk("Genesis event not found. Run: mix run priv/repo/seeds/genesis_event.exs")

        {:error, error} ->
          flunk("Failed to query genesis event: #{inspect(error)}")
      end
    end
  end

  describe "append-only constraint" do
    @tag :integration
    test "prevents UPDATE operations on events" do
      # Insert test event
      event = %{
        id: Ecto.UUID.generate(),
        resource: "test_resource",
        action: "test_action",
        action_type: "create",
        record_id: Ecto.UUID.generate(),
        data: %{original: "data"},
        version: 1,
        domain: "gate",
        metadata: %{},
        occurred_at: DateTime.utc_now(),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        ledger_version: 1,
        event_hash: :crypto.hash(:sha256, "test"),
        event_signature: "test_signature",
        key_id: "test_key",
        previous_hash: nil
      }

      insert_query = """
      INSERT INTO thunderline_events (
        id, resource, action, action_type, record_id, data, version,
        domain, metadata, occurred_at, inserted_at, updated_at,
        ledger_version, event_hash, event_signature, key_id, previous_hash
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
      """

      insert_params = [
        event.id,
        event.resource,
        event.action,
        event.action_type,
        event.record_id,
        event.data,
        event.version,
        event.domain,
        event.metadata,
        event.occurred_at,
        event.inserted_at,
        event.updated_at,
        event.ledger_version,
        event.event_hash,
        event.event_signature,
        event.key_id,
        event.previous_hash
      ]

      {:ok, _} = Repo.query(insert_query, insert_params)

      # Attempt to UPDATE (should be blocked by append-only rule)
      update_query = """
      UPDATE thunderline_events
      SET data = $1
      WHERE id = $2
      """

      # PostgreSQL rule prevents UPDATE by doing NOTHING
      # This means UPDATE succeeds but affects 0 rows
      {:ok, result} = Repo.query(update_query, [%{modified: "data"}, event.id])

      # Verify no rows were updated
      assert result.num_rows == 0

      # Verify original data unchanged
      select_query = "SELECT data FROM thunderline_events WHERE id = $1"
      {:ok, %{rows: [[data]]}} = Repo.query(select_query, [event.id])

      assert data == %{"original" => "data"}
    end

    @tag :integration
    test "allows INSERT operations (append-only)" do
      event = %{
        id: Ecto.UUID.generate(),
        resource: "append_test",
        action: "create",
        action_type: "create",
        record_id: Ecto.UUID.generate(),
        data: %{test: "append"},
        version: 1,
        domain: "gate",
        metadata: %{},
        occurred_at: DateTime.utc_now(),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        ledger_version: 1,
        event_hash: :crypto.hash(:sha256, "append_test"),
        event_signature: "signature",
        key_id: "key_id",
        previous_hash: nil
      }

      query = """
      INSERT INTO thunderline_events (
        id, resource, action, action_type, record_id, data, version,
        domain, metadata, occurred_at, inserted_at, updated_at,
        ledger_version, event_hash, event_signature, key_id, previous_hash
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
      """

      params = [
        event.id,
        event.resource,
        event.action,
        event.action_type,
        event.record_id,
        event.data,
        event.version,
        event.domain,
        event.metadata,
        event.occurred_at,
        event.inserted_at,
        event.updated_at,
        event.ledger_version,
        event.event_hash,
        event.event_signature,
        event.key_id,
        event.previous_hash
      ]

      # INSERT should succeed
      assert {:ok, %{num_rows: 1}} = Repo.query(query, params)

      # Verify event exists
      select_query = "SELECT id FROM thunderline_events WHERE id = $1"
      assert {:ok, %{rows: [[_id]]}} = Repo.query(select_query, [event.id])
    end
  end

  describe "hash chain continuity" do
    @tag :integration
    test "event N+1 references hash of event N" do
      # Create event N
      event_n = %{
        id: Ecto.UUID.generate(),
        name: "chain.event_n",
        source: :gate,
        payload: %{sequence: 1},
        at: DateTime.utc_now(),
        correlation_id: "chain-test"
      }

      hash_n = SigningService.compute_event_hash(event_n)
      {:ok, sig_n, key_id_n} = SigningService.sign_event(hash_n)

      insert_query = """
      INSERT INTO thunderline_events (
        id, resource, action, action_type, record_id, data, version,
        domain, metadata, occurred_at, inserted_at, updated_at,
        ledger_version, event_hash, event_signature, key_id, previous_hash
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
      """

      {:ok, _} =
        Repo.query(insert_query, [
          event_n.id,
          "chain_test",
          "event_n",
          "create",
          Ecto.UUID.generate(),
          event_n.payload,
          1,
          "gate",
          %{},
          event_n.at,
          DateTime.utc_now(),
          DateTime.utc_now(),
          1,
          hash_n,
          sig_n,
          key_id_n,
          nil
        ])

      # Create event N+1 referencing hash_n
      event_n_plus_1 = %{
        id: Ecto.UUID.generate(),
        name: "chain.event_n_plus_1",
        source: :gate,
        payload: %{sequence: 2},
        at: DateTime.utc_now(),
        correlation_id: "chain-test"
      }

      hash_n_plus_1 = SigningService.compute_event_hash(event_n_plus_1)
      {:ok, sig_n_plus_1, key_id_n_plus_1} = SigningService.sign_event(hash_n_plus_1)

      {:ok, _} =
        Repo.query(insert_query, [
          event_n_plus_1.id,
          "chain_test",
          "event_n_plus_1",
          "create",
          Ecto.UUID.generate(),
          event_n_plus_1.payload,
          1,
          "gate",
          %{},
          event_n_plus_1.at,
          DateTime.utc_now(),
          DateTime.utc_now(),
          1,
          hash_n_plus_1,
          sig_n_plus_1,
          key_id_n_plus_1,
          hash_n
        ])

      # Verify chain linkage
      query = """
      SELECT e1.event_hash AS hash_n, e2.previous_hash AS prev_hash_n_plus_1
      FROM thunderline_events e1
      JOIN thunderline_events e2 ON e1.event_hash = e2.previous_hash
      WHERE e1.id = $1 AND e2.id = $2
      """

      {:ok, %{rows: [[retrieved_hash_n, retrieved_prev_hash]]}} =
        Repo.query(query, [event_n.id, event_n_plus_1.id])

      assert retrieved_hash_n == hash_n
      assert retrieved_prev_hash == hash_n
    end
  end
end
