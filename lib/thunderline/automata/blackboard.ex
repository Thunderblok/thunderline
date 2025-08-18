defmodule Thunderline.Automata.Blackboard do
  @moduledoc """
  Deprecated compatibility module.
  The canonical implementation lives at `Thunderline.Thunderbolt.Automata.Blackboard`.

  This wrapper is NOT supervised directly anymore; supervision tree uses the
  canonical module. Remove usages of this namespace before v0.7.0.
  """

  @deprecated "Use Thunderline.Thunderbolt.Automata.Blackboard"
  defdelegate put(key, value, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate fetch(key, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate get(key, default \\ nil, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate keys(opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate snapshot(scope \\ :global), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate subscribe(), to: Thunderline.Thunderbolt.Automata.Blackboard
end
