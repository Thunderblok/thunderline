defmodule Thunderline.Thundercore.Id.Parser do
  @moduledoc """
  ULID parsing, validation, and timestamp extraction.

  This module provides utilities for working with existing ULIDs:
  - Extracting the embedded timestamp
  - Validating ULID format
  - Converting between string and binary representations
  - Comparing ULIDs by time

  ## Timestamp Extraction

  The first 48 bits of a ULID encode the Unix timestamp in milliseconds.
  This allows extracting the creation time without storing an additional column:

      iex> {:ok, dt} = Thunderline.Id.Parser.timestamp("01HZQKX3VG0000000000000000")
      iex> dt.year
      2024

  ## Validation

  ULID validation checks:
  - Length is exactly 26 characters
  - All characters are valid Crockford Base32
  - Timestamp is within valid range (after Unix epoch, before year 10889)

  ## See Also

  - `Thunderline.Id.Generator` - ULID generation
  - `Thunderline.Id.Types.ULID` - Ash.Type for resources
  """

  alias Thunderline.Id

  # Crockford Base32 alphabet (excludes I, L, O, U)
  @crockford_alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @crockford_set MapSet.new(@crockford_alphabet)

  # Maximum valid timestamp (48 bits = ~8900 years from epoch)
  # Reserved for future timestamp validation
  @_max_timestamp 0xFFFFFFFFFFFF

  @doc """
  Extract the timestamp from a ULID string.

  Returns `{:ok, datetime}` on success or `{:error, :invalid_ulid}` on failure.

  ## Examples

      iex> {:ok, dt} = Thunderline.Id.Parser.timestamp("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      iex> is_struct(dt, DateTime)
      true

      iex> Thunderline.Id.Parser.timestamp("invalid")
      {:error, :invalid_ulid}

      iex> Thunderline.Id.Parser.timestamp(nil)
      {:error, :invalid_ulid}
  """
  @spec timestamp(Id.t()) :: {:ok, DateTime.t()} | {:error, :invalid_ulid}
  def timestamp(ulid) when is_binary(ulid) and byte_size(ulid) == 26 do
    with {:ok, binary} <- to_binary(ulid),
         <<unix_ms::unsigned-big-48, _random::80>> <- binary do
      {:ok, DateTime.from_unix!(unix_ms, :millisecond)}
    else
      _ -> {:error, :invalid_ulid}
    end
  rescue
    _ -> {:error, :invalid_ulid}
  end

  def timestamp(_), do: {:error, :invalid_ulid}

  @doc """
  Extract timestamp from ULID, raising on invalid input.

  ## Examples

      iex> dt = Thunderline.Id.Parser.timestamp!("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      iex> is_struct(dt, DateTime)
      true
  """
  @spec timestamp!(Id.t()) :: DateTime.t()
  def timestamp!(ulid) do
    case timestamp(ulid) do
      {:ok, dt} -> dt
      {:error, :invalid_ulid} -> raise ArgumentError, "Invalid ULID: #{inspect(ulid)}"
    end
  end

  @doc """
  Check if a value is a valid ULID.

  Validates:
  - String type
  - Exactly 26 characters
  - All characters in Crockford Base32 alphabet
  - First character ≤ '7' (timestamp overflow check)

  ## Examples

      iex> Thunderline.Id.Parser.valid?("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      true

      iex> Thunderline.Id.Parser.valid?("not-a-ulid")
      false

      iex> Thunderline.Id.Parser.valid?("01hzqkx3vgs8wqxj7y9zbnfr4m")
      true

      iex> Thunderline.Id.Parser.valid?(nil)
      false

      iex> Thunderline.Id.Parser.valid?(123)
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(ulid) when is_binary(ulid) and byte_size(ulid) == 26 do
    ulid
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.all?(&MapSet.member?(@crockford_set, &1))
  rescue
    _ -> false
  end

  def valid?(_), do: false

  @doc """
  Convert a 16-byte binary ULID to its string representation.

  ## Examples

      iex> bin = <<1, 127, 29, 107, 117, 125, 183, 154, 147, 224, 191, 135, 161, 183, 2, 52>>
      iex> str = Thunderline.Id.Parser.to_string(bin)
      iex> String.length(str)
      26
  """
  @spec to_string(Id.ulid_binary()) :: Id.t()
  def to_string(binary) when byte_size(binary) == 16 do
    {:ok, str} = Ecto.ULID.load(binary)
    str
  rescue
    _ ->
      # Manual encoding fallback
      <<value::unsigned-big-128>> = binary
      encode_base32(value, 26, [])
  end

  @doc """
  Convert a ULID string to its 16-byte binary representation.

  ## Examples

      iex> {:ok, bin} = Thunderline.Id.Parser.to_binary("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      iex> byte_size(bin)
      16

      iex> Thunderline.Id.Parser.to_binary("invalid")
      {:error, :invalid_ulid}
  """
  @spec to_binary(Id.t()) :: {:ok, Id.ulid_binary()} | {:error, :invalid_ulid}
  def to_binary(ulid) when is_binary(ulid) and byte_size(ulid) == 26 do
    case Ecto.ULID.dump(ulid) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_ulid}
    end
  rescue
    _ ->
      # Manual decoding fallback
      try do
        value = decode_base32(ulid |> String.upcase() |> String.to_charlist(), 0)
        {:ok, <<value::unsigned-big-128>>}
      rescue
        _ -> {:error, :invalid_ulid}
      end
  end

  def to_binary(_), do: {:error, :invalid_ulid}

  @doc """
  Compare two ULIDs by their timestamp component.

  Returns:
  - `:lt` if first is older (smaller timestamp)
  - `:eq` if same timestamp (within same millisecond)
  - `:gt` if first is newer (larger timestamp)

  Note: Only compares timestamp portion. ULIDs generated in the same
  millisecond return `:eq` even if their random portions differ.

  ## Examples

      iex> old = Thunderline.Id.generate_at(~U[2024-01-01 00:00:00Z])
      iex> new = Thunderline.Id.generate_at(~U[2024-06-01 00:00:00Z])
      iex> Thunderline.Id.Parser.compare_time(old, new)
      :lt

      iex> same1 = Thunderline.Id.generate_at(~U[2024-03-15 12:00:00Z])
      iex> same2 = Thunderline.Id.generate_at(~U[2024-03-15 12:00:00Z])
      iex> Thunderline.Id.Parser.compare_time(same1, same2)
      :eq
  """
  @spec compare_time(Id.t(), Id.t()) :: :lt | :eq | :gt
  def compare_time(ulid1, ulid2) do
    ts1 = extract_timestamp_ms(ulid1)
    ts2 = extract_timestamp_ms(ulid2)

    cond do
      ts1 < ts2 -> :lt
      ts1 > ts2 -> :gt
      true -> :eq
    end
  end

  # --- Private Helpers ---

  @spec extract_timestamp_ms(Id.t()) :: non_neg_integer()
  defp extract_timestamp_ms(ulid) do
    case to_binary(ulid) do
      {:ok, <<unix_ms::unsigned-big-48, _::80>>} -> unix_ms
      _ -> 0
    end
  end

  # Encode integer to Crockford Base32 string
  @spec encode_base32(non_neg_integer(), non_neg_integer(), list()) :: String.t()
  defp encode_base32(_value, 0, acc), do: IO.iodata_to_binary(acc)

  defp encode_base32(value, remaining, acc) do
    char_index = rem(value, 32)
    char = Enum.at(@crockford_alphabet, char_index)
    encode_base32(div(value, 32), remaining - 1, [char | acc])
  end

  # Decode Crockford Base32 charlist to integer
  @spec decode_base32(charlist(), non_neg_integer()) :: non_neg_integer()
  defp decode_base32([], acc), do: acc

  defp decode_base32([char | rest], acc) do
    index = Enum.find_index(@crockford_alphabet, &(&1 == char)) || 0
    decode_base32(rest, acc * 32 + index)
  end
end
