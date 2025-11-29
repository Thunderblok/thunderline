defmodule Thunderline.Thunderflow.Observability.NDJSON do
  @moduledoc """
  Canonical NDJSON writer (migrated from Thunderline.Log.NDJSON).

  Provides append-only JSONL logging for high-volume observability events.
  Old module remains as a deprecated delegate until removal window closes.
  """
  use GenServer

  alias __MODULE__, as: NDJSON

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(opts) do
    path = Keyword.get(opts, :path, "log/events.ndjson")
    File.mkdir_p!(Path.dirname(path))
    :persistent_term.put({NDJSON, :path}, path)
    {:ok, %{}}
  end

  def write(map) when is_map(map) do
    path = :persistent_term.get({NDJSON, :path}, "log/events.ndjson")
    ts_map = Map.put(map, :timestamp, DateTime.utc_now())
    File.write!(path, Jason.encode!(ts_map) <> "\n", [:append])
    :ok
  end
end
