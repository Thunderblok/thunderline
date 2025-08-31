defmodule Thunderline.Thunderflow.Blackboard do
  @moduledoc """
  Canonical transient blackboard facade.

  WARHORSE Phase 1: delegates to Thunderbolt.Automata.Blackboard while callers migrate.
  Future: replace underlying implementation; emit telemetry on legacy path usage.
  """
  @delegate_mod Thunderline.Thunderbolt.Automata.Blackboard

  @deprecated "Use Thunderline.Thunderflow.Blackboard (this module) instead of direct Automata.Blackboard access"
  def put(key, value, opts \\ []), do: delegate(:put, [key, value, opts])
  def fetch(key, opts \\ []), do: delegate(:fetch, [key, opts])
  def get(key, default \\ nil, opts \\ []), do: delegate(:get, [key, default, opts])
  def keys(opts \\ []), do: delegate(:keys, [opts])
  def snapshot(scope \\ :global), do: delegate(:snapshot, [scope])
  def subscribe, do: delegate(:subscribe, [])

  defp delegate(fun, args) do
    :telemetry.execute([:thunderline, :blackboard, :legacy_use], %{count: 1}, %{fun: fun})
    apply(@delegate_mod, fun, args)
  end
end
