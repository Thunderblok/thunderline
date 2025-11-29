defmodule Thunderline.Thunderbolt.Continuous.AlgebraTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Continuous.{Tensor, Algebra}

  setup do
    # Create test tensors
    tensor_a =
      Tensor.new(dims: 1)
      |> Tensor.set_interval({0.0, 10.0}, 10)

    tensor_b =
      Tensor.new(dims: 1)
      |> Tensor.set_interval({0.0, 10.0}, 5)

    {:ok, tensor_a: tensor_a, tensor_b: tensor_b}
  end

  describe "add/2" do
    test "adds scalar to tensor", %{tensor_a: tensor} do
      result = Algebra.add(tensor, 5)

      assert Tensor.get(result, 5.0) == 15
    end

    test "adds two tensors", %{tensor_a: a, tensor_b: b} do
      result = Algebra.add(a, b)

      # Should have summed values where intervals overlap
      assert is_struct(result, Tensor)
    end
  end

  describe "subtract/2" do
    test "subtracts scalar from tensor", %{tensor_a: tensor} do
      result = Algebra.subtract(tensor, 3)

      assert Tensor.get(result, 5.0) == 7
    end
  end

  describe "scale/2" do
    test "scales tensor by factor", %{tensor_a: tensor} do
      result = Algebra.scale(tensor, 2)

      assert Tensor.get(result, 5.0) == 20
    end

    test "scales by negative factor", %{tensor_a: tensor} do
      result = Algebra.scale(tensor, -1)

      assert Tensor.get(result, 5.0) == -10
    end

    test "scales by zero", %{tensor_a: tensor} do
      result = Algebra.scale(tensor, 0)

      assert Tensor.get(result, 5.0) == 0
    end
  end

  describe "sum/1" do
    test "sums all interval values" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 10)
        |> Tensor.set_interval({1.0, 2.0}, 20)
        |> Tensor.set_interval({2.0, 3.0}, 30)

      assert Algebra.sum(tensor) == 60
    end

    test "returns 0 for empty tensor" do
      tensor = Tensor.new()

      assert Algebra.sum(tensor) == 0
    end
  end

  describe "mean/1" do
    test "computes mean of interval values" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 10)
        |> Tensor.set_interval({1.0, 2.0}, 20)
        |> Tensor.set_interval({2.0, 3.0}, 30)

      assert Algebra.mean(tensor) == 20.0
    end

    test "returns nil for empty tensor" do
      tensor = Tensor.new()

      assert Algebra.mean(tensor) == nil
    end
  end

  describe "min/1 and max/1" do
    test "finds min value" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 30)
        |> Tensor.set_interval({1.0, 2.0}, 10)
        |> Tensor.set_interval({2.0, 3.0}, 50)

      assert Algebra.min(tensor) == 10
    end

    test "finds max value" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({0.0, 1.0}, 30)
        |> Tensor.set_interval({1.0, 2.0}, 10)
        |> Tensor.set_interval({2.0, 3.0}, 50)

      assert Algebra.max(tensor) == 50
    end

    test "returns nil for empty tensor" do
      tensor = Tensor.new()

      assert Algebra.min(tensor) == nil
      assert Algebra.max(tensor) == nil
    end
  end

  describe "integrate/3" do
    test "integrates constant function" do
      # f(x) = 10 for x in [0, 10)
      # ∫₀¹⁰ 10 dx = 100
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, 10)

      result = Algebra.integrate(tensor, 0.0, 10.0)

      assert result == 100.0
    end

    test "integrates step function" do
      # f(x) = 10 for [0,5), 20 for [5,10)
      # ∫₀¹⁰ f(x) dx = 5*10 + 5*20 = 150
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 5.0}, 10)
        |> Tensor.set_interval({5.0, 10.0}, 20)

      result = Algebra.integrate(tensor, 0.0, 10.0)

      assert result == 150.0
    end

    test "integrates partial range" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, 10)

      # ∫₂⁸ 10 dx = 60
      result = Algebra.integrate(tensor, 2.0, 8.0)

      assert result == 60.0
    end

    test "returns 0 for range outside intervals with nil default" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, 10)

      result = Algebra.integrate(tensor, 20.0, 30.0)

      assert result == 0.0
    end
  end

  describe "weighted_sum/1" do
    test "computes weighted sum" do
      # interval [0,5) value 10: contributes 5*10=50
      # interval [5,10) value 20: contributes 5*20=100
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 5.0}, 10)
        |> Tensor.set_interval({5.0, 10.0}, 20)

      assert Algebra.weighted_sum(tensor) == 150.0
    end
  end

  describe "differentiate/2" do
    test "returns 0 for constant function" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, 10)

      # Interior point - derivative should be 0
      result = Algebra.differentiate(tensor, 5.0)

      assert_in_delta result, 0.0, 0.01
    end
  end

  describe "l2_distance/2" do
    test "computes distance between identical tensors" do
      tensor =
        Tensor.new(dims: 1)
        |> Tensor.set_interval({0.0, 10.0}, 5)

      distance = Algebra.l2_distance(tensor, tensor)

      assert_in_delta distance, 0.0, 0.001
    end
  end
end
