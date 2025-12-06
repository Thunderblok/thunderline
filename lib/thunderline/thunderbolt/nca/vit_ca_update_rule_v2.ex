defmodule Thunderline.Thunderbolt.NCA.ViTCAUpdateRuleV2 do
  @moduledoc """
  Vision Transformer Cellular Automata (ViTCA) Update Rule - V2.

  Implements the learnings from "Attention-based Neural Cellular Automata" (Tesfaldet et al., 2022).

  ## Key Improvements over V1:
  1. **Relative Positional Encodings**: Adds learnable embeddings to neighbor Keys/Values to restore directionality (anisotropy), which pure attention lacks.
  2. **Multi-Head Attention**: Allows the CA to attend to multiple distinct features of the neighborhood simultaneously.
  3. **Layer Normalization**: Stabilizes training dynamics.
  4. **Transformer Block Structure**: Follows the standard `x + Sublayer(LayerNorm(x))` pattern.

  ## Architecture
  Input (Grid) -> [Extract 3x3 Patches]
      -> LayerNorm
      -> Multi-Head Self-Attention (with Relative Positional Encodings)
      -> Residual Connection
      -> LayerNorm
      -> MLP (Dense -> GELU -> Dense)
      -> Residual Connection
      -> Output (Update Vector)
  """

  alias Thunderline.Thunderbolt.NCA.Perception
  import Nx.Defn

  @state_dim 16
  @hidden_dim 64
  @num_heads 4
  @head_dim 16 # Total inner dim = num_heads * head_dim = 64
  @neighbor_count 9 # 3x3 neighborhood

  # ═══════════════════════════════════════════════════════════════
  # PARAMETER INITIALIZATION
  # ═══════════════════════════════════════════════════════════════

  def initialize_params(opts \\ []) do
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))
    key = Nx.Random.key(seed)

    inner_dim = @num_heads * @head_dim

    # -- Attention Parameters --
    # Q, K, V Projections: StateDim -> InnerDim
    scale_attn = :math.sqrt(2.0 / (@state_dim + inner_dim))
    {w_q, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {@state_dim, inner_dim})
    {w_k, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {@state_dim, inner_dim})
    {w_v, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {@state_dim, inner_dim})
    
    # Output Projection: InnerDim -> StateDim
    {w_o, key} = Nx.Random.normal(key, 0.0, scale_attn, shape: {inner_dim, @state_dim})

    # -- Relative Positional Encodings --
    # One vector per neighbor position (9) per head
    # Shape: {9, NumHeads, HeadDim}
    # We add this to the Key (and optionally Value)
    {pos_emb, key} = Nx.Random.normal(key, 0.0, 0.02, shape: {@neighbor_count, @num_heads, @head_dim})

    # -- MLP Parameters --
    # Layer 1: StateDim -> HiddenDim
    scale_w1 = :math.sqrt(2.0 / (@state_dim + @hidden_dim))
    {w1, key} = Nx.Random.normal(key, 0.0, scale_w1, shape: {@state_dim, @hidden_dim})
    {b1, key} = Nx.Random.normal(key, 0.0, 0.01, shape: {@hidden_dim})

    # Layer 2: HiddenDim -> StateDim (Zero init for identity start)
    w2 = Nx.broadcast(0.0, {@hidden_dim, @state_dim})
    b2 = Nx.broadcast(0.0, {@state_dim})

    # -- LayerNorm Parameters --
    # Gamma (scale) and Beta (shift)
    gamma1 = Nx.broadcast(1.0, {@state_dim})
    beta1 = Nx.broadcast(0.0, {@state_dim})
    gamma2 = Nx.broadcast(1.0, {@state_dim})
    beta2 = Nx.broadcast(0.0, {@state_dim})

    %{
      w_q: w_q, w_k: w_k, w_v: w_v, w_o: w_o,
      pos_emb: pos_emb,
      w1: w1, b1: b1, w2: w2, b2: b2,
      gamma1: gamma1, beta1: beta1,
      gamma2: gamma2, beta2: beta2,
      config: %{
        state_dim: @state_dim,
        num_heads: @num_heads,
        head_dim: @head_dim
      }
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # CORE MECHANISMS
  # ═══════════════════════════════════════════════════════════════

  def layer_norm(x, gamma, beta, eps \\ 1.0e-5) do
    mean = Nx.mean(x, axes: [-1], keep_axes: true)
    var = Nx.variance(x, axes: [-1], keep_axes: true)
    x_norm = (x - mean) / Nx.sqrt(var + eps)
    x_norm * gamma + beta
  end

  def extract_neighborhoods(grid) do
    {h, w, c} = Nx.shape(grid)
    padded = Nx.pad(grid, 0.0, [{1, 1, 0}, {1, 1, 0}, {0, 0, 0}])
    
    shifts = for dy <- 0..2, dx <- 0..2 do
      Nx.slice(padded, [dy, dx, 0], [h, w, c])
    end
    
    # {H, W, 9, C}
    Nx.stack(shifts, axis: 2)
  end

  def multi_head_attention(grid, params) do
    {h, w, _c} = Nx.shape(grid)
    
    # 1. Extract Neighborhoods: {H, W, 9, C}
    neighbors = extract_neighborhoods(grid)
    
    # 2. Projections
    # Query: From Center Cell {H, W, C} -> {H, W, InnerDim}
    q = Nx.dot(grid, params.w_q)
    
    # Keys/Values: From Neighbors {H, W, 9, C} -> {H, W, 9, InnerDim}
    # Flatten spatial dims for dot product
    neighbors_flat = Nx.reshape(neighbors, {h * w * 9, @state_dim})
    k_flat = Nx.dot(neighbors_flat, params.w_k)
    v_flat = Nx.dot(neighbors_flat, params.w_v)
    
    # Reshape and Split Heads
    # InnerDim = NumHeads * HeadDim
    # Q: {H, W, NumHeads, HeadDim}
    q = Nx.reshape(q, {h, w, @num_heads, @head_dim})
    
    # K, V: {H, W, 9, NumHeads, HeadDim}
    k = Nx.reshape(k_flat, {h, w, 9, @num_heads, @head_dim})
    v = Nx.reshape(v_flat, {h, w, 9, @num_heads, @head_dim})
    
    # 3. Add Relative Positional Encodings to Keys
    # pos_emb: {9, NumHeads, HeadDim}
    # Broadcast to {H, W, 9, NumHeads, HeadDim}
    k = Nx.add(k, params.pos_emb)

    # 4. Attention Scores (Scaled Dot-Product)
    # Q: {H, W, NumHeads, HeadDim} -> Expand to {H, W, 1, NumHeads, HeadDim}
    q_expanded = Nx.new_axis(q, 2)
    
    # Dot product over HeadDim axis
    # {H, W, 1, NH, HD} * {H, W, 9, NH, HD} -> {H, W, 9, NH}
    scores = Nx.sum(q_expanded * k, axes: [-1])
    scores = scores / :math.sqrt(@head_dim)
    
    # Softmax over neighbors (axis 2)
    attn_weights = Nx.exp(scores)
    sum_weights = Nx.sum(attn_weights, axes: [2], keep_axes: true)
    attn_weights = attn_weights / sum_weights # {H, W, 9, NH}
    
    # 5. Aggregate Values
    # Weights: {H, W, 9, NH} -> Expand to {H, W, 9, NH, 1}
    weights_expanded = Nx.new_axis(attn_weights, 4)
    
    # Weighted Sum: sum(Weights * V, axis: 2)
    # {H, W, 9, NH, 1} * {H, W, 9, NH, HD} -> {H, W, 9, NH, HD}
    # Sum over neighbors -> {H, W, NH, HD}
    weighted_v = Nx.sum(weights_expanded * v, axes: [2])
    
    # 6. Concatenate Heads and Output Projection
    # {H, W, NH, HD} -> {H, W, InnerDim}
    concat_v = Nx.reshape(weighted_v, {h, w, @num_heads * @head_dim})
    
    # Project back to StateDim
    Nx.dot(concat_v, params.w_o)
  end

  # ═══════════════════════════════════════════════════════════════
  # FORWARD PASS (Transformer Block)
  # ═══════════════════════════════════════════════════════════════

  def forward(grid, params) do
    # Block 1: Attention
    # x = x + Attn(LN(x))
    norm1 = layer_norm(grid, params.gamma1, params.beta1)
    attn_out = multi_head_attention(norm1, params)
    x = Nx.add(grid, attn_out)
    
    # Block 2: MLP
    # x = x + MLP(LN(x))
    norm2 = layer_norm(x, params.gamma2, params.beta2)
    
    # MLP: Dense -> GELU -> Dense
    # Using ReLU here for simplicity/speed, GELU is standard for ViT
    hidden = Nx.dot(norm2, params.w1) |> Nx.add(params.b1)
    hidden = Nx.max(hidden, 0.0) # ReLU
    mlp_out = Nx.dot(hidden, params.w2) |> Nx.add(params.b2)
    
    # Final Residual (The output is the delta to be applied to the grid)
    # Note: In standard ViT, we return the new state. 
    # In NCA, we usually return a delta.
    # However, since we initialized the final dense layer to zero, 
    # `mlp_out` starts as 0.
    # If we return `mlp_out`, that is the delta.
    # But we also have the `attn_out` residual.
    # Let's return the accumulated delta from the input `grid`.
    
    # Total Delta = (x_final - grid_initial)
    # x_final = grid + attn_out + mlp_out
    # Delta = attn_out + mlp_out
    
    Nx.add(attn_out, mlp_out)
  end

  # ═══════════════════════════════════════════════════════════════
  # STEP FUNCTION
  # ═══════════════════════════════════════════════════════════════

  def step(state_grid, params, opts \\ []) do
    update_prob = Keyword.get(opts, :update_prob, 0.5)

    # 1. Compute Update Delta
    delta_grid = forward(state_grid, params)

    # 2. Stochastic Update Mask
    {h, w, c} = Nx.shape(state_grid)
    key = Nx.Random.key(System.system_time(:nanosecond))
    {rand_mask, _key} = Nx.Random.uniform(key, shape: {h, w, 1})
    
    update_mask = Nx.less(rand_mask, update_prob)
    update_mask = Nx.broadcast(update_mask, {h, w, c})
    
    zeros = Nx.broadcast(0.0, {h, w, c})
    masked_delta = Nx.select(update_mask, delta_grid, zeros)
    
    updated_grid = Nx.add(state_grid, masked_delta)

    # 3. Alive Masking
    Perception.apply_alive_mask(updated_grid)
  end
end
