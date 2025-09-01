defmodule Thunderline.Thundergate.ActorContext do
  @moduledoc """
  Capability context (signed) issued by Gate.

  Fields:
    :actor_id, :tenant, :scopes (list), :exp (unix seconds), :correlation_id, :sig

  Signatures: Ed25519 via JOSE (keypair loaded from config or generated ephemeral in dev).

  Token Format (Phase 1): the JWS compact form (ctx.sig) returned by `sign/1`.
  The struct itself is not directly serialized to external callers; instead we
  provide `token/1` for extraction and `from_token/1` (verify) for inbound.
  Future: evolve to include versioned header (kid) and rotate keys.
  """
  @enforce_keys [:actor_id, :tenant, :scopes, :exp, :correlation_id]
  defstruct [:actor_id, :tenant, :scopes, :exp, :correlation_id, :sig]

  alias JOSE.{JWK, JWS}

  @type t :: %__MODULE__{
          actor_id: String.t(),
          tenant: String.t(),
          scopes: [String.t()],
          exp: non_neg_integer(),
          correlation_id: String.t(),
          sig: binary() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) do
    struct!(__MODULE__, attrs)
  end

  @spec sign(t()) :: t()
  def sign(%__MODULE__{} = ctx) do
    jwk = signing_key()
    payload = :erlang.term_to_binary(Map.drop(Map.from_struct(ctx), [:sig]))
    {_, jws} = JWS.sign(jwk, payload, %{"alg" => "EdDSA"})
    sig = elem(JWS.compact(jws), 1)
    %{ctx | sig: sig}
  end

  @doc """
  Return the bearer token (compact JWS) for a signed context.

  Returns nil if ctx has not been signed yet.
  """
  @spec token(t()) :: binary() | nil
  def token(%__MODULE__{sig: sig}), do: sig

  @doc """
  Verify a compact JWS token and return the reconstructed ActorContext.

  This is an alias of `verify/1` for semantic clarity in plugs.
  """
  @spec from_token(binary()) :: {:ok, t()} | {:error, term()}
  def from_token(token), do: verify(token)

  @spec verify(binary()) :: {:ok, t()} | {:error, term()}
  def verify(sig) when is_binary(sig) do
    jwk = public_key()
    now = System.os_time(:second)
    with {true, jws, _} <- JWS.verify_strict(jwk, ["EdDSA"], sig),
         {:ok, payload} <- decode_payload(jws),
         {:ok, ctx} <- to_struct(payload) do
      cond do
        ctx.exp <= now -> {:error, :expired}
        true -> {:ok, ctx}
      end
    else
      false -> {:error, :invalid_signature}
      {:error, _} = e -> e
    end
  end

  defp decode_payload(jws) do
    case JWS.peek_payload(jws) do
      {:binary, bin} -> {:ok, :erlang.binary_to_term(bin)}
      _ -> {:error, :bad_payload}
    end
  rescue
    _ -> {:error, :decode_failed}
  end

  defp to_struct(map) when is_map(map) do
    try do
      {:ok, struct(__MODULE__, Map.put(map, :sig, nil))}
    rescue
      _ -> {:error, :struct_cast_failed}
    end
  end

  defp signing_key do
    {priv, _pub} = keypair()
    priv
  end

  defp public_key do
    {_priv, pub} = keypair()
    pub
  end

  defp keypair do
    case Application.get_env(:thunderline, :gate_keys) do
      %{jwk_ed25519_priv: priv_map, jwk_ed25519_pub: pub_map} -> {JWK.from_map(priv_map), JWK.from_map(pub_map)}
      _ -> ephemeral()
    end
  end

  defp ephemeral do
    jwk = JWK.generate_key({:okp, :Ed25519})
    {jwk, jwk |> JWK.to_public()}
  end
end
