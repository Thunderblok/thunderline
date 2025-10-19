defmodule Thunderline.Thundercrown.SigningService do
  @moduledoc """
  T-72h Directive #2: Crown ECDSA Signing Service.

  Provides cryptographic signing for event ledger with:
  - Ed25519 keypair generation and management
  - SHA256 event hash computation
  - ECDSA signature generation and verification
  - Key rotation support (30-day rotation, old signatures remain valid)

  ## Usage

      # Generate event hash
      event_data = %{id: "...", name: "...", payload: %{...}}
      event_hash = SigningService.compute_event_hash(event_data)

      # Sign event hash
      {:ok, signature, key_id} = SigningService.sign_event(event_hash)

      # Verify signature
      :ok = SigningService.verify_signature(event_hash, signature, key_id)

  ## Key Rotation

  Keys are rotated automatically every 30 days. Old keys are retained
  for signature verification. The active key is identified by `key_id`.

  Ownership: Renegade-S + Shadow-Sec
  Command Code: rZX45120
  """

  use GenServer
  require Logger

  alias JOSE.{JWK, JWS}

  @key_rotation_days 30
  @key_storage_path "priv/crown_keys"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Compute SHA256 hash of canonical event data.

  Canonical representation: stable JSON serialization of event fields
  in sorted order to ensure deterministic hashing.
  """
  @spec compute_event_hash(map()) :: binary()
  def compute_event_hash(event_data) when is_map(event_data) do
    # Canonical serialization: sort keys, convert to JSON, hash
    canonical_json =
      event_data
      |> Map.take([:id, :name, :source, :payload, :at, :correlation_id])
      |> Enum.sort()
      |> Jason.encode!()

    :crypto.hash(:sha256, canonical_json)
  end

  @doc """
  Sign an event hash with the current active signing key.

  Returns `{:ok, signature, key_id}` or `{:error, reason}`.
  """
  @spec sign_event(binary()) :: {:ok, binary(), String.t()} | {:error, term()}
  def sign_event(event_hash) when is_binary(event_hash) do
    GenServer.call(__MODULE__, {:sign_event, event_hash})
  end

  @doc """
  Verify an event signature against a specific key.

  Returns `:ok` if signature is valid, `{:error, :invalid_signature}` otherwise.
  """
  @spec verify_signature(binary(), binary(), String.t()) :: :ok | {:error, term()}
  def verify_signature(event_hash, signature, key_id) do
    GenServer.call(__MODULE__, {:verify_signature, event_hash, signature, key_id})
  end

  @doc """
  Get the current active key ID.
  """
  @spec current_key_id() :: String.t()
  def current_key_id do
    GenServer.call(__MODULE__, :current_key_id)
  end

  @doc """
  Force key rotation (for testing or manual rotation).
  """
  @spec rotate_keys() :: :ok
  def rotate_keys do
    GenServer.call(__MODULE__, :rotate_keys)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("[Crown] Starting Signing Service...")

    # Ensure key storage directory exists
    File.mkdir_p!(@key_storage_path)

    # Load or generate initial keypair
    state = load_or_generate_keypair()

    # Schedule periodic key rotation check
    schedule_rotation_check()

    Logger.info("[Crown] Signing Service started with key_id=#{state.current_key_id}")

    {:ok, state}
  end

  @impl true
  def handle_call({:sign_event, event_hash}, _from, state) do
    try do
      # Sign with Ed25519 private key
      jwk = state.current_keypair.private
      {_, jws} = JWS.sign(jwk, event_hash, %{"alg" => "EdDSA"})
      {_, signature} = JWS.compact(jws)

      {:reply, {:ok, signature, state.current_key_id}, state}
    rescue
      error ->
        Logger.error("[Crown] Signature generation failed: #{inspect(error)}")
        {:reply, {:error, :signature_failed}, state}
    end
  end

  @impl true
  def handle_call({:verify_signature, event_hash, signature, key_id}, _from, state) do
    case Map.get(state.keypairs, key_id) do
      nil ->
        {:reply, {:error, :unknown_key_id}, state}

      keypair ->
        try do
          jwk = keypair.public

          case JWS.verify_strict(jwk, ["EdDSA"], signature) do
            {true, payload, _jws} ->
              # Signature is valid, payload is the original signed data
              if payload == event_hash do
                {:reply, :ok, state}
              else
                {:reply, {:error, :payload_mismatch}, state}
              end

            {false, _, _} ->
              {:reply, {:error, :invalid_signature}, state}
          end
        rescue
          error ->
            Logger.error("[Crown] Signature verification failed: #{inspect(error)}")
            {:reply, {:error, :verification_failed}, state}
        end
    end
  end

  @impl true
  def handle_call(:current_key_id, _from, state) do
    {:reply, state.current_key_id, state}
  end

  @impl true
  def handle_call(:rotate_keys, _from, state) do
    Logger.info("[Crown] Manual key rotation triggered")
    new_state = perform_key_rotation(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:check_rotation, state) do
    # Check if rotation is due
    days_since_creation = DateTime.diff(DateTime.utc_now(), state.created_at, :day)

    new_state =
      if days_since_creation >= @key_rotation_days do
        Logger.info("[Crown] Automatic key rotation due (#{days_since_creation} days)")
        perform_key_rotation(state)
      else
        state
      end

    # Schedule next check (daily)
    schedule_rotation_check()

    {:noreply, new_state}
  end

  # Private Functions

  defp load_or_generate_keypair do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    key_id = "crown-key-#{timestamp}"
    key_file = Path.join(@key_storage_path, "#{key_id}.json")

    keypair =
      if File.exists?(key_file) do
        Logger.info("[Crown] Loading existing keypair: #{key_id}")
        load_keypair(key_file)
      else
        Logger.info("[Crown] Generating new Ed25519 keypair: #{key_id}")
        keypair = generate_ed25519_keypair()
        save_keypair(key_file, keypair)
        keypair
      end

    %{
      current_key_id: key_id,
      current_keypair: keypair,
      keypairs: %{key_id => keypair},
      created_at: DateTime.utc_now()
    }
  end

  defp generate_ed25519_keypair do
    # Generate Ed25519 keypair using JOSE
    jwk_private = JWK.generate_key({:okp, :Ed25519})
    jwk_public = JWK.to_public(jwk_private)

    %{private: jwk_private, public: jwk_public}
  end

  defp save_keypair(file_path, keypair) do
    # Export keys to JSON
    {_, private_map} = JWK.to_map(keypair.private)
    {_, public_map} = JWK.to_map(keypair.public)

    private_json = Jason.encode!(private_map)
    public_json = Jason.encode!(public_map)

    data = %{
      private: private_json,
      public: public_json,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(file_path, Jason.encode!(data, pretty: true))
    Logger.info("[Crown] Saved keypair to #{file_path}")
  end

  defp load_keypair(file_path) do
    data = File.read!(file_path) |> Jason.decode!()

    private_jwk = data["private"] |> Jason.decode!() |> JWK.from_map()
    public_jwk = data["public"] |> Jason.decode!() |> JWK.from_map()

    %{private: private_jwk, public: public_jwk}
  end

  defp perform_key_rotation(state) do
    # Generate new keypair with microsecond timestamp to ensure uniqueness
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    new_key_id = "crown-key-#{timestamp}"
    new_keypair = generate_ed25519_keypair()

    # Save new keypair to disk
    key_file = Path.join(@key_storage_path, "#{new_key_id}.json")
    save_keypair(key_file, new_keypair)

    # Retain old keypairs for verification (keep last 3 rotations)
    all_keypairs = Map.put(state.keypairs, new_key_id, new_keypair)

    pruned_keypairs =
      if map_size(all_keypairs) > 3 do
        # Keep only most recent 3 keys
        all_keypairs
        |> Enum.sort_by(fn {key_id, _} -> key_id end, :desc)
        |> Enum.take(3)
        |> Map.new()
      else
        all_keypairs
      end

    Logger.info("[Crown] Key rotation complete: #{state.current_key_id} → #{new_key_id}")
    Logger.info("[Crown] Active keypairs: #{map_size(pruned_keypairs)}")

    %{
      state
      | current_key_id: new_key_id,
        current_keypair: new_keypair,
        keypairs: pruned_keypairs,
        created_at: DateTime.utc_now()
    }
  end

  defp schedule_rotation_check do
    # Check rotation daily
    Process.send_after(self(), :check_rotation, :timer.hours(24))
  end
end
