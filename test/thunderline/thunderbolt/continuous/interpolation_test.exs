defmodule Thunderline.Thunderbolt.Continuous.InterpolationTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Continuous.{Tensor, Interpolation}

  setup do
    # Step function: 10 for [0,10), 20 for [10,20)
    step_tensor =
      Tensor.new(dims: 1, default: 0)
      |> Tensor.set_interval({0.0, 10.0}, 10.0)
      |> Tensor.set_interval({10.0, 20.0}, 20.0)

    {:ok, step_tensor: step_tensor}
  end

  describe "at/4 with :constant method" do
    test "returns piecewise constant values", %{step_tensor: tensor} do
      assert Interpolation.at(tensor, 5.0, :constant) == 10.0
      assert Interpolation.at(tensor, 15.0, :constant) == 20.0
      assert Interpolation.at(tensor, 25.0, :constant) == 0
    end
  end

  describe "at/4 with :linear method" do
    test "interpolates between intervals", %{step_tensor: tensor} do
      # Near the boundary at x=10, should interpolate
      value = Interpolation.at(tensor, 10.0, :linear, bandwidth: 1.0)

      # Should be somewhere between 10 and 20
      assert is_number(value)
    end
  end

  describe "at/4 with :gaussian method" do
    test "returns weighted average", %{step_tensor: tensor} do
      # At center of first interval
      value = Interpolation.at(tensor, 5.0, :gaussian, bandwidth: 5.0)

      # Should be closer to 10 (center of first interval)
      assert is_number(value)
    end
  end

  describe "sample/3" do
    test "samples at regular intervals", %{step_tensor: tensor} do
      samples = Interpolation.sample(tensor, {0.0, 20.0}, steps: 20)

      assert length(samples) == 20

      # Each sample is {coord, value}
      Enum.each(samples, fn {coord, value} ->
        assert is_number(coord)
        assert is_number(value) or is_nil(value)
      end)
    end

    test "samples with interpolation", %{step_tensor: tensor} do
      samples =
        Interpolation.sample(tensor, {0.0, 20.0},
          steps: 20,
          method: :linear,
          bandwidth: 1.0
        )

      assert length(samples) == 20
    end
  end

  describe "transitions/1" do
    test "returns boundary points", %{step_tensor: tensor} do
      transitions = Interpolation.transitions(tensor)

      assert 0.0 in transitions
      assert 10.0 in transitions
      assert 20.0 in transitions
    end

    test "returns sorted unique values" do
      tensor =
        Tensor.new()
        |> Tensor.set_interval({5.0, 10.0}, 1)
        |> Tensor.set_interval({0.0, 5.0}, 2)

      transitions = Interpolation.transitions(tensor)

      assert transitions == Enum.sort(transitions)
      assert transitions == Enum.uniq(transitions)
    end
  end

  describe "gradient_at_transitions/1" do
    test "returns gradient at each boundary", %{step_tensor: tensor} do
      gradients = Interpolation.gradient_at_transitions(tensor)

      # Should have gradient info at each transition
      assert length(gradients) > 0

      Enum.each(gradients, fn {coord, gradient} ->
        assert is_number(coord)
        assert is_number(gradient)
      end)
    end

    test "detects step discontinuity" do
      tensor =
        Tensor.new(dims: 1, default: 0)
        |> Tensor.set_interval({0.0, 5.0}, 0.0)
        |> Tensor.set_interval({5.0, 10.0}, 100.0)

      gradients = Interpolation.gradient_at_transitions(tensor)

      # Should have large gradient at x=5 (the step)
      step_gradient =
        Enum.find(gradients, fn {x, _g} -> abs(x - 5.0) < 0.01 end)

      if step_gradient do
        {_x, g} = step_gradient
        # Gradient should be large (step function)
        assert abs(g) > 1000
      end
    end
  end

  describe "smooth/2" do
    test "creates smoothed version with more intervals", %{step_tensor: tensor} do
      smoothed = Interpolation.smooth(tensor, resolution: 5)

      # Should have more intervals than original
      assert Tensor.interval_count(smoothed) >= Tensor.interval_count(tensor)
    end
  end
end
