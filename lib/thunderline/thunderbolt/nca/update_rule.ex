defmodule Thunderline.Thunderbolt.NCA.UpdateRule do
  @moduledoc """
  Neural Cellular Automata Update Rule.

  Based on: "Growing Neural Cellular Automata" (Distill, Google Research, 2020)

  Implements the learned update rule that takes a perception vector and
  outputs a state delta. Combined with stochastic updates and alive masking,
  this enables self-organizing, regenerating patterns.

  ## Architecture

  Perception (48 channels)
       │
       ▼
  Dense Layer    48 → 128 (ReLU)
       │
       ▼
  Dense Layer    128 → 16 (Linear, zero-init)
       │
       ▼
  State Delta (16 channels)

  The final layer is initialized with zeros to produce "do nothing" initially.

  ## Reference

  Mordvintsev et al., "Growing Neural Cellular Automata", Distill 2020
  """

  alias Thunderline.Thunderbolt.NCA.Perception

  # 16 state + 16 grad_x + 16 grad_y
  @perception_dim 48
  @hidden_dim 128
  @state_dim 16

  # ═══════════════════════════════════════════════════════════════
  # PARAMETER INITIALIZATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Initialize update rule parameters.

  Uses Xavier initialization for first layer and zero initialization
  for output layer (to start with "do nothing" behavior).
  """
  def initialize_params(opts \\ []) do
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))
    _channels = Keyword.get(opts, :channels, @state_dim)
    key = Nx.Random.key(seed)

    # First layer: perception → hidden (Xavier init)
    scale_w1 = :math.sqrt(2.0 / (@perception_dim + @hidden_dim))
    {w1, key} = Nx.Random.normal(key, 0.0, scale_w1, shape: {@perception_dim, @hidden_dim})
    {b1, _key} = Nx.Random.normal(key, 0.0, 0.01, shape: {@hidden_dim})

    # Output layer: hidden → state delta (ZERO init for "do nothing")
    w2 = Nx.broadcast(0.0, {@hidden_dim, @state_dim})
    b2 = Nx.broadcast(0.0, {@state_dim})

    %{
      w1: w1,
      b1: b1,
      w2: w2,
      b2: b2,
      perception_dim: @perception_dim,
      hidden_dim: @hidden_dim,
      state_dim: @state_dim,
      version: 1,
      created_at: DateTime.utc_now()
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # UPDATE RULE FORWARD PASS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply update rule to perception vector(s).

  Input: perception tensor of shape {..., 48}
  Output: state delta tensor of shape {..., 16}
  """
  def forward(perception, params) do
    # Layer 1: Dense + ReLU
    z1 = Nx.add(Nx.dot(perception, params.w1), params.b1)
    # ReLU
    h1 = Nx.max(z1, 0)

    # Layer 2: Dense (no activation - residual update)
    Nx.add(Nx.dot(h1, params.w2), params.b2)
  end

  # ═══════════════════════════════════════════════════════════════
  # STOCHASTIC UPDATE
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply stochastic cell update.

  Each cell independently decides whether to update with probability update_prob.
  This removes the need for global synchronization.
  """
  def stochastic_update(state_grid, delta_grid, update_prob \\ 0.5) do
    {h, w, c} = Nx.shape(state_grid)

    # Generate random mask
    key = Nx.Random.key(System.system_time(:nanosecond))
    {rand_mask, _key} = Nx.Random.uniform(key, shape: {h, w, 1})

    # Cells update if random < update_prob
    update_mask = Nx.less(rand_mask, update_prob)
    update_mask = Nx.broadcast(update_mask, {h, w, c})

    # Apply masked update
    zeros = Nx.broadcast(Nx.tensor(0.0, type: :f32), {h, w, c})
    masked_delta = Nx.select(update_mask, delta_grid, zeros)
    Nx.add(state_grid, masked_delta)
  end

  # ═══════════════════════════════════════════════════════════════
  # FULL NCA STEP
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Perform one full NCA update step.

  1. Perceive: compute gradients and form perception vectors
  2. Update: apply learned update rule
  3. Stochastic: randomly mask which cells update
  4. Alive mask: zero out dead cells
  """
  def step(state_grid, params, opts \\ []) do
    update_prob = Keyword.get(opts, :update_prob, 0.5)

    # 1. Perceive
    perception = Perception.perceive(state_grid)

    # 2. Apply update rule to get deltas
    # Reshape for batch processing
    {h, w, _p} = Nx.shape(perception)
    perception_flat = Nx.reshape(perception, {h * w, @perception_dim})

    delta_flat = forward(perception_flat, params)
    delta_grid = Nx.reshape(delta_flat, {h, w, @state_dim})

    # 3. Stochastic update
    updated = stochastic_update(state_grid, delta_grid, update_prob)

    # 4. Alive masking
    Perception.apply_alive_mask(updated)
  end

  @doc """
  Run multiple NCA steps.
  """
  def run_steps(state_grid, params, n_steps, opts \\ []) do
    Enum.reduce(1..n_steps, state_grid, fn _i, grid ->
      step(grid, params, opts)
    end)
  end

  # ═══════════════════════════════════════════════════════════════
  # TRAINING
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute L2 loss between current grid RGBA and target.

  Only compares the first 4 channels (RGB + Alpha).
  """
  def rgba_loss(state_grid, target_rgba) do
    {h, w, _c} = Nx.shape(state_grid)

    # Extract RGBA from state
    current_rgba = Nx.slice(state_grid, [0, 0, 0], [h, w, 4])

    # L2 loss
    diff = Nx.subtract(current_rgba, target_rgba)
    Nx.mean(Nx.pow(diff, 2))
  end

  @doc """
  Update parameters with SGD.
  """
  def update_params(params, gradients, learning_rate \\ 0.001) do
    %{
      params
      | w1: Nx.subtract(params.w1, Nx.multiply(gradients.w1, learning_rate)),
        b1: Nx.subtract(params.b1, Nx.multiply(gradients.b1, learning_rate)),
        w2: Nx.subtract(params.w2, Nx.multiply(gradients.w2, learning_rate)),
        b2: Nx.subtract(params.b2, Nx.multiply(gradients.b2, learning_rate)),
        version: params.version + 1
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # SERIALIZATION
  # ═══════════════════════════════════════════════════════════════

  def serialize(params) do
    serializable = %{
      params
      | w1: Nx.to_binary(params.w1),
        b1: Nx.to_binary(params.b1),
        w2: Nx.to_binary(params.w2),
        b2: Nx.to_binary(params.b2)
    }

    :erlang.term_to_binary(serializable)
  end

  def deserialize(binary) do
    params = :erlang.binary_to_term(binary)

    %{
      params
      | w1: Nx.from_binary(params.w1, :f32) |> Nx.reshape({@perception_dim, @hidden_dim}),
        b1: Nx.from_binary(params.b1, :f32) |> Nx.reshape({@hidden_dim}),
        w2: Nx.from_binary(params.w2, :f32) |> Nx.reshape({@hidden_dim, @state_dim}),
        b2: Nx.from_binary(params.b2, :f32) |> Nx.reshape({@state_dim})
    }
  end
end
