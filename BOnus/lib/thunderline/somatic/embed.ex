defmodule Thunderline.Somatic.Embed do
  @moduledoc """Trigram hashing embed + cosine for quick drift/recurrence."""
  @dim 512
  def vec(str) when is_binary(str) do
    bins = for <<a::utf8, b::utf8, c::utf8 <- String.downcase(str)>>, do: <<a,b,c>>
    Enum.reduce(bins, :array.new(@dim, default: 0.0), fn tri, acc ->
      h = :erlang.phash2(tri, @dim)
      :array.set(h, :array.get(h, acc) + 1.0, acc)
    end)
    |> :array.to_list()
  end

  def cosine(v1, v2) do
    {num, d1, d2} =
      Enum.zip(v1, v2)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {a,b}, {n,x,y} -> {n + a*b, x + a*a, y + b*b} end)
    if d1 == 0.0 or d2 == 0.0, do: 0.0, else: num / (:math.sqrt(d1) * :math.sqrt(d2))
  end
end
