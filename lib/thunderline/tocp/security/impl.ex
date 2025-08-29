defmodule Thunderline.TOCP.Security.Impl do
  @moduledoc """
  Security implementation scaffold.

  Provides minimal Ed25519 signing/verification & replay window tracking behind
  feature controls. Real crypto libs (enacl/libsodium) will replace the stub
  functions. Replay window uses ETS for O(1) membership and periodic pruning.
  """
  require Logger

  @behaviour Thunderline.TOCP.Security

  @table :tocp_replay_window

  # Public API (behaviour callbacks)
  @impl true
  def sign(_key_id, payload) when is_binary(payload) do
    {jwk, pub} = ephemeral_jwk()
    sig = JOSE.JWS.sign(jwk, payload, %{"alg" => "EdDSA"}) |> elem(1)
    {:ok, {pub, sig}}
  end

  @impl true
  def verify(_key_id, payload, {pub, sig}) do
    jwk = JOSE.JWK.from(public_key: pub)
    case JOSE.JWS.verify(jwk, sig) do
      {true, ^payload, _jws} -> :ok
      _ ->
        Thunderline.TOCP.Telemetry.emit(:security_sig_fail, %{count: 1}, %{peer: Base.encode16(pub)})
        {:error, :invalid_signature}
    end
  end

  @impl true
  def replay_seen?(key_id, mid, ts_ms)
      when is_binary(key_id) and is_binary(mid) and is_integer(ts_ms) do
    ensure_table()
    conf = Thunderline.TOCP.Config.get()
    skew = conf.replay.skew_ms
    now = system_time_ms()

    if ts_ms < now - skew do
      Thunderline.TOCP.Telemetry.emit(:security_replay_drop, %{count: 1}, %{peer: key_id, mid: mid, reason: :stale})
      true
    else
      entry = {key_id, mid}
      case :ets.lookup(@table, entry) do
        [] ->
          :ets.insert(@table, {entry, ts_ms})
          false
        _ ->
          Thunderline.TOCP.Telemetry.emit(:security_replay_drop, %{count: 1}, %{peer: key_id, mid: mid, reason: :duplicate})
          true
      end
    end
  end

  # Init helper (idempotent)
  def ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
        :ok
      _ -> :ok
    end
  end

  # Periodic pruning (manual call for now, future: scheduled Task)
  def prune_expired do
    ensure_table()
    conf = Thunderline.TOCP.Config.get()
    skew = conf.replay.skew_ms
    cutoff = system_time_ms() - skew
    for { {key_id, mid} = k, ts } <- :ets.tab2list(@table), ts < cutoff do
      :ets.delete(@table, k)
    end
    :ok
  end

  def system_time_ms, do: System.system_time(:millisecond)

  # Placeholder ephemeral keypair (MVP). Future: load from Gate / keystore.
  defp ephemeral_jwk do
    case :persistent_term.get({__MODULE__, :jwk}, :undefined) do
      :undefined ->
        jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
        pub = jwk |> JOSE.JWK.to_public()
        :persistent_term.put({__MODULE__, :jwk}, {jwk, pub})
        {jwk, pub}
      pair -> pair
    end
  end
end
