defmodule Thunderline.Thunderbolt.Continuous.Storage do
  @moduledoc """
  Storage format for continuous tensors using piecewise-constant representation.

  This module handles serialization and deserialization of ContinuousTensor
  structs for persistence in ThunderBlock and transfer to external systems
  (e.g., Finch.jl sidecar).

  ## Storage Formats

  ### Internal (Elixir)
  Erlang term format for fast serialization within BEAM:

      {:continuous_tensor, version, dims, intervals, default, metadata}

  ### External (JSON)
  JSON format for interop with Julia/Python sidecars:

      {
        "version": 1,
        "dims": 2,
        "intervals": [
          {"bounds": [[0.0, 10.0], [0.0, 10.0]], "value": 1.0}
        ],
        "default": null,
        "metadata": {}
      }

  ### Compressed
  For large tensors, zlib compression over binary:

      <<version::8, dims::16, compressed_data::binary>>

  ## Usage

      alias Thunderline.Thunderbolt.Continuous.{Tensor, Storage}

      tensor = Tensor.new(dims: 2)
      |> Tensor.set_interval({{0.0, 10.0}, {0.0, 10.0}}, 1.0)

      # Serialize to binary
      {:ok, binary} = Storage.serialize(tensor)

      # Deserialize back
      {:ok, restored} = Storage.deserialize(binary)

      # Export to JSON for Finch.jl
      {:ok, json} = Storage.to_json(tensor)
  """

  alias Thunderline.Thunderbolt.Continuous.Tensor

  @storage_version 1

  @doc """
  Serializes a ContinuousTensor to binary format.

  ## Options

  - `:compress` - Whether to compress (default: false)
  - `:format` - `:etf` (Erlang Term Format) or `:json` (default: `:etf`)
  """
  @spec serialize(Tensor.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def serialize(%Tensor{} = tensor, opts \\ []) do
    format = Keyword.get(opts, :format, :etf)
    compress = Keyword.get(opts, :compress, false)

    case format do
      :etf -> serialize_etf(tensor, compress)
      :json -> to_json(tensor)
      _ -> {:error, {:unknown_format, format}}
    end
  end

  @doc """
  Deserializes binary data back to a ContinuousTensor.
  """
  @spec deserialize(binary(), keyword()) :: {:ok, Tensor.t()} | {:error, term()}
  def deserialize(binary, opts \\ []) do
    format = Keyword.get(opts, :format, :auto)

    case detect_format(binary, format) do
      :etf -> deserialize_etf(binary)
      :etf_compressed -> deserialize_etf_compressed(binary)
      :json -> from_json(binary)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Converts a ContinuousTensor to JSON format for external systems.

  This format is compatible with Finch.jl and other external processors.
  """
  @spec to_json(Tensor.t()) :: {:ok, String.t()} | {:error, term()}
  def to_json(%Tensor{} = tensor) do
    json_map = %{
      "version" => @storage_version,
      "dims" => tensor.dims,
      "intervals" => encode_intervals_json(tensor.intervals),
      "default" => tensor.default,
      "metadata" => tensor.metadata
    }

    case Jason.encode(json_map) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encode_error, reason}}
    end
  end

  @doc """
  Parses JSON data into a ContinuousTensor.
  """
  @spec from_json(String.t()) :: {:ok, Tensor.t()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    with {:ok, map} <- Jason.decode(json),
         {:ok, tensor} <- parse_json_map(map) do
      {:ok, tensor}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Calculates the storage size of a serialized tensor.
  """
  @spec byte_size(Tensor.t()) :: non_neg_integer()
  def byte_size(%Tensor{} = tensor) do
    case serialize(tensor) do
      {:ok, binary} -> Kernel.byte_size(binary)
      _ -> 0
    end
  end

  @doc """
  Exports tensor to a format suitable for Finch.jl sparse representation.

  Returns a map with:
  - `:format` - Sparse format hint ("coo", "csc", etc.)
  - `:data` - Coordinate/value pairs
  - `:shape` - Bounding box of the tensor
  """
  @spec to_finch_format(Tensor.t()) :: map()
  def to_finch_format(%Tensor{dims: dims, intervals: intervals, default: default}) do
    # Convert intervals to COO (Coordinate) format
    {coords, values} = intervals_to_coo(intervals, dims)

    # Calculate bounding shape
    shape = calculate_bounding_shape(intervals, dims)

    %{
      format: "interval_list",
      dims: dims,
      intervals: Enum.map(intervals, fn {interval, value} ->
        %{bounds: interval_to_list(interval), value: value}
      end),
      shape: shape,
      default: default,
      nnz: length(intervals)
    }
  end

  # ============================================================================
  # Private - ETF Serialization
  # ============================================================================

  defp serialize_etf(%Tensor{} = tensor, compress) do
    term = {
      :continuous_tensor,
      @storage_version,
      tensor.dims,
      tensor.intervals,
      tensor.default,
      tensor.metadata
    }

    binary = :erlang.term_to_binary(term)

    if compress and Kernel.byte_size(binary) > 1024 do
      compressed = :zlib.compress(binary)
      {:ok, <<0x01, compressed::binary>>}
    else
      {:ok, <<0x00, binary::binary>>}
    end
  end

  defp deserialize_etf(<<0x00, binary::binary>>) do
    parse_etf_term(binary)
  end

  defp deserialize_etf(binary) do
    # Legacy format without header
    parse_etf_term(binary)
  end

  defp deserialize_etf_compressed(<<0x01, compressed::binary>>) do
    binary = :zlib.uncompress(compressed)
    parse_etf_term(binary)
  end

  defp parse_etf_term(binary) do
    try do
      case :erlang.binary_to_term(binary, [:safe]) do
        {:continuous_tensor, _version, dims, intervals, default, metadata} ->
          tensor = %Tensor{
            dims: dims,
            intervals: intervals,
            default: default,
            metadata: metadata
          }

          {:ok, tensor}

        _ ->
          {:error, :invalid_term_format}
      end
    rescue
      ArgumentError -> {:error, :invalid_binary}
    end
  end

  # ============================================================================
  # Private - JSON Encoding/Decoding
  # ============================================================================

  defp encode_intervals_json(intervals) do
    Enum.map(intervals, fn {interval, value} ->
      %{
        "bounds" => interval_to_list(interval),
        "value" => value
      }
    end)
  end

  defp interval_to_list({start_val, stop_val}) when is_number(start_val) do
    [[start_val, stop_val]]
  end

  defp interval_to_list(interval) when is_tuple(interval) do
    interval
    |> Tuple.to_list()
    |> Enum.map(fn {start_val, stop_val} -> [start_val, stop_val] end)
  end

  defp parse_json_map(%{"dims" => dims, "intervals" => intervals_json} = map) do
    intervals = parse_intervals_json(intervals_json)

    tensor = %Tensor{
      dims: dims,
      intervals: intervals,
      default: Map.get(map, "default"),
      metadata: Map.get(map, "metadata", %{})
    }

    {:ok, tensor}
  end

  defp parse_json_map(_), do: {:error, :invalid_json_structure}

  defp parse_intervals_json(intervals_json) when is_list(intervals_json) do
    Enum.map(intervals_json, fn %{"bounds" => bounds, "value" => value} ->
      interval = list_to_interval(bounds)
      {interval, value}
    end)
  end

  defp list_to_interval([[start_val, stop_val]]) do
    {start_val, stop_val}
  end

  defp list_to_interval(bounds) when is_list(bounds) do
    bounds
    |> Enum.map(fn [start_val, stop_val] -> {start_val, stop_val} end)
    |> List.to_tuple()
  end

  # ============================================================================
  # Private - Format Detection
  # ============================================================================

  defp detect_format(<<0x00, _rest::binary>>, :auto), do: :etf
  defp detect_format(<<0x01, _rest::binary>>, :auto), do: :etf_compressed
  defp detect_format(<<"{", _rest::binary>>, :auto), do: :json
  defp detect_format(_binary, :etf), do: :etf
  defp detect_format(_binary, :json), do: :json
  defp detect_format(_binary, :auto), do: {:error, :unknown_format}
  defp detect_format(_binary, format), do: {:error, {:unknown_format, format}}

  # ============================================================================
  # Private - Finch Format Helpers
  # ============================================================================

  defp intervals_to_coo(intervals, _dims) do
    # For interval-based representation, we export interval bounds as coordinates
    coords =
      Enum.map(intervals, fn {interval, _value} ->
        interval_to_center(interval)
      end)

    values = Enum.map(intervals, fn {_interval, value} -> value end)

    {coords, values}
  end

  defp interval_to_center({start_val, stop_val}) when is_number(start_val) do
    [(start_val + stop_val) / 2]
  end

  defp interval_to_center(interval) when is_tuple(interval) do
    interval
    |> Tuple.to_list()
    |> Enum.map(fn {start_val, stop_val} -> (start_val + stop_val) / 2 end)
  end

  defp calculate_bounding_shape([], dims) do
    List.duplicate({0.0, 0.0}, dims)
  end

  defp calculate_bounding_shape(intervals, dims) do
    # Find min/max across all intervals for each dimension
    Enum.reduce(intervals, init_shape_bounds(dims), fn {interval, _value}, acc ->
      merge_shape_bounds(interval, acc)
    end)
  end

  defp init_shape_bounds(dims) do
    List.duplicate({:infinity, :neg_infinity}, dims)
  end

  defp merge_shape_bounds({start_val, stop_val}, [{min_val, max_val}]) do
    [{safe_min(start_val, min_val), safe_max(stop_val, max_val)}]
  end

  defp merge_shape_bounds(interval, bounds) when is_tuple(interval) do
    interval
    |> Tuple.to_list()
    |> Enum.zip(bounds)
    |> Enum.map(fn {{start_val, stop_val}, {min_val, max_val}} ->
      {safe_min(start_val, min_val), safe_max(stop_val, max_val)}
    end)
  end

  defp safe_min(:infinity, v), do: v
  defp safe_min(v, :infinity), do: v
  defp safe_min(a, b), do: Kernel.min(a, b)

  defp safe_max(:neg_infinity, v), do: v
  defp safe_max(v, :neg_infinity), do: v
  defp safe_max(a, b), do: Kernel.max(a, b)
end
