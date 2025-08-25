defmodule Thunderline.Log.NDJSON do
  @moduledoc "Append-only NDJSON writer with persistent path."
  use GenServer

  def start_link(opts) do
    path = Keyword.get(opts, :path, "logs/probe.ndjson")
    File.mkdir_p!(Path.dirname(path))
    :persistent_term.put({__MODULE__, :path}, path)
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(s), do: {:ok, s}

  def write(map) when is_map(map) do
    path = :persistent_term.get({__MODULE__, :path}, "logs/probe.ndjson")
    ts_map = Map.put(map, :timestamp, DateTime.utc_now())
    File.write!(path, Jason.encode!(ts_map) <> "\n", [:append])
    :ok
  end
end
