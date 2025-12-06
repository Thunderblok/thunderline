defmodule Thunderline.Thunderbolt.NCA.ViTCAUpdateRule do
  @moduledoc """
  Attention-based Neural Cellular Automata Update Rule (ViTCA).

  This module implements a variant of the NCA where the fixed perception kernels (Sobel)
  are replaced/augmented by a local Self-Attention mechanism.

  Each cell attends to its 3x3 neighborhood to compute its update vector.
  This allows the CA to learn dynamic, context-dependent perception filters
  rather than relying on fixed gradients.

  ## Architecture

  1. **Patch Extraction**: For each cell, extract the 3x3 neighborhood of state vectors.
  2. **Local Attention**:
     - Query (Q) from the center cell.
     - Keys (K) and Values (V) from the 9 neighbors.
     - Attention = softmax(Q * K^T / sqrt(d)) * V
  3. **Update MLP**:
     - The attention output is passed through a Dense -> ReLU -> Dense MLP.
     - Output is the state delta.

  ## Parameters

  - `w_q`, `w_k`, `w_v`: Attention projection matrices.
  - `w_o`: Attention output projection.
  - `w1`, `b1`, `w2`, `b2`: MLP parameters.
  """

  alias Thunderline.Thunderbolt.NCA.Perception
  import Nx.Defn

  @state_dim 16
  @hidden_dim 128
  @head_dim 16  # Dimension for Q, K, V projections

  # ═══════════════════════════════════════════════════════════════
  # PARAMETER INITIALIZATION
  # ═══════════════════════════════════════════════════════════════

  def initialize_params(opts \\ []) do
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))
    key = Nx.Random.key(seed)

    # -- Attention Parameters --
    # Projections for Q, K, V (Linear layers without bias for simplicity)
    scale_attn = :math.sqrt(2.0 / (@state_dim + @head_dim))
    {w_q, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {@state_dim, @head_dim})
    {w_k, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {@state_dim, @head_dim})
    {w_v, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {@state_dim, @head_dim})
    
    # Output projection (Head dim -> State dim) to match MLP input expectation
    # or we can feed head_dim directly to MLP. Let's project back to state_dim size
    # to keep the "perception" vector size consistent-ish, or just feed head_dim.
    # Let's feed @head_dim directly to MLP to save params.
    
    # -- MLP Parameters --
    # Input to MLP is the output of attention (size @head_dim)
    # Layer 1: Attention Output -> Hidden
    scale_w1 = :math.sqrt(2.0 / (@head_dim + @hidden_dim))
    {w1, key} = Nx.Random.normal(key, 0.0, scale_w1, shape: {@head_dim, @hidden_dim})
    {b1, key} = Nx.Random.normal(key, 0.0, 0.01, shape: {@hidden_dim})

    # Layer 2: Hidden -> State Delta (Zero init)
    w2 = Nx.broadcast(0.0, {@hidden_dim, @state_dim})
    b2 = Nx.broadcast(0.0, {@state_dim})

    %{
      w_q: w_q,
      w_k: w_k,
      w_v: w_v,
      w1: w1,
      b1: b1,
      w2: w2,
      b2: b2,
      state_dim: @state_dim,
      head_dim: @head_dim,
      hidden_dim: @hidden_dim,
      version: 1,
      type: :vit_ca
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # LOCAL ATTENTION MECHANISM
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Extracts 3x3 neighborhoods for all cells.
  Returns tensor of shape {H, W, 9, C} where 9 is the number of neighbors.
  """
  def extract_neighborhoods(grid) do
    {h, w, c} = Nx.shape(grid)
    
    # Pad grid to handle boundaries (circular padding is common for CA, but zero/replicate works too)
    # Using constant 0 padding for now to match standard NCA behavior
    padded = Nx.pad(grid, 0.0, [{1, 1, 0}, {1, 1, 0}, {0, 0, 0}])
    
    # We want to stack 9 shifts of the grid
    # Top-Left, Top-Mid, Top-Right, etc.
    
    shifts = for dy <- 0..2, dx <- 0..2 do
      Nx.slice(padded, [dy, dx, 0], [h, w, c])
    end
    
    # Stack along a new neighbor axis (axis 2)
    # Result: {H, W, 9, C}
    Nx.stack(shifts, axis: 2)
  end

  @doc """
  Computes local attention for the grid.
  
  1. Center cell (the one being updated) provides Query.
  2. All 9 neighbors (including self) provide Keys and Values.
  """
  def attention_inference(grid, params) do
    {h, w, _c} = Nx.shape(grid)
    
    # 1. Get Neighborhoods: {H, W, 9, C}
    neighbors = extract_neighborhoods(grid)
    
    # 2. Compute Query (Q) from center cells (original grid)
    # Grid: {H, W, C} -> Dot -> {H, W, HeadDim}
    q = Nx.dot(grid, params.w_q)
    
    # 3. Compute Keys (K) and Values (V) from neighbors
    # Neighbors: {H, W, 9, C}
    # We need to apply dot product to the last axis (C)
    # Nx.dot operates on the last axis of A and first of B usually, but here we have extra dims.
    # We can reshape to apply dense layer then reshape back.
    
    neighbors_flat = Nx.reshape(neighbors, {h * w * 9, @state_dim})
    
    k_flat = Nx.dot(neighbors_flat, params.w_k)
    v_flat = Nx.dot(neighbors_flat, params.w_v)
    
    k = Nx.reshape(k_flat, {h, w, 9, @head_dim})
    v = Nx.reshape(v_flat, {h, w, 9, @head_dim})
    
    # 4. Calculate Attention Scores
    # Q: {H, W, HeadDim} -> expand to {H, W, 1, HeadDim}
    q_expanded = Nx.new_axis(q, 2)
    
    # Dot product Q * K^T
    # We want {H, W, 1, HeadDim} * {H, W, 9, HeadDim} -> {H, W, 1, 9} (scores per neighbor)
    # Nx.multiply is element-wise. We need a dot product over the HeadDim axis.
    # sum(q * k, axis: -1)
    
    scores = Nx.sum(Nx.multiply(q_expanded, k), axes: [-1]) # {H, W, 9}
    
    # Scale
    scale = :math.sqrt(@head_dim)
    scores = Nx.divide(scores, scale)
    
    # Softmax over neighbors (axis 2)
    attn_weights = Nx.exp(scores)
    sum_weights = Nx.sum(attn_weights, axes: [2], keep_axes: true)
    attn_weights = Nx.divide(attn_weights, sum_weights) # {H, W, 9}
    
    # 5. Aggregate Values
    # Weights: {H, W, 9} -> expand to {H, W, 9, 1}
    weights_expanded = Nx.new_axis(attn_weights, 3)
    
    # Weighted sum of V
    # sum(weights * V, axis: 2) -> {H, W, HeadDim}
    weighted_v = Nx.multiply(weights_expanded, v)
    context_vector = Nx.sum(weighted_v, axes: [2])
    
    context_vector
  end

  # ═══════════════════════════════════════════════════════════════
  # UPDATE RULE
  # ═══════════════════════════════════════════════════════════════

  def forward(grid, params) do
    # 1. Attention Step
    # Output: {H, W, HeadDim}
    attn_out = attention_inference(grid, params)
    
    # 2. MLP Step
    # Layer 1: Dense + ReLU
    z1 = Nx.add(Nx.dot(attn_out, params.w1), params.b1)
    h1 = Nx.max(z1, 0)
    
    # Layer 2: Dense (Output)
    Nx.add(Nx.dot(h1, params.w2), params.b2)
  end

  # ═══════════════════════════════════════════════════════════════
  # STEP FUNCTION (Compatible with Standard NCA)
  # ═══════════════════════════════════════════════════════════════

  def step(state_grid, params, opts \\ []) do
    update_prob = Keyword.get(opts, :update_prob, 0.5)

    # 1. Compute Update (Attention + MLP)
    delta_grid = forward(state_grid, params)

    # 2. Stochastic Update (Same as standard NCA)
    {h, w, c} = Nx.shape(state_grid)
    key = Nx.Random.key(System.system_time(:nanosecond))
    {rand_mask, _key} = Nx.Random.uniform(key, shape: {h, w, 1})
    
    update_mask = Nx.less(rand_mask, update_prob)
    update_mask = Nx.broadcast(update_mask, {h, w, c})
    
    zeros = Nx.broadcast(Nx.tensor(0.0, type: :f32), {h, w, c})
    masked_delta = Nx.select(update_mask, delta_grid, zeros)
    
    updated_grid = Nx.add(state_grid, masked_delta)

    # 3. Alive Masking (Reuse standard logic)
    Perception.apply_alive_mask(updated_grid)
  end
  
  # ═══════════════════════════════════════════════════════════════
  # UTILS
  # ═══════════════════════════════════════════════════════════════
  
  def run_steps(state_grid, params, n_steps, opts \\ []) do
    Enum.reduce(1..n_steps, state_grid, fn _i, grid ->
      step(grid, params, opts)
    end)
  end
end
