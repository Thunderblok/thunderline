defmodule Thunderline.UUID do
  @moduledoc """
  RFC 9562 UUIDv7 generator (time-ordered) with fallback to v4 on error.

  We implement v7 manually because the bundled `:elixir_uuid` version lacks `UUID.uuid7/0`.
  Layout (big-endian):
    48 bits unix time (ms)
    4 bits version (0b0111)
    12 bits rand_a
    2 bits variant (10)
    62 bits rand_b
  """
  use Bitwise

  @spec v7() :: String.t()
  def v7 do
    unix_ms = System.system_time(:millisecond) &&& 0xFFFFFFFFFFFF
    rand_a_12 = :crypto.strong_rand_bytes(2) |> :binary.decode_unsigned() &&& 0x0FFF
    rand_b_62 = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned() &&& 0x3FFFFFFFFFFFFFFF

    version_and_rand_a = (0x7 <<< 12) ||| rand_a_12
    high14 = (rand_b_62 >>> 48) &&& 0x3FFF
    variant_and_rand_b_high = (0b10 <<< 14) ||| high14
    rand_b_low_48 = rand_b_62 &&& 0xFFFFFFFFFFFF
    rand_b_mid_16 = (rand_b_low_48 >>> 32) &&& 0xFFFF
    rand_b_low_32 = rand_b_low_48 &&& 0xFFFFFFFF

    binary = <<unix_ms::unsigned-big-48, version_and_rand_a::unsigned-big-16, variant_and_rand_b_high::unsigned-big-16, rand_b_mid_16::unsigned-big-16, rand_b_low_32::unsigned-big-32>>
    <<p0::unsigned-big-32, p1::unsigned-big-16, p2::unsigned-big-16, p3::unsigned-big-16, p4::unsigned-big-48>> = binary
    to_hex(p0, 8) <> "-" <> to_hex(p1, 4) <> "-" <> to_hex(p2, 4) <> "-" <> to_hex(p3, 4) <> "-" <> to_hex(p4, 12)
  rescue
    _ -> UUID.uuid4() # fallback
  end

  defp to_hex(int, digits) do
    int
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(digits, "0")
  end
end
