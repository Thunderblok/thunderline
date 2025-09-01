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
  def put(k, v, opts \\ []) do
    :telemetry.execute([:thunderline, :blackboard, :legacy_call], %{count: 1}, %{fun: :put})
    FlowBlackboard.put(k, v, opts)
  end
  @spec fetch(term(), keyword()) :: {:ok, term()} | :error
  def fetch(k, opts \\ []) do
    :telemetry.execute([:thunderline, :blackboard, :legacy_call], %{count: 1}, %{fun: :fetch})
    FlowBlackboard.fetch(k, opts)
  end
  def get(k, d \\ nil, opts \\ []) do
    :telemetry.execute([:thunderline, :blackboard, :legacy_call], %{count: 1}, %{fun: :get})
    FlowBlackboard.get(k, d, opts)
  end
  def keys(opts \\ []) do
    :telemetry.execute([:thunderline, :blackboard, :legacy_call], %{count: 1}, %{fun: :keys})
    FlowBlackboard.keys(opts)
  end
  def snapshot(scope \\ :global) do
    :telemetry.execute([:thunderline, :blackboard, :legacy_call], %{count: 1}, %{fun: :snapshot})
    FlowBlackboard.snapshot(scope)
  end
  def subscribe do
    :telemetry.execute([:thunderline, :blackboard, :legacy_call], %{count: 1}, %{fun: :subscribe})
    FlowBlackboard.subscribe()
  end
end
