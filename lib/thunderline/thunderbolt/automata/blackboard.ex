defmodule Thunderline.Thunderbolt.Automata.Blackboard do
  @moduledoc """
  Legacy Automata Blackboard (deprecated).

  All functionality has migrated to `Thunderline.Thunderflow.Blackboard`.
  This module delegates for backward compatibility but should not be started
  or referenced directly. Will be removed in a future WARHORSE phase.
  """
  @deprecated "Use Thunderline.Thunderflow.Blackboard instead"
  alias Thunderline.Thunderflow.Blackboard, as: FlowBlackboard

  @spec put(term(), term(), keyword()) :: :ok
  def put(k, v, opts \\ []), do: FlowBlackboard.put(k, v, opts)
  @spec fetch(term(), keyword()) :: {:ok, term()} | :error
  def fetch(k, opts \\ []), do: FlowBlackboard.fetch(k, opts)
  def get(k, d \\ nil, opts \\ []), do: FlowBlackboard.get(k, d, opts)
  def keys(opts \\ []), do: FlowBlackboard.keys(opts)
  def snapshot(scope \\ :global), do: FlowBlackboard.snapshot(scope)
  def subscribe, do: FlowBlackboard.subscribe()
end
