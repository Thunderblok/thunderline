defmodule Thunderline.Automata.Blackboard do
  @moduledoc """
  DEPRECATED alias. Moved to `Thunderline.Thunderbolt.Automata.Blackboard`.
  Will be removed after the migration window.
  """
  @deprecated "Use Thunderline.Thunderbolt.Automata.Blackboard instead"
  def start_link(opts \\ []), do: Thunderline.Thunderbolt.Automata.Blackboard.start_link(opts)
  defdelegate put(key, value, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate fetch(key, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate get(key, default \\ nil, opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate keys(opts \\ []), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate snapshot(scope \\ :global), to: Thunderline.Thunderbolt.Automata.Blackboard
  defdelegate subscribe(), to: Thunderline.Thunderbolt.Automata.Blackboard
end
