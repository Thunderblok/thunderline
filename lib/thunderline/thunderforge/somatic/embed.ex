defmodule Thunderline.Thunderforge.Somatic.Embed do
  @moduledoc """
  Somatic Embed - Text embedding and similarity for signal processing.

  Provides vector embeddings and cosine similarity calculations for
  the signal pipeline's recurrence detection and velocity calculations.

  ## Future Implementation

  This module is a stub that will integrate with:
  - Bumblebee embedding models (BERT, sentence-transformers)
  - ONNX runtime for efficient inference
  - Cached embeddings for common tokens

  ## Usage

      vec = Thunderline.Thunderforge.Somatic.Embed.vec("hello world")
      # => [0.1, 0.2, 0.3, ...]

      similarity = Thunderline.Thunderforge.Somatic.Embed.cosine(vec1, vec2)
      # => 0.95
  """

  @doc """
  Generate an embedding vector for a string.

  Returns a list of floats representing the semantic embedding.
  Currently uses a simple byte-based fallback; future versions
  will use actual embedding models.

  ## Examples

      iex> vec = Thunderline.Thunderforge.Somatic.Embed.vec("hello")
      iex> is_list(vec)
      true
  """
  @spec vec(String.t()) :: [float()]
  def vec(string) when is_binary(string) do
    # Stub implementation using byte-based fallback
    # Future: integrate with Bumblebee embedding models
    string
    |> :binary.bin_to_list()
    |> Enum.map(&(&1 / 255.0))
  end

  def vec(_), do: []

  @doc """
  Calculate cosine similarity between two embedding vectors.

  Returns a value between -1.0 and 1.0, where:
  - 1.0 = identical direction
  - 0.0 = orthogonal
  - -1.0 = opposite direction

  ## Examples

      iex> v1 = [1.0, 0.0, 0.0]
      iex> v2 = [1.0, 0.0, 0.0]
      iex> Thunderline.Thunderforge.Somatic.Embed.cosine(v1, v2)
      1.0

      iex> v1 = [1.0, 0.0]
      iex> v2 = [0.0, 1.0]
      iex> Thunderline.Thunderforge.Somatic.Embed.cosine(v1, v2)
      0.0
  """
  @spec cosine([float()], [float()]) :: float()
  def cosine(lhs, rhs) when is_list(lhs) and is_list(rhs) do
    {aligned_lhs, aligned_rhs} = align_vectors(lhs, rhs)

    dot =
      Enum.zip(aligned_lhs, aligned_rhs)
      |> Enum.reduce(0.0, fn {l, r}, acc -> acc + l * r end)

    lhs_mag = magnitude(aligned_lhs)
    rhs_mag = magnitude(aligned_rhs)

    denom = lhs_mag * rhs_mag

    if denom == 0.0 do
      0.0
    else
      dot / denom
    end
  end

  def cosine(_, _), do: 0.0

  # Private helpers

  defp align_vectors(lhs, rhs) do
    size = max(length(lhs), length(rhs))
    {pad(lhs, size), pad(rhs, size)}
  end

  defp pad(list, size) when length(list) >= size, do: Enum.take(list, size)
  defp pad(list, size), do: list ++ List.duplicate(0.0, size - length(list))

  defp magnitude(list) do
    list
    |> Enum.reduce(0.0, fn value, acc -> acc + value * value end)
    |> :math.sqrt()
  end
end
