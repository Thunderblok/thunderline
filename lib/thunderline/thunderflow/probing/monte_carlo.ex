defmodule Thunderline.Thunderflow.Probing.MonteCarlo do
  @moduledoc "Monte Carlo first-word approximate distribution + JS divergence utilities."

  def first_word(text) do
    case Regex.run(~r/^\s*([\w\-'\"]+)/u, to_string(text) || "") do
      [_, w] -> String.downcase(String.trim_leading(w, "'"))
      _ -> "<empty>"
    end
  end

  def distribution(fun, prompt, samples) do
    counts = Enum.reduce(1..samples, %{}, fn _, acc ->
      {:ok, text} = fun.(prompt)
      w = first_word(text)
      Map.update(acc, w, 1, &(&1 + 1))
    end)
    total = Enum.reduce(counts, 0, fn {_k, v}, a -> a + v end)
    for {k, v} <- counts, into: %{}, do: {k, v / total}
  end

  def js_divergence(p, q) do
    keys = Map.keys(p) ++ Map.keys(q) |> Enum.uniq()
    pts = Enum.map(keys, &Map.get(p, &1, 0.0))
    qts = Enum.map(keys, &Map.get(q, &1, 0.0))
    m = Enum.zip(pts, qts) |> Enum.map(fn {a, b} -> (a + b) / 2 end)
    0.5 * kl(pts, m) + 0.5 * kl(qts, m)
  end

  def topk_overlap(p, q, k \\ 10) do
    top = p |> Enum.sort_by(fn {_k, v} -> -v end) |> Enum.take(k) |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    topq = q |> Enum.sort_by(fn {_k, v} -> -v end) |> Enum.take(k) |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    inter = MapSet.intersection(top, topq) |> MapSet.size()
    union = MapSet.union(top, topq) |> MapSet.size()
    inter / max(1, union)
  end

  defp kl(a, b) do
    Enum.zip(a, b)
    |> Enum.reduce(0.0, fn {x, y}, acc ->
      x = if x <= 0.0, do: 1.0e-12, else: x
      y = if y <= 0.0, do: 1.0e-12, else: y
      acc + x * (:math.log(x) - :math.log(y))
    end)
  end
end
