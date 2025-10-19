defmodule Thunderline.Thundercrown.SigningServiceTest do
  @moduledoc """
  T-72h Directive #2: Signing Service Unit Tests.

  Tests:
  - Event hash computation consistency
  - Signature generation and verification
  - Key rotation behavior
  - Error handling (invalid signatures, unknown keys)

  Ownership: Renegade-S + Shadow-Sec
  Command Code: rZX45120
  """

  use ExUnit.Case, async: false

  alias Thunderline.Thundercrown.SigningService

  setup do
    # Start signing service
    {:ok, pid} = SigningService.start_link()

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    :ok
  end

  describe "compute_event_hash/1" do
    test "generates deterministic SHA256 hash" do
      event = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "test.event",
        source: :gate,
        payload: %{key: "value"},
        at: ~U[2025-01-19 12:00:00Z],
        correlation_id: "corr-123"
      }

      hash1 = SigningService.compute_event_hash(event)
      hash2 = SigningService.compute_event_hash(event)

      assert hash1 == hash2
      assert byte_size(hash1) == 32
    end

    test "hash changes with different event data" do
      event1 = %{
        id: "id1",
        name: "test.event",
        source: :gate,
        payload: %{key: "value1"},
        at: ~U[2025-01-19 12:00:00Z],
        correlation_id: nil
      }

      event2 = %{event1 | payload: %{key: "value2"}}

      hash1 = SigningService.compute_event_hash(event1)
      hash2 = SigningService.compute_event_hash(event2)

      assert hash1 != hash2
    end

    test "hash is stable regardless of map key order" do
      # Maps internally order keys, but test explicit reordering
      event1 = %{
        id: "id",
        name: "test",
        source: :gate,
        payload: %{a: 1, b: 2},
        at: ~U[2025-01-19 12:00:00Z],
        correlation_id: nil
      }

      event2 = %{
        correlation_id: nil,
        at: ~U[2025-01-19 12:00:00Z],
        payload: %{b: 2, a: 1},
        source: :gate,
        name: "test",
        id: "id"
      }

      hash1 = SigningService.compute_event_hash(event1)
      hash2 = SigningService.compute_event_hash(event2)

      assert hash1 == hash2
    end
  end

  describe "sign_event/1 and verify_signature/3" do
    test "successfully signs and verifies event hash" do
      event = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "test.event",
        source: :gate,
        payload: %{key: "value"},
        at: ~U[2025-01-19 12:00:00Z],
        correlation_id: "corr-123"
      }

      event_hash = SigningService.compute_event_hash(event)

      # Sign event
      assert {:ok, signature, key_id} = SigningService.sign_event(event_hash)
      assert is_binary(signature)
      assert is_binary(key_id)
      assert String.starts_with?(key_id, "crown-key-")

      # Verify signature
      assert :ok = SigningService.verify_signature(event_hash, signature, key_id)
    end

    test "verification fails with wrong hash" do
      event = %{
        id: "id",
        name: "test",
        source: :gate,
        payload: %{key: "value"},
        at: ~U[2025-01-19 12:00:00Z],
        correlation_id: nil
      }

      event_hash = SigningService.compute_event_hash(event)
      {:ok, signature, key_id} = SigningService.sign_event(event_hash)

      # Tamper with hash
      tampered_hash = :crypto.hash(:sha256, "tampered")

      assert {:error, _reason} =
               SigningService.verify_signature(tampered_hash, signature, key_id)
    end

    test "verification fails with unknown key_id" do
      event = %{
        id: "id",
        name: "test",
        source: :gate,
        payload: %{},
        at: ~U[2025-01-19 12:00:00Z],
        correlation_id: nil
      }

      event_hash = SigningService.compute_event_hash(event)
      {:ok, signature, _key_id} = SigningService.sign_event(event_hash)

      assert {:error, :unknown_key_id} =
               SigningService.verify_signature(event_hash, signature, "unknown-key-123")
    end
  end

  describe "current_key_id/0" do
    test "returns current active key ID" do
      key_id = SigningService.current_key_id()

      assert is_binary(key_id)
      assert String.starts_with?(key_id, "crown-key-")
    end
  end

  describe "rotate_keys/0" do
    test "rotates to new key while retaining old key" do
      # Get initial key
      initial_key_id = SigningService.current_key_id()

      # Sign event with initial key
      event_hash = :crypto.hash(:sha256, "test event")
      {:ok, signature, ^initial_key_id} = SigningService.sign_event(event_hash)

      # Rotate keys
      :ok = SigningService.rotate_keys()

      # New key should be different
      new_key_id = SigningService.current_key_id()
      assert new_key_id != initial_key_id

      # Old signature should still verify with old key_id
      assert :ok = SigningService.verify_signature(event_hash, signature, initial_key_id)

      # New signatures use new key
      new_event_hash = :crypto.hash(:sha256, "new event")
      {:ok, _new_signature, ^new_key_id} = SigningService.sign_event(new_event_hash)
    end
  end
end
