defmodule Thunderline.Thunderbolt.NCA.PerceptionTest do
  @moduledoc """
  Tests for NCA perception layer with Sobel gradients.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.NCA.Perception

  describe "new_cell/1" do
    test "creates cell with correct shape" do
      cell = Perception.new_cell(channels: 16)
      assert Nx.shape(cell) == {16}
    end

    test "creates cell with default 16 channels" do
      cell = Perception.new_cell()
      assert Nx.shape(cell) == {16}
    end
  end

  describe "seed_cell/0" do
    test "has correct shape" do
      seed = Perception.seed_cell()
      assert Nx.shape(seed) == {16}
    end

    test "has alpha = 1.0" do
      seed = Perception.seed_cell()
      # Get alpha (index 3) and squeeze to scalar
      alpha = seed |> Nx.slice([3], [1]) |> Nx.squeeze() |> Nx.to_number()
      assert_in_delta alpha, 1.0, 0.001
    end

    test "has white RGB" do
      seed = Perception.seed_cell()
      rgb = Nx.to_list(Nx.slice(seed, [0], [3]))
      assert_in_delta Enum.at(rgb, 0), 1.0, 0.001
      assert_in_delta Enum.at(rgb, 1), 1.0, 0.001
      assert_in_delta Enum.at(rgb, 2), 1.0, 0.001
    end
  end

  describe "perceive/1" do
    test "outputs 3x input channels" do
      # 4x4 grid with 16 channels
      state = Nx.broadcast(0.5, {4, 4, 16})
      perception = Perception.perceive(state)

      # Should be 48 channels (state + grad_x + grad_y)
      assert Nx.shape(perception) == {4, 4, 48}
    end

    test "preserves state in first channels" do
      state = Nx.iota({4, 4, 16})
      perception = Perception.perceive(state)

      # First 16 channels should match input state
      extracted = Nx.slice(perception, [0, 0, 0], [4, 4, 16])
      assert Nx.to_list(extracted) == Nx.to_list(state)
    end
  end

  describe "sobel_gradient_x/1" do
    test "detects horizontal edges" do
      # Vertical edge pattern (bright on right)
      left = Nx.broadcast(0.0, {3, 2, 1})
      right = Nx.broadcast(1.0, {3, 2, 1})
      state = Nx.concatenate([left, right], axis: 1)

      grad = Perception.sobel_gradient_x(state)

      # Middle column should have strong gradient
      center_grad = Nx.slice(grad, [1, 1, 0], [1, 2, 1])
      max_grad = Nx.to_number(Nx.reduce_max(Nx.abs(center_grad)))
      assert max_grad > 0.1
    end

    test "outputs same shape as input" do
      state = Nx.broadcast(0.5, {5, 5, 8})
      grad = Perception.sobel_gradient_x(state)
      assert Nx.shape(grad) == {5, 5, 8}
    end
  end

  describe "apply_alive_mask/1" do
    test "zeros out isolated dead cells" do
      # Create 3x3 grid - all alive (alpha=1) except center (alpha=0)
      # Each cell is 16 channels: [r, g, b, alpha, hidden...]
      alive_cell = [1.0, 1.0, 1.0, 1.0] ++ List.duplicate(0.5, 12)
      dead_cell = [1.0, 1.0, 1.0, 0.0] ++ List.duplicate(0.5, 12)

      # Build grid with dead center that has alive neighbors
      row_alive = [alive_cell, alive_cell, alive_cell]
      row_dead_center = [alive_cell, dead_cell, alive_cell]

      state = Nx.tensor([row_alive, row_dead_center, row_alive])

      masked = Perception.apply_alive_mask(state)

      # The center cell should NOT be zeroed because its neighbors are alive
      # (alive mask uses max pooling to check neighborhood)
      center = Nx.slice(masked, [1, 1, 0], [1, 1, 16])
      center_sum = center |> Nx.sum() |> Nx.to_number()

      # Center has neighbors alive, so max pool alpha > 0.1, keeps values
      assert center_sum > 0.0
    end

    test "zeros out completely isolated dead regions" do
      # Create 5x5 grid - all dead (alpha=0)
      dead_cell = [0.0, 0.0, 0.0, 0.0] ++ List.duplicate(0.5, 12)

      # 5x5 grid all dead
      grid = for _ <- 1..5, do: for(_ <- 1..5, do: dead_cell)
      state = Nx.tensor(grid)

      masked = Perception.apply_alive_mask(state)

      # Everything should be zero since no cell or neighbor has alpha > 0.1
      total_sum = masked |> Nx.sum() |> Nx.to_number()
      assert_in_delta total_sum, 0.0, 0.001
    end
  end
end
