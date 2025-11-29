defmodule Thunderline.Thunderbolt.Continuous.StorageTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Continuous.{Tensor, Storage}

  setup do
    tensor =
      Tensor.new(dims: 1, default: 0.0, metadata: %{name: "test"})
      |> Tensor.set_interval({0.0, 10.0}, 42.0)
      |> Tensor.set_interval({10.0, 20.0}, 84.0)

    tensor_2d =
      Tensor.new(dims: 2)
      |> Tensor.set_interval({{0.0, 10.0}, {0.0, 10.0}}, :region)

    {:ok, tensor: tensor, tensor_2d: tensor_2d}
  end

  describe "serialize/2 and deserialize/2" do
    test "round-trips ETF format", %{tensor: tensor} do
      {:ok, binary} = Storage.serialize(tensor, format: :etf)
      {:ok, restored} = Storage.deserialize(binary)

      assert restored.dims == tensor.dims
      assert restored.default == tensor.default
      assert length(restored.intervals) == length(tensor.intervals)
      assert Tensor.get(restored, 5.0) == 42.0
    end

    test "round-trips compressed ETF", %{tensor: tensor} do
      {:ok, binary} = Storage.serialize(tensor, format: :etf, compress: true)
      {:ok, restored} = Storage.deserialize(binary)

      assert restored.dims == tensor.dims
      assert Tensor.get(restored, 5.0) == 42.0
    end

    test "preserves metadata", %{tensor: tensor} do
      {:ok, binary} = Storage.serialize(tensor)
      {:ok, restored} = Storage.deserialize(binary)

      assert restored.metadata == %{name: "test"}
    end
  end

  describe "to_json/1 and from_json/1" do
    test "round-trips JSON format", %{tensor: tensor} do
      {:ok, json} = Storage.to_json(tensor)
      {:ok, restored} = Storage.from_json(json)

      assert restored.dims == tensor.dims
      assert restored.default == tensor.default
      assert Tensor.get(restored, 5.0) == 42.0
    end

    test "produces valid JSON", %{tensor: tensor} do
      {:ok, json} = Storage.to_json(tensor)

      assert is_binary(json)
      assert String.starts_with?(json, "{")

      # Should be parseable
      {:ok, _map} = Jason.decode(json)
    end

    test "handles 2D tensors", %{tensor_2d: tensor_2d} do
      {:ok, json} = Storage.to_json(tensor_2d)
      {:ok, restored} = Storage.from_json(json)

      assert restored.dims == 2
      assert Tensor.get(restored, {5.0, 5.0}) == :region
    end
  end

  describe "byte_size/1" do
    test "returns size of serialized tensor", %{tensor: tensor} do
      size = Storage.byte_size(tensor)

      assert size > 0
      assert is_integer(size)
    end
  end

  describe "to_finch_format/1" do
    test "exports to Finch-compatible format", %{tensor: tensor} do
      finch_data = Storage.to_finch_format(tensor)

      assert finch_data.format == "interval_list"
      assert finch_data.dims == 1
      assert finch_data.nnz == 2
      assert is_list(finch_data.intervals)
    end

    test "includes shape bounds", %{tensor: tensor} do
      finch_data = Storage.to_finch_format(tensor)

      assert is_list(finch_data.shape)
      [{min_bound, max_bound}] = finch_data.shape
      assert min_bound == 0.0
      assert max_bound == 20.0
    end

    test "handles 2D tensors", %{tensor_2d: tensor_2d} do
      finch_data = Storage.to_finch_format(tensor_2d)

      assert finch_data.dims == 2
      assert length(finch_data.shape) == 2
    end
  end
end
