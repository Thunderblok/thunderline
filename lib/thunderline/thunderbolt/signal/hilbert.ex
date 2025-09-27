defmodule Thunderline.Thunderbolt.Signal.Hilbert do
  @moduledoc "Sliding FIR Hilbert transformer for instantaneous analytic phase on a scalar signal. (migrated from Thunderline.Current.Hilbert)"
  @type t :: %__MODULE__{taps: tuple(), buf: tuple(), idx: non_neg_integer(), l: pos_integer()}
  defstruct taps: {}, buf: {}, idx: 0, l: 63
  @pi :math.pi()
  def new(l \\ 63) when is_integer(l) and rem(l, 2) == 1 and l > 3 do
    taps = taps(l)
    buf = List.duplicate(0.0, l) |> List.to_tuple()
    %__MODULE__{taps: taps, buf: buf, idx: 0, l: l}
  end

  def step(%__MODULE__{taps: taps, buf: buf, idx: idx, l: l} = h, x) when is_number(x) do
    buf1 = put_elem(buf, idx, x)

    acc =
      0..(l - 1)
      |> Enum.reduce(0.0, fn k, a -> a + elem(taps, k) * elem(buf1, rem(idx - k + l, l)) end)

    phi = :math.atan2(acc, x)
    # Normalize phase to [0,1). Float.mod/2 deprecated; emulate with remainder.
    raw = (phi + @pi) / (2.0 * @pi)
    phi_norm = raw - :math.floor(raw)
    idx1 = rem(idx + 1, l)
    {%__MODULE__{h | buf: buf1, idx: idx1}, phi_norm}
  end

  defp taps(l) do
    m = (l - 1) / 2

    0..(l - 1)
    |> Enum.map(fn k ->
      n = k - m

      cond do
        n == 0 -> 0.0
        rem(round(n), 2) == 0 -> 0.0
        true -> 2.0 / (@pi * n)
      end
    end)
    |> window_hamming(l)
    |> List.to_tuple()
  end

  defp window_hamming(h, l) do
    0..(l - 1)
    |> Enum.map(fn k ->
      w = 0.54 - 0.46 * :math.cos(2.0 * @pi * k / (l - 1))
      Enum.at(h, k) * w
    end)
  end
end
