defmodule Thunderline.Thunderflow.Observability.Drift do
  @moduledoc """
  Facade helpers for drift metric ingestion & retrieval.

  Provides a boundary-friendly API so other domains (e.g. Raincatcher pipeline,
  Cerebros demos, tests) can push embedding/time-series vectors without
  depending on PubSub topic strings.
  """
  alias Phoenix.PubSub
  @pubsub Thunderline.PubSub

  @doc """
  Ingest an embedding vector or map with :embedding key.

  Examples:
    iex> ingest_embedding([0.1, 0.2, 0.3])
    :ok
  """
  def ingest_embedding(%{embedding: _}=map), do: publish(map)
  def ingest_embedding(%{"embedding" => _}=map), do: publish(map)
  def ingest_embedding(list) when is_list(list), do: publish(%{embedding: list})
  def ingest_embedding(tuple) when is_tuple(tuple), do: publish(%{embedding: Tuple.to_list(tuple)})
  def ingest_embedding(_other), do: :ignored

  @doc """
  Return latest drift metrics snapshot from DriftMetricsProducer.
  """
  def metrics do
    Thunderline.Thunderflow.Observability.DriftMetricsProducer.current_metrics()
  end

  defp publish(payload) do
    PubSub.broadcast(@pubsub, "drift:embedding", {:timeseries_embedding, payload})
    :ok
  end
end
