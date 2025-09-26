defmodule Thunderline.Thunderlink.Presence.Enforcer do
  @moduledoc """
  Presence enforcement macro ensuring all Link mutations pass through
  `Thunderline.Thunderlink.Presence.Policy.decide/3`.

  Usage:

      import Thunderline.Thunderlink.Presence.Enforcer, only: [with_presence: 4]
      with_presence :send, {:channel, channel.id}, actor_ctx do
        send_message(...)
      end

  On denial returns {:error, Ash.Error.Forbidden.t()} so callers can unify error handling.
  Emits unified telemetry `[:thunderline,:link,:presence,:blocked_enforcer]` for any denial.
  """
  alias Thunderline.Thunderlink.Presence.Policy

  # 3-arity form returns {:ok, meta} | {:error, Ash.Error.Forbidden.t()}
  # Use this when you only need the decision result, not to wrap a block.
  defmacro with_presence(action, resource, actor_ctx) do
    quote do
      case Policy.decide(unquote(action), unquote(resource), unquote(actor_ctx)) do
        {:allow, meta} -> {:ok, meta}
        {:deny, reason} ->
          :telemetry.execute([
            :thunderline, :link, :presence, :blocked_enforcer
          ], %{count: 1}, %{action: unquote(action), resource: unquote(resource), reason: reason})
          {:error, Ash.Error.Forbidden.exception(reason: inspect(reason))}
      end
    end
  end

  defmacro with_presence(action, resource, actor_ctx, do: block) do
    quote do
      case Policy.decide(unquote(action), unquote(resource), unquote(actor_ctx)) do
        {:allow, _meta} -> unquote(block)
        {:deny, reason} ->
          :telemetry.execute([
            :thunderline, :link, :presence, :blocked_enforcer
          ], %{count: 1}, %{action: unquote(action), resource: unquote(resource), reason: reason})
          {:error, Ash.Error.Forbidden.exception(reason: inspect(reason))}
      end
    end
  end
end
