defmodule Thunderline.Thunderbolt.Cerebros.Encoder do
  @moduledoc """
  HC-Delta-14: Multimodal binary encoding for CA clustering.

  Encodes heterogeneous data (text, raw binary, tensors, tabular) into
  fixed-width binary for reversible CA state representation.

  ## Supported Types

  - `:text` - String/text data
  - `:raw` - Raw binary data
  - `:tensor` - Lists of numbers (vectors, matrices)
  - `:tabular` - Lists of maps (table rows)

  ## Examples

      iex> Encoder.encode_data("hello", :text, bits: 64)
      {:ok, <<...>>}

      iex> Encoder.encode_data([0.1, 0.5], :tensor, bits: 32)
      {:ok, <<...>>}
  """

  import Bitwise

  @default_bits 128

  @doc """
  Encode data into fixed-width binary representation.

  ## Arguments

  - `data` - The data to encode
  - `type` - The data type (`:text`, `:raw`, `:tensor`, `:tabular`)
  - `opts` - Options including `:bits` for output width in bytes

  ## Returns

  `{:ok, binary}` or `{:error, reason}`
  """
  @spec encode_data(term(), atom(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode_data(data, type, opts \\ [])

  def encode_data(data, :text, opts) when is_binary(data) do
    bytes = Keyword.get(opts, :bits, @default_bits)
    {:ok, hash_to_binary(data, bytes)}
  end

  def encode_data(data, :raw, opts) when is_binary(data) do
    bytes = Keyword.get(opts, :bits, @default_bits)
    {:ok, pad_or_truncate(data, bytes)}
  end

  def encode_data(data, :tensor, opts) when is_list(data) do
    bytes = Keyword.get(opts, :bits, @default_bits)
    binary = encode_tensor(data, bytes)
    {:ok, binary}
  end

  def encode_data(data, :tabular, opts) when is_list(data) do
    bytes = Keyword.get(opts, :bits, @default_bits)
    # Flatten tabular data to binary representation
    serialized = inspect(data, limit: :infinity)
    {:ok, hash_to_binary(serialized, bytes)}
  end

  def encode_data(_data, type, _opts) do
    {:error, {:unknown_type, type}}
  end

  @doc """
  Encode data, raising on error.
  """
  @spec encode_data!(term(), atom(), keyword()) :: binary()
  def encode_data!(data, type, opts \\ []) do
    case encode_data(data, type, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Encoding failed: #{inspect(reason)}"
    end
  end

  @doc """
  Decode binary back to a list of floats.

  ## Options

  - `:chunk_size` - Size of each chunk in bytes (default: 4)
  """
  @spec decode_binary(binary(), keyword()) :: list(float())
  def decode_binary(binary, opts \\ []) when is_binary(binary) do
    chunk_size = Keyword.get(opts, :chunk_size, 4)

    binary
    |> chunk_binary(chunk_size)
    |> Enum.map(&bytes_to_float/1)
  end

  @doc """
  Get encoding statistics for a binary.
  """
  @spec encoding_stats(binary()) :: map()
  def encoding_stats(binary) when is_binary(binary) do
    byte_count = byte_size(binary)
    bit_count = byte_count * 8

    # Count ones by examining each byte
    ones = binary
      |> :binary.bin_to_list()
      |> Enum.map(&count_ones_in_byte/1)
      |> Enum.sum()

    zeros = bit_count - ones
    density = if bit_count > 0, do: ones / bit_count, else: 0.0

    # Simple entropy approximation based on density
    entropy = if density > 0 and density < 1 do
      -density * :math.log2(density) - (1 - density) * :math.log2(1 - density)
    else
      0.0
    end

    %{
      byte_count: byte_count,
      bit_count: bit_count,
      ones_count: ones,
      zeros_count: zeros,
      density: density,
      entropy_approx: entropy
    }
  end

  # Private functions

  defp hash_to_binary(data, bytes_needed) when is_binary(data) and is_integer(bytes_needed) do
    # Use repeated hashing to generate enough bytes
    hash = generate_hash_bytes(data, bytes_needed)

    # Ensure exact byte count
    if byte_size(hash) >= bytes_needed do
      binary_part(hash, 0, bytes_needed)
    else
      hash <> :binary.copy(<<0>>, bytes_needed - byte_size(hash))
    end
  end

  defp generate_hash_bytes(data, bytes_needed) do
    # MD5 gives 16 bytes, repeat if we need more
    hash_rounds = div(bytes_needed, 16) + 1

    0..(hash_rounds - 1)
    |> Enum.map(fn i ->
      :crypto.hash(:md5, data <> <<i::32>>)
    end)
    |> Enum.join()
  end

  defp pad_or_truncate(binary, bytes_needed) when is_binary(binary) do
    current = byte_size(binary)

    cond do
      current == bytes_needed -> binary
      current > bytes_needed -> binary_part(binary, 0, bytes_needed)
      true -> binary <> :binary.copy(<<0>>, bytes_needed - current)
    end
  end

  defp encode_tensor(list, bytes_needed) when is_list(list) do
    # Convert floats/integers to bytes
    float_bytes = list
      |> List.flatten()
      |> Enum.map(&number_to_bytes/1)
      |> Enum.join()

    pad_or_truncate(float_bytes, bytes_needed)
  end

  defp number_to_bytes(n) when is_float(n) do
    # Clamp to [0,1] range and convert to 4-byte representation
    clamped = max(0.0, min(1.0, n))
    value = trunc(clamped * 0xFFFFFFFF)
    <<value::32>>
  end

  defp number_to_bytes(n) when is_integer(n) do
    <<n::32>>
  end

  defp chunk_binary(binary, chunk_size) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(chunk_size, chunk_size, Stream.cycle([0]))
    |> Enum.map(&:binary.list_to_bin/1)
  end

  defp bytes_to_float(bytes) when is_binary(bytes) do
    # Interpret bytes as unsigned integer and normalize to [0, 1]
    bits = byte_size(bytes) * 8
    max_val = (1 <<< bits) - 1

    value = bytes
      |> :binary.bin_to_list()
      |> Enum.reduce(0, fn byte, acc -> (acc <<< 8) + byte end)

    if max_val > 0, do: value / max_val, else: 0.0
  end

  defp count_ones_in_byte(byte) do
    # Count set bits (population count)
    byte
    |> Integer.digits(2)
    |> Enum.sum()
  end
end
