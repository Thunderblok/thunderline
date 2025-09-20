defmodule Thunderline.Flow.Producer do
  @moduledoc """
  Unified Producer behaviour for Event DAG sources (HTTP, WS, timers, DB triggers).

  Implementations must emit `%Thunderline.Event{}` structs and instrument with telemetry
  events under [:thunderline, :flow, :stage, :producer].
  """
  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback name() :: atom()
  @callback partitions() :: pos_integer()
  @callback produce() :: :ok | {:error, term()}
end
