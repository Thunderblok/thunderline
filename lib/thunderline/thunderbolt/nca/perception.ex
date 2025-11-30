defmodule Thunderline.Thunderbolt.NCA.Perception do
  @moduledoc """
  Neural Cellular Automata Perception Layer.

  Based on: "Growing Neural Cellular Automata" (Distill, Google Research, 2020)
  
  Implements the perception stage of the NCA update rule where each cell
  perceives its local neighborhood through gradient sensing (Sobel filters).

  ## Perception Model

  Each cell has a 16-dimensional state vector:
  - Channels 0-2: RGB (visible state)
  - Channel 3: Alpha (alive/dead indicator)
  - Channels 4-15: Hidden state (learned representations)

  The perception vector is constructed by:
  1. The cell's own state (16 channels)
  2. Sobel-x gradient of state (16 channels)  
  3. Sobel-y gradient of state (16 channels)

  Total perception: 48 dimensions per cell.

  ## Reference

  Mordvintsev et al., "Growing Neural Cellular Automata", Distill 2020
  https://distill.pub/2020/growing-ca/
  """

  @state_channels 16
  @alpha_channel 3

  # Sobel filter values (as lists - converted to tensors at runtime)
  @sobel_x_vals [
    [-1, 0, 1],
    [-2, 0, 2],
    [-1, 0, 1]
  ]

  @sobel_y_vals [
    [-1, -2, -1],
    [0,  0,  0],
    [1,  2,  1]
  ]

  # Runtime functions to get Sobel tensors (avoids compile-time EXLA)
  defp sobel_x, do: Nx.tensor(@sobel_x_vals, type: :f32)
  defp sobel_y, do: Nx.tensor(@sobel_y_vals, type: :f32)

  # ═══════════════════════════════════════════════════════════════
  # CELL STATE
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Create a new cell state vector.

  ## Options

  - `:rgb` - Initial RGB values {r, g, b} in [0, 1] (default: {0, 0, 0})
  - `:alpha` - Initial alpha value (default: 0.0)
  - `:hidden` - Initial hidden state (default: zeros)
  - `:channels` - Total channels (default: 16)
  """
  def new_cell(opts \\ []) do
    channels = Keyword.get(opts, :channels, @state_channels)
    {r, g, b} = Keyword.get(opts, :rgb, {0.0, 0.0, 0.0})
    alpha = Keyword.get(opts, :alpha, 0.0)
    hidden = Keyword.get(opts, :hidden, List.duplicate(0.0, channels - 4))

    Nx.tensor([r, g, b, alpha | hidden], type: :f32)
  end

  @doc """
  Create a seed cell (the starting point for growth).

  Seed cells have alpha=1.0 and white RGB.
  """
  def seed_cell do
    # RGB = white, alpha = 1, hidden = 0
    hidden = List.duplicate(0.0, @state_channels - 4)
    Nx.tensor([1.0, 1.0, 1.0, 1.0 | hidden], type: :f32)
  end

  @doc """
  Check if a cell is "alive" (alpha > 0.1).
  """
  def alive?(cell_state) do
    alpha = Nx.to_number(Nx.slice(cell_state, [3], [1]))
    alpha > 0.1
  end

  # ═══════════════════════════════════════════════════════════════
  # PERCEPTION (Sobel Gradient Sensing)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute perception vector for entire grid.

  Input: state_grid of shape {H, W, 16}
  Output: perception_grid of shape {H, W, 48}

  The perception consists of:
  - Original state (16 channels)
  - Sobel-x gradient (16 channels)
  - Sobel-y gradient (16 channels)
  """
  def perceive(state_grid) do
    # Compute gradients for each channel
    grad_x = sobel_gradient_x(state_grid)
    grad_y = sobel_gradient_y(state_grid)
    
    # Concatenate: [state, grad_x, grad_y]
    Nx.concatenate([state_grid, grad_x, grad_y], axis: 2)
  end

  @doc """
  Compute Sobel gradient in X direction for all channels.
  """
  def sobel_gradient_x(state_grid) do
    apply_sobel_filter(state_grid, sobel_x())
  end

  @doc """
  Compute Sobel gradient in Y direction for all channels.
  """
  def sobel_gradient_y(state_grid) do
    apply_sobel_filter(state_grid, sobel_y())
  end

  defp apply_sobel_filter(state_grid, kernel) do
    {h, w, c} = Nx.shape(state_grid)
    
    # Pad the grid for convolution (same padding)
    padded = Nx.pad(state_grid, 0.0, [{1, 1, 0}, {1, 1, 0}, {0, 0, 0}])
    
    # Convolve each channel
    results = 
      for channel <- 0..(c - 1) do
        channel_data = Nx.slice(padded, [0, 0, channel], [h + 2, w + 2, 1])
        channel_data = Nx.squeeze(channel_data, axes: [2])
        convolved = convolve_2d(channel_data, kernel)
        Nx.reshape(convolved, {h, w, 1})
      end
    
    Nx.concatenate(results, axis: 2)
  end

  defp convolve_2d(input, kernel) do
    {ih, iw} = Nx.shape(input)
    {kh, kw} = Nx.shape(kernel)
    
    oh = ih - kh + 1
    ow = iw - kw + 1
    
    # Build output via sliding window
    rows = 
      for i <- 0..(oh - 1) do
        cols = 
          for j <- 0..(ow - 1) do
            # Extract patch and compute convolution
            patch = Nx.slice(input, [i, j], [kh, kw])
            Nx.sum(Nx.multiply(patch, kernel))
          end
        Nx.stack(cols)
      end
    
    Nx.stack(rows)
  end

  # ═══════════════════════════════════════════════════════════════
  # PERCEPTION FOR 3D THUNDERBIT GRIDS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute 3D perception for Thunderbit lattice.

  Uses 3D central difference for gradient estimation in x, y, z directions.
  """
  def perceive_3d(state_grid) do
    # 3D Sobel approximation: compute gradients in each axis
    grad_x = gradient_3d_x(state_grid)
    grad_y = gradient_3d_y(state_grid)
    grad_z = gradient_3d_z(state_grid)
    
    # Concatenate: [state, grad_x, grad_y, grad_z]
    Nx.concatenate([state_grid, grad_x, grad_y, grad_z], axis: 3)
  end

  defp gradient_3d_x(grid) do
    {x, y, z, c} = Nx.shape(grid)
    
    # Central difference in x direction
    left = Nx.slice(grid, [0, 0, 0, 0], [x - 2, y, z, c])
    right = Nx.slice(grid, [2, 0, 0, 0], [x - 2, y, z, c])
    center_grad = Nx.divide(Nx.subtract(right, left), 2.0)
    
    # Pad to original size
    Nx.pad(center_grad, 0.0, [{1, 1, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}])
  end

  defp gradient_3d_y(grid) do
    {x, y, z, c} = Nx.shape(grid)
    
    left = Nx.slice(grid, [0, 0, 0, 0], [x, y - 2, z, c])
    right = Nx.slice(grid, [0, 2, 0, 0], [x, y - 2, z, c])
    center_grad = Nx.divide(Nx.subtract(right, left), 2.0)
    
    Nx.pad(center_grad, 0.0, [{0, 0, 0}, {1, 1, 0}, {0, 0, 0}, {0, 0, 0}])
  end

  defp gradient_3d_z(grid) do
    {x, y, z, c} = Nx.shape(grid)
    
    left = Nx.slice(grid, [0, 0, 0, 0], [x, y, z - 2, c])
    right = Nx.slice(grid, [0, 0, 2, 0], [x, y, z - 2, c])
    center_grad = Nx.divide(Nx.subtract(right, left), 2.0)
    
    Nx.pad(center_grad, 0.0, [{0, 0, 0}, {0, 0, 0}, {1, 1, 0}, {0, 0, 0}])
  end

  # ═══════════════════════════════════════════════════════════════
  # ALIVE MASKING
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply alive masking to state grid.

  Cells are considered "alive" if they or any neighbor has alpha > 0.1.
  Dead cells have their state set to zero.
  """
  def apply_alive_mask(state_grid) do
    {h, w, c} = Nx.shape(state_grid)
    
    # Extract alpha channel
    alpha = Nx.slice(state_grid, [0, 0, @alpha_channel], [h, w, 1])
    alpha = Nx.squeeze(alpha, axes: [2])
    
    # Max pool over 3x3 to check if any neighbor is alive
    alive_mask = max_pool_2d(alpha, 3)
    alive_mask = Nx.greater(alive_mask, 0.1)
    
    # Broadcast mask to all channels and apply
    mask_3d = Nx.new_axis(alive_mask, 2)
    mask_3d = Nx.broadcast(mask_3d, {h, w, c})
    
    zeros = Nx.broadcast(Nx.tensor(0.0, type: :f32), {h, w, c})
    Nx.select(mask_3d, state_grid, zeros)
  end

  defp max_pool_2d(input, kernel_size) do
    {h, w} = Nx.shape(input)
    pad = div(kernel_size, 2)
    
    # Pad with very negative value for max pooling
    padded = Nx.pad(input, -1.0e9, [{pad, pad, 0}, {pad, pad, 0}])
    
    # Max over each kernel_size x kernel_size window
    rows = 
      for i <- 0..(h - 1) do
        cols = 
          for j <- 0..(w - 1) do
            patch = Nx.slice(padded, [i, j], [kernel_size, kernel_size])
            Nx.reduce_max(patch)
          end
        Nx.stack(cols)
      end
    
    Nx.stack(rows)
  end
end
