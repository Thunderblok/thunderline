defmodule Thunderline.Thunderflow.Probing.Metrics do
  @moduledoc """
  Text surface metrics: entropy, lexical diversity, repetition; migrated from Raincatcher.

  All functions are pure and safe for synchronous inline usage in Oban workers.
  """

  @spec char_entropy(String.t() | nil) :: float()
  def char_entropy(text) when text in [nil, ""], do: 0.0

  def char_entropy(text) do
    len = String.length(text)

    text
    |> String.graphemes()
    |> Enum.frequencies()
    |> Enum.reduce(0.0, fn {_c, v}, acc ->
      p = v / len
      acc - p * :math.log(p + 1.0e-12)
    end)
  end

  @spec lexical_diversity(String.t() | nil) :: float()
  def lexical_diversity(text) when text in [nil, ""], do: 0.0

  def lexical_diversity(text) do
    toks = String.split(text)
    uniq = toks |> MapSet.new() |> MapSet.size()
    if toks == [], do: 0.0, else: uniq / max(1, length(toks))
  end

  @spec repetition_ratio(String.t() | nil) :: float()
  def repetition_ratio(text) when text in [nil, ""], do: 0.0

  def repetition_ratio(text) do
    toks = String.split(text)

    case toks do
      [] ->
        0.0

      [_] ->
        0.0

      _ ->
        {repeats, total} =
          toks
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.reduce({0, 0}, fn [a, b], {r, t} -> {r + if(a == b, do: 1, else: 0), t + 1} end)

        repeats / max(1, total)
    end
  end
end
