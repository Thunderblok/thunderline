defmodule Thunderline.Thunderbolt.Numerics.Native do
  @moduledoc """
  NIF glue for Rust implementation.
  """
  # Temporarily disabled for development
  # use Rustler, otp_app: :thunderline, crate: "cerebros_numerics"

  @doc """
  GEMM FP16 with FP32 accumulation.
  Arguments:
    - a :: binary (FP16 row-major, m×k)
    - b :: binary (FP16 row-major, k×n)
    - m, n, k :: positive integers (dimensions)
  Returns:
    - binary FP16 row-major (m×n)
  """
  def gemm_fp16_acc32(_a, _b, _m, _n, _k), do: {:error, :nif_disabled}
end
