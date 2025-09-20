defmodule Thunderline.Flow.Sink do
  @moduledoc """
  Unified Sink behaviour for DAG outputs (Postgres, Vector store, MCP, external bridges).
  """
  alias Thunderline.Event
  @callback consume(Event.t()) :: :ok | {:error, term()}
  @callback name() :: atom()
end
