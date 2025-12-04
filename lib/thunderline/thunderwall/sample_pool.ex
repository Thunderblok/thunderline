defmodule Thunderline.Thunderwall.SamplePool do
  @moduledoc """
  Sample Pool Training for Growing NCAs.

  Based on: "Growing Neural Cellular Automata" (Distill 2020)

  The key insight: train NCAs by maintaining a pool of partially-grown states.
  At each step, randomly sample from the pool, run NCA for random steps,
  and replace the highest-loss sample with the seed.

  ## Why It Works

  1. **Temporal consistency**: Forces NCA to maintain stable patterns over time
  2. **Self-healing**: Damaged states in pool learn to recover
  3. **Diverse training**: Pool contains states at various growth stages
  4. **Avoids collapse**: Seed injection prevents runaway dynamics

  ## Algorithm

  ```
  1. Initialize pool with seed state
  2. For each training step:
     a. Sample batch from pool
     b. Run NCA for N steps (N ~ Uniform[64, 96])
     c. Compute loss against target
     d. Update NCA parameters via gradient descent
     e. Replace highest-loss sample with fresh seed
     f. Write batch back to pool (with damage injection)
  ```

  ## Reference

  Mordvintsev et al., "Growing Neural Cellular Automata", Distill 2020
  """

  require Logger

  alias Thunderline.Thunderbolt.NCA.UpdateRule

  defstruct [
    # Pool of state tensors
    :states,
    # Loss value for each state
    :losses,
    # Number of states in pool
    :pool_size,
    # Shape of each state tensor
    :state_shape,
    # Target pattern to grow towards
    :target,
    # Seed state for injection
    :seed,
    # NCA network parameters
    :nca_params,
    # {min_steps, max_steps} for random rollouts
    :step_range,
    # Probability of damaging states before return
    :damage_prob
  ]

  @type t :: %__MODULE__{
          states: [Nx.Tensor.t()],
          losses: [float()],
          pool_size: non_neg_integer(),
          state_shape: tuple(),
          target: Nx.Tensor.t(),
          seed: Nx.Tensor.t(),
          nca_params: map(),
          step_range: {non_neg_integer(), non_neg_integer()},
          damage_prob: float()
        }

  @default_pool_size 1024
  @default_step_range {64, 96}
  @default_damage_prob 0.5
  @default_batch_size 8

  # ═══════════════════════════════════════════════════════════════
  # CONSTRUCTION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Create a new sample pool.

  ## Arguments

  - `target` - Target pattern to grow towards (H x W x C tensor)
  - `opts` - Options:
    - `:pool_size` - Number of states (default: 1024)
    - `:step_range` - {min, max} steps per rollout (default: {64, 96})
    - `:damage_prob` - Probability of damage injection (default: 0.5)
    - `:channels` - Hidden channels for NCA (default: 16)
  """
  @spec new(Nx.Tensor.t(), keyword()) :: t()
  def new(target, opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    step_range = Keyword.get(opts, :step_range, @default_step_range)
    damage_prob = Keyword.get(opts, :damage_prob, @default_damage_prob)
    channels = Keyword.get(opts, :channels, 16)

    {h, w, _c} = Nx.shape(target)
    state_shape = {h, w, channels}

    # Create seed (center cell alive)
    seed = create_seed(state_shape)

    # Initialize pool with seeds
    states = List.duplicate(seed, pool_size)
    # High initial loss
    losses = List.duplicate(1.0, pool_size)

    # Initialize NCA parameters
    nca_params = UpdateRule.initialize_params(channels: channels)

    %__MODULE__{
      states: states,
      losses: losses,
      pool_size: pool_size,
      state_shape: state_shape,
      target: target,
      seed: seed,
      nca_params: nca_params,
      step_range: step_range,
      damage_prob: damage_prob
    }
  end

  defp create_seed({h, w, c}) do
    # Center cell is alive, rest are zeros
    zeros = Nx.broadcast(0.0, {h, w, c})

    cx = div(h, 2)
    cy = div(w, 2)

    # Set center cell: RGB white + alpha 1.0 + zeros for hidden
    seed_cell = [1.0, 1.0, 1.0, 1.0] ++ List.duplicate(0.0, c - 4)
    seed_tensor = Nx.tensor([seed_cell]) |> Nx.reshape({1, 1, c})

    Nx.put_slice(zeros, [cx, cy, 0], seed_tensor)
  end

  # ═══════════════════════════════════════════════════════════════
  # TRAINING STEP
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Execute one training step.

  1. Sample batch from pool
  2. Run NCA for random steps
  3. Compute loss and gradients
  4. Update parameters
  5. Replace worst sample with seed
  6. Write batch back (with damage)

  ## Returns

  `{updated_pool, batch_loss}`
  """
  @spec train_step(t(), keyword()) :: {t(), float()}
  def train_step(pool, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    learning_rate = Keyword.get(opts, :learning_rate, 2.0e-3)

    # Sample batch indices
    indices = sample_indices(pool.pool_size, batch_size)

    # Get batch states
    batch_states = Enum.map(indices, fn idx -> Enum.at(pool.states, idx) end)

    # Random number of steps
    {min_steps, max_steps} = pool.step_range
    n_steps = :rand.uniform(max_steps - min_steps + 1) + min_steps - 1

    # Run NCA for n_steps and compute gradients
    {final_states, batch_loss, grad} =
      rollout_and_grad(batch_states, pool.nca_params, pool.target, n_steps)

    # Update parameters
    updated_params = apply_gradients(pool.nca_params, grad, learning_rate)

    # Compute per-sample losses for pool management
    per_sample_losses = compute_per_sample_losses(final_states, pool.target)

    # Optionally damage states before returning to pool
    damaged_states = maybe_damage_states(final_states, pool.damage_prob)

    # Write batch back to pool
    updated_states = write_batch_to_pool(pool.states, indices, damaged_states)
    updated_losses = write_batch_to_pool(pool.losses, indices, per_sample_losses)

    # Replace highest loss sample with seed
    {states_with_seed, losses_with_seed} =
      inject_seed(updated_states, updated_losses, pool.seed)

    updated_pool = %{
      pool
      | states: states_with_seed,
        losses: losses_with_seed,
        nca_params: updated_params
    }

    Logger.debug("[SamplePool] step complete, loss=#{Float.round(batch_loss, 5)}")

    {updated_pool, batch_loss}
  end

  defp sample_indices(pool_size, batch_size) do
    # Sample without replacement
    0..(pool_size - 1)
    |> Enum.shuffle()
    |> Enum.take(batch_size)
  end

  defp rollout_and_grad(batch_states, params, target, n_steps) do
    # Stack batch
    batch = Nx.stack(batch_states)

    # Run NCA for n_steps
    final_batch = run_nca_steps(batch, params, n_steps)

    # Compute loss
    {loss, grad} = compute_loss_and_grad(final_batch, target, params)

    # Unstack batch
    final_states = Nx.to_list(final_batch)

    loss_value = Nx.to_number(loss)

    {final_states, loss_value, grad}
  end

  defp run_nca_steps(batch, params, n_steps) do
    Enum.reduce(1..n_steps, batch, fn _step, state ->
      # Apply NCA step to each state in batch
      # Note: This is simplified - real impl would vectorize
      state
      |> Nx.to_list()
      |> Enum.map(fn s ->
        {updated, _} = UpdateRule.step(s, params)
        updated
      end)
      |> Nx.stack()
    end)
  end

  defp compute_loss_and_grad(final_batch, target, params) do
    # Extract RGBA channels for loss
    rgba_pred =
      Nx.slice(final_batch, [0, 0, 0, 0], [
        elem(Nx.shape(final_batch), 0),
        elem(Nx.shape(target), 0),
        elem(Nx.shape(target), 1),
        4
      ])

    rgba_target =
      Nx.slice(target, [0, 0, 0], [elem(Nx.shape(target), 0), elem(Nx.shape(target), 1), 4])

    # Broadcast target to batch size
    batch_size = elem(Nx.shape(final_batch), 0)

    target_batch =
      Nx.broadcast(
        rgba_target,
        {batch_size, elem(Nx.shape(target), 0), elem(Nx.shape(target), 1), 4}
      )

    # MSE loss
    diff = Nx.subtract(rgba_pred, target_batch)
    loss = Nx.mean(Nx.pow(diff, 2))

    # Simplified gradient (placeholder - real impl would use Nx.Defn.grad)
    grad = %{
      w1: Nx.broadcast(0.0, Nx.shape(params.w1)),
      b1: Nx.broadcast(0.0, Nx.shape(params.b1)),
      w2: Nx.broadcast(0.0, Nx.shape(params.w2)),
      b2: Nx.broadcast(0.0, Nx.shape(params.b2))
    }

    {loss, grad}
  end

  defp apply_gradients(params, grad, lr) do
    %{
      w1: Nx.subtract(params.w1, Nx.multiply(lr, grad.w1)),
      b1: Nx.subtract(params.b1, Nx.multiply(lr, grad.b1)),
      w2: Nx.subtract(params.w2, Nx.multiply(lr, grad.w2)),
      b2: Nx.subtract(params.b2, Nx.multiply(lr, grad.b2))
    }
  end

  defp compute_per_sample_losses(states, target) do
    rgba_target =
      Nx.slice(target, [0, 0, 0], [elem(Nx.shape(target), 0), elem(Nx.shape(target), 1), 4])

    Enum.map(states, fn state ->
      rgba_pred =
        Nx.slice(state, [0, 0, 0], [elem(Nx.shape(state), 0), elem(Nx.shape(state), 1), 4])

      diff = Nx.subtract(rgba_pred, rgba_target)
      Nx.to_number(Nx.mean(Nx.pow(diff, 2)))
    end)
  end

  defp maybe_damage_states(states, damage_prob) do
    Enum.map(states, fn state ->
      if :rand.uniform() < damage_prob do
        apply_random_damage(state)
      else
        state
      end
    end)
  end

  defp apply_random_damage(state) do
    {h, w, c} = Nx.shape(state)

    # Random rectangular damage (zero out a region)
    damage_size = div(min(h, w), 4)
    dx = :rand.uniform(h - damage_size + 1) - 1
    dy = :rand.uniform(w - damage_size + 1) - 1

    # Create damage mask
    mask = Nx.broadcast(1.0, {h, w, c})
    damage_region = Nx.broadcast(0.0, {damage_size, damage_size, c})
    damage_mask = Nx.put_slice(mask, [dx, dy, 0], damage_region)

    Nx.multiply(state, damage_mask)
  end

  defp write_batch_to_pool(pool_list, indices, batch_values) do
    Enum.zip(indices, batch_values)
    |> Enum.reduce(pool_list, fn {idx, value}, acc ->
      List.replace_at(acc, idx, value)
    end)
  end

  defp inject_seed(states, losses, seed) do
    # Find index of highest loss
    max_loss_idx =
      losses
      |> Enum.with_index()
      |> Enum.max_by(fn {loss, _idx} -> loss end)
      |> elem(1)

    # Replace with seed
    new_states = List.replace_at(states, max_loss_idx, seed)
    # Reset loss
    new_losses = List.replace_at(losses, max_loss_idx, 1.0)

    {new_states, new_losses}
  end

  # ═══════════════════════════════════════════════════════════════
  # TRAINING LOOP
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Run full training loop.

  ## Options

  - `:steps` - Number of training steps (default: 8000)
  - `:batch_size` - Batch size (default: 8)
  - `:learning_rate` - Learning rate (default: 2e-3)
  - `:log_every` - Log interval (default: 100)
  - `:on_step` - Callback `fn pool, step, loss -> :ok end`
  """
  @spec train(t(), keyword()) :: {t(), list(float())}
  def train(pool, opts \\ []) do
    steps = Keyword.get(opts, :steps, 8000)
    log_every = Keyword.get(opts, :log_every, 100)
    on_step = Keyword.get(opts, :on_step, fn _pool, _step, _loss -> :ok end)

    train_opts = Keyword.take(opts, [:batch_size, :learning_rate])

    Logger.info("[SamplePool] Starting training for #{steps} steps")

    {final_pool, losses} =
      Enum.reduce(1..steps, {pool, []}, fn step, {current_pool, loss_history} ->
        {updated_pool, loss} = train_step(current_pool, train_opts)

        if rem(step, log_every) == 0 do
          avg_loss = Enum.sum(updated_pool.losses) / updated_pool.pool_size

          Logger.info(
            "[SamplePool] Step #{step}/#{steps}, batch_loss=#{Float.round(loss, 5)}, avg_pool_loss=#{Float.round(avg_loss, 5)}"
          )
        end

        on_step.(updated_pool, step, loss)

        {updated_pool, [loss | loss_history]}
      end)

    Logger.info("[SamplePool] Training complete")

    {final_pool, Enum.reverse(losses)}
  end

  # ═══════════════════════════════════════════════════════════════
  # INFERENCE
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Grow from seed for specified steps.
  """
  @spec grow(t(), non_neg_integer()) :: Nx.Tensor.t()
  def grow(pool, steps) do
    Enum.reduce(1..steps, pool.seed, fn _step, state ->
      {updated, _} = UpdateRule.step(state, pool.nca_params)
      updated
    end)
  end

  @doc """
  Get best sample from pool (lowest loss).
  """
  @spec best_sample(t()) :: Nx.Tensor.t()
  def best_sample(pool) do
    min_idx =
      pool.losses
      |> Enum.with_index()
      |> Enum.min_by(fn {loss, _idx} -> loss end)
      |> elem(1)

    Enum.at(pool.states, min_idx)
  end

  @doc """
  Get statistics about pool.
  """
  @spec stats(t()) :: map()
  def stats(pool) do
    %{
      pool_size: pool.pool_size,
      min_loss: Enum.min(pool.losses),
      max_loss: Enum.max(pool.losses),
      avg_loss: Enum.sum(pool.losses) / pool.pool_size,
      median_loss: Enum.sort(pool.losses) |> Enum.at(div(pool.pool_size, 2))
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # PERSISTENCE
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Serialize pool to binary.
  """
  @spec serialize(t()) :: binary()
  def serialize(pool) do
    # Only serialize params, not full pool
    :erlang.term_to_binary(%{
      nca_params: serialize_params(pool.nca_params),
      state_shape: pool.state_shape,
      step_range: pool.step_range,
      damage_prob: pool.damage_prob
    })
  end

  defp serialize_params(params) do
    %{
      w1: Nx.to_binary(params.w1),
      b1: Nx.to_binary(params.b1),
      w2: Nx.to_binary(params.w2),
      b2: Nx.to_binary(params.b2),
      w1_shape: Nx.shape(params.w1),
      b1_shape: Nx.shape(params.b1),
      w2_shape: Nx.shape(params.w2),
      b2_shape: Nx.shape(params.b2)
    }
  end

  @doc """
  Deserialize pool from binary.
  """
  @spec deserialize(binary(), Nx.Tensor.t()) :: t()
  def deserialize(binary, target) do
    data = :erlang.binary_to_term(binary)

    # Reconstruct params
    nca_params = %{
      w1: Nx.from_binary(data.nca_params.w1, :f32) |> Nx.reshape(data.nca_params.w1_shape),
      b1: Nx.from_binary(data.nca_params.b1, :f32) |> Nx.reshape(data.nca_params.b1_shape),
      w2: Nx.from_binary(data.nca_params.w2, :f32) |> Nx.reshape(data.nca_params.w2_shape),
      b2: Nx.from_binary(data.nca_params.b2, :f32) |> Nx.reshape(data.nca_params.b2_shape)
    }

    # Create fresh pool with loaded params
    pool = new(target, step_range: data.step_range, damage_prob: data.damage_prob)
    %{pool | nca_params: nca_params}
  end
end
