defmodule Thunderline.Thunderbolt.Cerebros.Artifacts do
  @moduledoc """
  Load and (eventually) persist Cerebros artifacts.
  Current format: JSON file produced by SimpleSearch.
  Future: add model param binary + preprocessing pipeline snapshot.
  """

  @type artifact :: map()

  @doc "Load a JSON artifact returning {:ok, artifact} or {:error, reason}."
  def load(path) when is_binary(path) do
    with true <- File.exists?(path) or {:error, :enoent},
         {:ok, bin} <- File.read(path),
         {:ok, data} <- Jason.decode(bin) do
      {:ok, data}
    else
      false -> {:error, :enoent}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  @doc "Stub prediction helper until real model loading implemented."
  def predict_stub(%{"spec" => spec}, samples) when is_list(samples) do
    %{spec_id: spec["id"], count: length(samples), predictions: Enum.map(samples, fn _ -> :stub end)}
  end
  def predict_stub(%{spec: spec}, samples) when is_list(samples) do
    %{spec_id: spec[:id], count: length(samples), predictions: Enum.map(samples, fn _ -> :stub end)}
  end

  def persist(_artifact), do: :ok
end
