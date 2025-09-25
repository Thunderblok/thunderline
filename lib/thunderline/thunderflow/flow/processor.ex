defmodule Thunderline.Thunderflow.Flow.Processor do
  @moduledoc """
  Unified Processor behaviour for DAG stages. Accepts `%Thunderline.Event{}` and returns
  either the same or transformed event, or :drop. Must be idempotent where configured.
  """
  alias Thunderline.Event
  @type outcome :: {:ok, Event.t()} | :drop | {:error, term()}
  @callback handle(Event.t()) :: outcome
  @callback name() :: atom()
  @callback partitions() :: pos_integer()
  @callback retry_policy() :: :idempotent | :non_idempotent
end
