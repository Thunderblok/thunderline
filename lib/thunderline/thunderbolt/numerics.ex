defmodule Thunderline.Thunderbolt.Numerics do
  @moduledoc """
  Thin façade for matrix operations (GEMM FP16 acc32) with pluggable backends.
  Configure default adapter via :thunderline, :numerics_adapter.
  """
  @callback gemm_fp16_acc32(any(), any(), Keyword.t()) :: {:ok, any()} | {:error, term()}

  @spec gemm_fp16_acc32(any(), any(), Keyword.t()) :: {:ok, any()} | {:error, term()}
  def gemm_fp16_acc32(a, b, opts \\ []) do
    adapter().gemm_fp16_acc32(a, b, opts)
  end

  defp adapter do
    Application.get_env(
      :thunderline,
      :numerics_adapter,
      Thunderline.Thunderbolt.Numerics.Adapters.ElixirFallback
    )
  end
end
