defmodule Thunderline.Thunderlink.Presence.Policy do
  @moduledoc """
  Compatibility shim delegating to `Thunderline.Thundergate.Policies.Presence`.

  ThunderLink no longer owns policy logic; guardrails expect future callers to
  reach into Gate directly. New code should alias
  `Thunderline.Thundergate.Policies.Presence` instead of this module.
  """

  @deprecated "Presence policies now live in Thundergate. Use Thunderline.Thundergate.Policies.Presence instead."
  def decide(action, resource, actor_ctx) do
    Thunderline.Thundergate.Policies.Presence.decide(action, resource, actor_ctx)
  end
end
