defmodule Thunderline.Id.Generator do
  @moduledoc """
  Low-level ULID generation with timestamp and randomness control.

  This module wraps `Ecto.ULID` (from ecto_ulid_next) providing a clean interface
  for ULID generation with optional timestamp specification.

  ## ULID Structure (128 bits)

  ```
  ┌────────────────────────────────────────────────────────────────────┐
  │                      ULID (26 characters)                          │
  ├─────────────────────────────┬──────────────────────────────────────┤
  │    Timestamp (48 bits)      │        Randomness (80 bits)          │
  │    10 characters            │        16 characters                 │
  │    milliseconds since       │        cryptographically secure      │
  │    Unix epoch                │        random data                   │
  └─────────────────────────────┴──────────────────────────────────────┘
  ```

  ## Encoding

  Uses Crockford's Base32 encoding:
  - Characters: `0123456789ABCDEFGHJKMNPQRSTVWXYZ`
  - Excludes: I, L, O, U (to avoid confusion)
  - Case-insensitive (normalized to uppercase internally)

  ## Implementation Notes

  - Delegates to `Ecto.ULID.generate/1` for string ULIDs
  - Delegates to `Ecto.ULID.bingenerate/1` for binary ULIDs
  - Falls back to `Thunderline.UUID.v7/0` if ULID generation fails
  """

  alias Thunderline.Id

  @type unix_ms :: non_neg_integer()

  # Crockford Base32 alphabet (excludes I, L, O, U)
  @crockford_alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @doc """
  Generate a new ULID string using the current timestamp.

  ## Examples

      iex> id = Thunderline.Id.Generator.generate()
      iex> String.length(id)
      26
      iex> String.match?(id, ~r/^[0-9A-Z]{26}$/)
      true
  """
  @spec generate() :: Id.t()
  def generate do
    Ecto.ULID.generate()
  rescue
    # Fallback to UUIDv7 which has similar time-ordering properties
    _error -> Thunderline.UUID.v7() |> String.replace("-", "") |> encode_uuid_as_ulid()
  end

  @doc """
  Generate a ULID for a specific timestamp.

  ## Parameters

  - `datetime` - A `DateTime` struct to embed in the ULID

  ## Examples

      iex> dt = ~U[2024-01-15 12:00:00Z]
      iex> id = Thunderline.Id.Generator.generate_at(dt)
      iex> String.length(id)
      26
  """
  @spec generate_at(DateTime.t()) :: Id.t()
  def generate_at(%DateTime{} = datetime) do
    unix_ms = DateTime.to_unix(datetime, :millisecond)
    Ecto.ULID.generate(unix_ms)
  rescue
    _error ->
      # Fallback: generate with current time
      generate()
  end

  @doc """
  Generate a binary (16-byte) ULID.

  ## Examples

      iex> bin = Thunderline.Id.Generator.generate_binary()
      iex> byte_size(bin)
      16
  """
  @spec generate_binary() :: Id.ulid_binary()
  def generate_binary do
    Ecto.ULID.bingenerate()
  rescue
    _error ->
      # Fallback: generate string and convert
      generate() |> decode_to_binary()
  end

  @doc """
  Generate a ULID range for time-based queries.

  Returns `{min_ulid, max_ulid}` covering the time window.
  - `min_ulid`: timestamp = start, random bits = all zeros
  - `max_ulid`: timestamp = end, random bits = all ones

  ## Parameters

  - `start_dt` - Start of the time range (inclusive)
  - `end_dt` - End of the time range (inclusive)

  ## Examples

      iex> start = ~U[2024-01-01 00:00:00Z]
      iex> stop = ~U[2024-01-02 00:00:00Z]
      iex> {min, max} = Thunderline.Id.Generator.range(start, stop)
      iex> String.length(min)
      26

  ## Use Cases

  Time-range queries in Ash/Ecto:

      from t in Thunderbit,
        where: t.id >= ^min_ulid and t.id <= ^max_ulid

  This is more efficient than timestamp column queries when the
  primary key is a ULID, as it uses the primary index directly.
  """
  @spec range(DateTime.t(), DateTime.t()) :: {Id.t(), Id.t()}
  def range(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    start_ms = DateTime.to_unix(start_dt, :millisecond)
    end_ms = DateTime.to_unix(end_dt, :millisecond)

    # Build min ULID: timestamp with all-zero random portion
    min_ulid = build_ulid_with_random(start_ms, <<0::80>>)

    # Build max ULID: timestamp with all-one random portion
    max_ulid = build_ulid_with_random(end_ms, <<0xFFFFFFFFFFFFFFFFFFFF::80>>)

    {min_ulid, max_ulid}
  end

  # --- Private Helpers ---

  # Build a ULID from timestamp and random bytes
  @spec build_ulid_with_random(unix_ms(), <<_::80>>) :: Id.t()
  defp build_ulid_with_random(unix_ms, random_80_bits) do
    <<time_48::unsigned-big-48>> = <<unix_ms::unsigned-big-48>>
    binary = <<time_48::unsigned-big-48, random_80_bits::binary>>
    encode_binary(binary)
  end

  # Encode 16-byte binary as Crockford Base32 ULID string
  @spec encode_binary(<<_::128>>) :: Id.t()
  defp encode_binary(<<value::unsigned-big-128>>) do
    encode_base32(value, 26, [])
  end

  defp encode_base32(_value, 0, acc), do: IO.iodata_to_binary(acc)

  defp encode_base32(value, remaining, acc) do
    char_index = rem(value, 32)
    char = Enum.at(@crockford_alphabet, char_index)
    encode_base32(div(value, 32), remaining - 1, [char | acc])
  end

  # Decode ULID string to 16-byte binary
  @spec decode_to_binary(Id.t()) :: Id.ulid_binary()
  defp decode_to_binary(ulid_string) when byte_size(ulid_string) == 26 do
    value = decode_base32(ulid_string |> String.upcase() |> String.to_charlist(), 0)
    <<value::unsigned-big-128>>
  end

  defp decode_base32([], acc), do: acc

  defp decode_base32([char | rest], acc) do
    index = Enum.find_index(@crockford_alphabet, &(&1 == char)) || 0
    decode_base32(rest, acc * 32 + index)
  end

  # Convert a UUIDv7 (or v4) string to ULID-like encoding for fallback
  @spec encode_uuid_as_ulid(String.t()) :: Id.t()
  defp encode_uuid_as_ulid(hex_string) when byte_size(hex_string) == 32 do
    # Parse hex string to integer
    {value, ""} = Integer.parse(hex_string, 16)
    encode_base32(value, 26, [])
  end
end
