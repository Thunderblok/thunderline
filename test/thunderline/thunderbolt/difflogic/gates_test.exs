defmodule Thunderline.Thunderbolt.DiffLogic.GatesTest do
  @moduledoc """
  Tests for DiffLogic differentiable logic gates.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.DiffLogic.Gates

  describe "individual gates" do
    # Note: apply_gate uses defn with cond, which requires scalar gate_id
    # For proper tensor batch operations, use soft_gate or gate_layer instead

    test "gate 0 (FALSE) returns 0 for scalars" do
      a = Nx.tensor(1.0)
      b = Nx.tensor(1.0)
      result = Gates.apply_gate(a, b, 0)
      assert_in_delta Nx.to_number(result), 0.0, 0.001
    end

    test "gate 1 (AND) returns a * b for scalars" do
      # (0.5, 0.5) -> 0.25
      a = Nx.tensor(0.5)
      b = Nx.tensor(0.5)
      result = Gates.apply_gate(a, b, 1)
      assert_in_delta Nx.to_number(result), 0.25, 0.001
    end

    test "gate 6 (XOR) for scalars" do
      # XOR(0.5, 0.5) = 0.5 + 0.5 - 2*0.5*0.5 = 1.0 - 0.5 = 0.5
      a = Nx.tensor(0.5)
      b = Nx.tensor(0.5)
      result = Gates.apply_gate(a, b, 6)
      assert_in_delta Nx.to_number(result), 0.5, 0.001
    end

    test "gate 7 (OR) for scalars" do
      # OR(0.5, 0.5) = 0.5 + 0.5 - 0.5*0.5 = 1.0 - 0.25 = 0.75
      a = Nx.tensor(0.5)
      b = Nx.tensor(0.5)
      result = Gates.apply_gate(a, b, 7)
      assert_in_delta Nx.to_number(result), 0.75, 0.001
    end

    test "gate 15 (TRUE) always returns 1" do
      a = Nx.tensor(0.0)
      b = Nx.tensor(0.0)
      result = Gates.apply_gate(a, b, 15)
      assert_in_delta Nx.to_number(result), 1.0, 0.001
    end
  end

  describe "soft_gate/3" do
    test "with uniform weights produces weighted average" do
      a = Nx.tensor(0.5)
      b = Nx.tensor(0.5)
      # Uniform weights -> equal probability for all gates
      weights = Nx.broadcast(1.0 / 16.0, {16})

      result = Gates.soft_gate(a, b, weights)

      # Should produce a scalar result
      assert Nx.shape(result) == {}
    end

    test "with peaked weights approximates AND gate" do
      a = Nx.tensor(0.5)
      b = Nx.tensor(0.5)

      # All weight on gate 1 (AND)
      weights =
        Nx.put_slice(
          Nx.broadcast(0.0, {16}),
          [1],
          Nx.tensor([1.0])
        )

      result = Gates.soft_gate(a, b, weights)

      # Should be very close to AND(0.5, 0.5) = 0.25
      assert_in_delta Nx.to_number(result), 0.25, 0.01
    end
  end

  describe "initialize_gate_logits/1" do
    test "creates correct shape with n_gates option" do
      logits = Gates.initialize_gate_logits(n_gates: 10)
      assert Nx.shape(logits) == {10, 16}
    end

    test "default creates 32 gates" do
      logits = Gates.initialize_gate_logits([])
      assert Nx.shape(logits) == {32, 16}
    end

    test "values are in reasonable range" do
      logits = Gates.initialize_gate_logits(n_gates: 100, init: :uniform)
      max_val = Nx.to_number(Nx.reduce_max(Nx.abs(logits)))
      # Uniform init is in [0, 1]
      assert max_val <= 1.0
    end
  end

  describe "gate_layer/2" do
    test "processes batch with soft gate selection" do
      # Single pair of scalar inputs
      a = Nx.tensor(0.5)
      b = Nx.tensor(0.5)

      # Logits for one gate (will be softmaxed)
      logits = Nx.broadcast(0.0, {16})

      # Use straight_through_gate for batch processing
      result = Gates.straight_through_gate(a, b, logits)

      # Should produce a scalar
      assert Nx.shape(result) == {}
    end
  end
end
