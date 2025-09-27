defmodule Thunderline.Thundergate.Policies.Presence do
  @moduledoc """
  Authorization rules for ThunderLink presence operations. Enforces deny-by-default
  and delegates allow decisions to actor capability scopes or controlled overrides.

  Telemetry: every decision emits `[:thunderline, :link, :presence, :decision]` with the
  duration, decision, and actor metadata so downstream observers retain the existing
  signal even though the policy now lives in Thundergate.
  """
  alias Thunderline.Thundergate.ActorContext

  @type decision :: :allow | :deny
  @type reason :: atom()
  @type resource :: {:channel, String.t()} | {:community, String.t()} | {:global, :presence}
  @type action :: :join | :leave | :send | :watch

  @allow_env_key :thunderline_link_presence_allow

  @spec decide(action(), resource(), ActorContext.t() | nil) :: {decision(), reason()}
  def decide(action, resource, %ActorContext{} = ctx) do
    start = System.monotonic_time()
    result = do_decide(action, resource, ctx)
    publish_telemetry(start, action, resource, ctx, result)
    result
  end

  def decide(_action, _resource, nil), do: {:deny, :missing_actor}

  defp do_decide(:leave, _resource, _ctx), do: {:allow, :graceful_disconnect}

  defp do_decide(action, resource, ctx) do
    scope = scope_for(resource, action)

    cond do
      scope_allowed?(scope, ctx.scopes) -> {:allow, :scope_match}
      env_allow?(resource) -> {:allow, :env_allow}
      true -> {:deny, :no_rule}
    end
  end

  defp scope_for({:channel, id}, action), do: "link:channel:#{id}:#{action}"
  defp scope_for({:community, id}, action), do: "link:community:#{id}:#{action}"
  defp scope_for({:global, :presence}, action), do: "link:global:presence:#{action}"

  defp scope_allowed?(scope, scopes) when is_binary(scope),
    do: scope in scopes or wildcard_match?(scope, scopes)

  defp wildcard_match?(scope, scopes) do
    parts = String.split(scope, ":")

    Enum.any?(scopes, fn candidate ->
      cparts = String.split(candidate, ":")

      length(cparts) == length(parts) and
        Enum.zip(parts, cparts)
        |> Enum.all?(fn {a, b} -> b == "*" or a == b end)
    end)
  end

  defp env_allow?(resource) do
    case System.get_env(env_key()) do
      nil ->
        false

      val ->
        val
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.member?(resource_key(resource))
    end
  end

  defp env_key, do: to_string(@allow_env_key)
  defp resource_key({:channel, id}), do: "channel:#{id}"
  defp resource_key({:community, id}), do: "community:#{id}"
  defp resource_key({:global, :presence}), do: "global:presence"

  defp publish_telemetry(start, action, resource, ctx, {decision, reason}) do
    duration = System.monotonic_time() - start

    meta = %{
      action: action,
      resource: resource_key(resource),
      decision: decision,
      reason: reason,
      actor: ctx && ctx.actor_id
    }

    :telemetry.execute([:thunderline, :link, :presence, :decision], %{duration: duration}, meta)
  end
end
