defmodule Thunderline.Thunderbolt.Continuous.TensorTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Continuous.Tensor

  describe "new/1" do
    test "creates a 1D tensor with defaults" do
      tensor = Tensor.new()

      assert tensor.dims == 1
      assert tensor.intervals == []
      assert tensor.default == nil
    end

    test "creates tensor with specified dimensions" do
      tensor = Tensor.new(dims: 3)

      assert tensor.dims == 3
    end

    test "creates tensor with default value" do
      tensor = Tensor.new(dims: 1, default: 0.0)

      assert tensor.default == 0.0
    end

    test "creates tensor with metadata" do
      tensor = Tensor.new(dims: 2, metadata: %{name: "test_field"})

      assert tensor.metadata == %{name: "test_field"}
    end
  end

  describe "set_interval/3" do
    test "sets interval for 1D tensor" do
      tensor = Tensor.new(dims: 1)
      tensor = Tensor.set_interval(tensor, {0.0, 10.0}, 42)

      assert Tensor.interval_count(tensor) == 1
      assert [{{0.0, 10.0}, 42}] = Tensor.intervals(tensor)
    end

    test "sets multiple non-overlapping intervals" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 5.0}, 10)
        |> Tensor.set_interval({5.0, 10.0}, 20)
        |> Tensor.set_interval({10.0, 15.0}, 30)

      assert Tensor.interval_count(tensor) == 3
    end

    test "sets interval for 2D tensor" do
      tensor = Tensor.new(dims: 2)
      tensor = Tensor.set_interval(tensor, {{0.0, 10.0}, {0.0, 10.0}}, :region)

      assert Tensor.interval_count(tensor) == 1
    end

    test "raises for mismatched dimensions" do
      tensor = Tensor.new(dims: 2)

      assert_raise ArgumentError, fn ->
        Tensor.set_interval(tensor, {0.0, 10.0}, 1)
      end
    end
  end

  describe "get/2" do
    test "returns value at coordinate within interval" do
      tensor =
        Tensor.new(dims: 1, default: 0)
        |> Tensor.set_interval({0.0, 10.0}, 42)

      assert Tensor.get(tensor, 5.0) == 42
      assert Tensor.get(tensor, 0.0) == 42
      assert Tensor.get(tensor, 9.999) == 42
    end

    test "returns default for coordinate outside intervals" do
      tensor =
        Tensor.new(dims: 1, default: -1)
        |> Tensor.set_interval({0.0, 10.0}, 42)

      assert Tensor.get(tensor, 10.0) == -1
      assert Tensor.get(tensor, -5.0) == -1
      assert Tensor.get(tensor, 100.0) == -1
    end

    test "returns nil when no default set and outside intervals" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, 42)

      assert Tensor.get(tensor, 20.0) == nil
    end

    test "handles multiple intervals" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, :first)
        |> Tensor.set_interval({10.0, 20.0}, :second)
        |> Tensor.set_interval({20.0, 30.0}, :third)

      assert Tensor.get(tensor, 5.0) == :first
      assert Tensor.get(tensor, 15.0) == :second
      assert Tensor.get(tensor, 25.0) == :third
    end

    test "handles 2D coordinate" do
      tensor =
        Tensor.new(dims: 2)
        |> Tensor.set_interval({{0.0, 10.0}, {0.0, 10.0}}, :center)

      assert Tensor.get(tensor, {5.0, 5.0}) == :center
      assert Tensor.get(tensor, {0.0, 0.0}) == :center
      assert Tensor.get(tensor, {9.99, 9.99}) == :center
      assert Tensor.get(tensor, {15.0, 15.0}) == nil
    end

    test "real-valued indexing at boundaries" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 1.0}, 10)
        |> Tensor.set_interval({1.0, 2.0}, 20)

      # Lower bound is inclusive
      assert Tensor.get(tensor, 0.0) == 10
      assert Tensor.get(tensor, 1.0) == 20

      # Upper bound is exclusive
      assert Tensor.get(tensor, 0.999999) == 10
    end
  end

  describe "interval_count/1" do
    test "returns 0 for empty tensor" do
      tensor = Tensor.new()
      assert Tensor.interval_count(tensor) == 0
    end

    test "returns correct count" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 1)
        |> Tensor.set_interval({1.0, 2.0}, 2)
        |> Tensor.set_interval({2.0, 3.0}, 3)

      assert Tensor.interval_count(tensor) == 3
    end
  end

  describe "map/2" do
    test "transforms all values" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 10)
        |> Tensor.set_interval({1.0, 2.0}, 20)

      doubled = Tensor.map(tensor, fn v -> v * 2 end)

      assert Tensor.get(doubled, 0.5) == 20
      assert Tensor.get(doubled, 1.5) == 40
    end
  end

  describe "reduce/3" do
    test "reduces all interval values" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 10)
        |> Tensor.set_interval({1.0, 2.0}, 20)
        |> Tensor.set_interval({2.0, 3.0}, 30)

      sum = Tensor.reduce(tensor, 0, fn v, acc -> v + acc end)

      assert sum == 60
    end
  end

  describe "sample/3" do
    test "samples at regular intervals" do
      tensor =
        Tensor.new(dims: 1, default: 0)
        |> Tensor.set_interval({0.0, 5.0}, 10)
        |> Tensor.set_interval({5.0, 10.0}, 20)

      samples = Tensor.sample(tensor, {0.0, 10.0}, steps: 10)

      assert length(samples) == 10
      # First 5 samples should be 10, last 5 should be 20
      assert Enum.at(samples, 0) == 10
      assert Enum.at(samples, 4) == 10
      assert Enum.at(samples, 5) == 20
      assert Enum.at(samples, 9) == 20
    end
  end

  describe "query_region/2" do
    test "finds overlapping intervals in 1D" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 10.0}, :a)
        |> Tensor.set_interval({10.0, 20.0}, :b)
        |> Tensor.set_interval({20.0, 30.0}, :c)

      # Query overlapping with :a and :b
      matches = Tensor.query_region(tensor, {5.0, 15.0})

      values = Enum.map(matches, fn {_, v} -> v end)
      assert :a in values
      assert :b in values
      refute :c in values
    end

    test "returns empty for non-overlapping query" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 10.0}, :a)

      matches = Tensor.query_region(tensor, {100.0, 200.0})

      assert matches == []
    end
  end

  describe "merge/2" do
    test "merges two tensors" do
      a =
        Tensor.new(dims: 1, default: 0)
        |> Tensor.set_interval({0.0, 10.0}, 1)

      b =
        Tensor.new(dims: 1, default: 0)
        |> Tensor.set_interval({5.0, 15.0}, 2)

      merged = Tensor.merge(a, b)

      # Has intervals from both
      assert Tensor.interval_count(merged) >= 2
    end
  end
end
