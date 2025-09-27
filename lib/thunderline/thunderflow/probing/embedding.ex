defmodule Thunderline.Thunderflow.Probing.Embedding do
  @moduledoc "Hash n‑gram embedding (lightweight, locality‑insensitive) with cosine similarity."
  @default_dim 512
  @default_ngram 3

  @spec hash_embedding(String.t(), keyword()) :: {list(float()), float()}
  def hash_embedding(text, opts \\ []) do
    dim = Keyword.get(opts, :dim, @default_dim)
    n = Keyword.get(opts, :ngram, @default_ngram)
    text = to_string(text)

    text =
      if String.length(text) < n,
        do: text <> String.duplicate(" ", n - String.length(text)),
        else: text

    vec = :array.new(dim, default: 0.0)
    final = do_slide(text, n, dim, vec)
    list = :array.to_list(final)
    norm = :math.sqrt(Enum.reduce(list, 0.0, fn x, a -> a + x * x end)) + 1.0e-12
    normed = Enum.map(list, &(&1 / norm))
    {normed, norm}
  end

  defp do_slide(text, n, dim, vec) do
    limit = String.length(text) - n

    Enum.reduce(0..limit, vec, fn i, acc ->
      ngram = binary_part(text, i, n)
      h = :crypto.hash(:md5, ngram) |> :binary.decode_unsigned()
      idx = rem(h, dim)
      current = :array.get(idx, acc)
      :array.set(idx, current + 1.0, acc)
    end)
  end

  @spec cosine(list(float()), list(float())) :: float()
  def cosine(a, b) do
    dot = Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    na = :math.sqrt(Enum.reduce(a, 0.0, fn x, a -> a + x * x end)) + 1.0e-12
    nb = :math.sqrt(Enum.reduce(b, 0.0, fn x, a -> a + x * x end)) + 1.0e-12
    dot / (na * nb)
  end
end
