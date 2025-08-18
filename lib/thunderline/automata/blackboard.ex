defmodule Thunderline.Automata.Blackboard do
  @moduledoc """
  Deprecated alias shim for moved module.
  Use `Thunderline.Thunderbolt.Automata.Blackboard` instead.
  Will be removed after migration window.
  """

  defdelegate start_link(opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate put(key, value, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate fetch(key, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate get(key, default \\ nil, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate keys(opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate snapshot(scope \\ :global), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate subscribe(), to: Thunderline.Thunderbolt.Automata.Blackboard
end
