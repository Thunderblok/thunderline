defmodule Thunderline.Thundercrown.Policy do
  @moduledoc """
  Policy decision kernel (WARHORSE Phase 1).

  decide/2 returns one of:
    {:allow, meta}
    {:deny, reason}
    {:allow_with, limits}

  Inputs:
    actor_ctx: %Thundergate.ActorContext{}
    action: %{domain: atom(), resource: atom(), action: atom(), scopes: [String.t()]} (descriptor)

  Simple rule table now; future: Ash resource-driven policies.
  """
  alias Thunderline.Thundergate.ActorContext
  require Logger

  @type decision :: {:allow, map()} | {:deny, term()} | {:allow_with, map()}
  @type action_descriptor :: %{
          required(:domain) => atom(),
          required(:resource) => atom(),
          required(:action) => atom(),
          optional(:scopes) => [String.t()]
        }

  @spec decide(ActorContext.t(), action_descriptor()) :: decision()
  def decide(%ActorContext{} = ctx, %{domain: _d, resource: _r, action: _a} = descriptor) do
    start = System.monotonic_time()
    {result, meta} = eval(ctx, descriptor)
    signed = maybe_sign_verdict(ctx, descriptor, result, meta)
    emit(ctx, descriptor, signed, start)
    signed
  end

  defp eval(ctx, %{scopes: required_scopes} = _desc)
       when is_list(required_scopes) and required_scopes != [] do
    if Enum.any?(required_scopes, &scope_allows?(ctx.scopes, &1)) do
      {{:allow, %{rule: :scope_match}}, %{rule_id: :scope_match}}
    else
      {{:deny, :insufficient_scope}, %{rule_id: :scope_match}}
    end
  end

  defp eval(_ctx, _), do: {{:deny, :no_scope_specified}, %{rule_id: :no_scope_specified}}

  defp scope_allows?(scopes, required) do
    Enum.any?(scopes, fn s -> wildcard_match?(s, required) end)
  end

  defp wildcard_match?(have, required) do
    case String.split(have, ":") do
      [d, r, "*"] -> required |> String.starts_with?(d <> ":" <> r <> ":")
      _ -> have == required
    end
  end

  defp emit(ctx, descriptor, result, start) do
    duration = System.monotonic_time() - start

    meta = %{
      actor: ctx.actor_id,
      tenant: ctx.tenant,
      decision: elem(result, 0),
      domain: descriptor[:domain],
      resource: descriptor[:resource],
      action: descriptor[:action],
      verdict_id: verdict_id(result)
    }

    :telemetry.execute([:thunderline, :policy, :decision], %{duration: duration}, meta)
  end

  defp verdict_id({_, meta}) when is_map(meta), do: Map.get(meta, :verdict_id)
  defp verdict_id(_), do: nil

  defp maybe_sign_verdict(%ActorContext{} = ctx, descriptor, {status, payload}, meta) do
    case status do
      :allow -> {status, Map.put(payload, :verdict_id, sign_verdict(ctx, descriptor, meta))}
      :allow_with -> {status, Map.put(payload, :verdict_id, sign_verdict(ctx, descriptor, meta))}
      :deny -> {status, payload}
    end
  end

  defp sign_verdict(ctx, descriptor, meta) do
    base = %{
      actor: ctx.actor_id,
      tenant: ctx.tenant,
      rule: meta.rule_id,
      domain: descriptor.domain,
      resource: descriptor.resource,
      action: descriptor.action,
      ts: System.system_time(:millisecond)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(base)) |> Base.encode16(case: :lower)
  end
end
