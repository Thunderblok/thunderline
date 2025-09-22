defmodule Thunderline.Thunderbolt.Numerics.Adapters.ElixirFallback do
  @behaviour Thunderline.Thunderbolt.Numerics
  @moduledoc """
  Pure Elixir fallback adapter with a naive GEMM. Intended only for validation.
  """

  @impl true
  def gemm_fp16_acc32(a, b, _opts) when is_list(a) and is_list(b) do
    with {:ok, {ar, ac}} <- shape(a),
         {:ok, {br, bc}} <- shape(b),
         true <- ac == br do
      res = for i <- 0..(ar - 1) do
        for j <- 0..(bc - 1) do
          Enum.reduce(0..(ac - 1), 0.0, fn k, acc -> acc + get(a, i, k) * get(b, k, j) end)
        end
      end
      {:ok, res}
    else
      false -> {:error, :shape_mismatch}
      {:error, r} -> {:error, r}
    end
  end

  def gemm_fp16_acc32(_a, _b, _opts), do: {:error, :unsupported_input}

  defp shape(list) when is_list(list) and list != [] do
    rows = length(list)
    cols = length(hd(list))
    if Enum.all?(list, fn row -> is_list(row) and length(row) == cols end) do
      {:ok, {rows, cols}}
    else
      {:error, :ragged}
    end
  end

  defp shape(_), do: {:error, :bad_shape}
  defp get(list, i, j), do: list |> Enum.at(i) |> Enum.at(j)
end
