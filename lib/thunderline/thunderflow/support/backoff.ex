defmodule Thunderline.Thunderflow.Support.Backoff do
  @moduledoc "Backoff strategies (exp & linear w/ jitter) for Thunderflow retries."
  @min_ms 1_000
  @max_ms 300_000
  @jitter_pct 0.20
  @spec exp(pos_integer()) :: non_neg_integer()
  def exp(a) when a <= 1, do: jitter(@min_ms)

  def exp(a) do
    base = trunc(@min_ms * :math.pow(2, a - 1)) |> min(@max_ms)
    jitter(base)
  end

  @spec linear(pos_integer(), pos_integer()) :: non_neg_integer()
  def linear(a, step \\ 5_000) do
    base = max(@min_ms, a * step) |> min(@max_ms)
    jitter(base)
  end

  def jitter(delay) do
    j = round(delay * @jitter_pct)
    offset = :rand.uniform(2 * j + 1) - j - 1
    max(0, delay + offset)
  end

  def config, do: %{min_ms: @min_ms, max_ms: @max_ms, jitter_pct: @jitter_pct}
end
