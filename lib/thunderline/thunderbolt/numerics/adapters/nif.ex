defmodule Thunderline.Thunderbolt.Numerics.Adapters.NIF do
  @behaviour Thunderline.Thunderbolt.Numerics
  alias Thunderline.Thunderbolt.Numerics.Native

  @impl true
  def gemm_fp16_acc32(a, b, opts) do
    m = Keyword.fetch!(opts, :m)
    n = Keyword.fetch!(opts, :n)
    k = Keyword.fetch!(opts, :k)

    try do
      {:ok, Native.gemm_fp16_acc32(a, b, m, n, k)}
    rescue
      e -> {:error, {:nif_error, e}}
    catch
      :exit, reason -> {:error, {:nif_exit, reason}}
      :throw, reason -> {:error, {:nif_throw, reason}}
    end
  end
end
