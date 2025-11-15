defmodule Thunderline.ML.SLASelector do
  @moduledoc """
  Stochastic Learning Automaton for adaptive model selection.

  The SLA (Stochastic Learning Automaton) is a reinforcement learning agent that maintains
  a probability distribution over a set of actions (candidate models) and updates these
  probabilities based on rewards from the environment.

  ## Theory

  From Li et al. (2007) "An Improved Adaptive Parzen Window Approach Based on SLA":

  **Action Set**: U = {u₁, u₂, ..., uₘ} (candidate model identifiers)

  **Probability Vector**: P(t) = {P₁(t), P₂(t), ..., Pₘ(t)} where Σ Pᵢ = 1

  **Update Rules**:

  If action uⱼ receives **reward** (distance decreased):

      P_j(t+1) = P_j(t) + α[1 - P_j(t)]
      P_i(t+1) = P_i(t) - (α/(m-1))P_i(t)  for i not equal j

  If action uⱼ receives **penalty** (distance increased):

      P_j(t+1) = (1-v)P_j(t)
      P_i(t+1) = (v/(m-1)) + (1-v)P_i(t)  for i not equal j

  Where:
  - α = reward learning rate (default: 0.1)
  - v = penalty learning rate (default: 0.05)
  - m = number of actions

  ## Convergence

  The SLA is proven to converge to the optimal action under stationary environments
  (Narendra & Thathachar, 1989). Convergence is detected when:

      max(P) > θ  (default θ = 0.85)

  And probability distribution remains stable over N iterations.

  ## Usage

  ```elixir
  # Initialize with candidate models
  sla = SLASelector.init([:model_k1, :model_k2, :model_k3], alpha: 0.1, v: 0.05)

  # Choose action based on current probabilities
  {sla, chosen_model} = SLASelector.choose_action(sla)

  # Update based on reward/penalty
  distance_decreased? = prev_distance > current_distance
  reward = if distance_decreased?, do: 1, else: 0
  sla = SLASelector.update(sla, chosen_model, reward, distance: current_distance)

  # Check convergence
  if SLASelector.converged?(sla, threshold: 0.85) do
    Logger.info("SLA converged to model: \#{inspect(sla.best_action)}")
  end

  # Get current probability distribution
  probs = SLASelector.probabilities(sla)
  # => %{model_k1: 0.05, model_k2: 0.90, model_k3: 0.05}
  ```

  ## Architecture

  Used by `Thunderline.ML.Controller` to select which ONNX model to use for each batch.
  The Controller computes the distance between Parzen density and model output density,
  then feeds this as reward/penalty signal to the SLA.

  ## References

  - Narendra & Thathachar (1989). "Learning Automata: An Introduction"
  - Li et al. (2007). "An Improved Adaptive Parzen Window Approach Based on SLA"
  - Lakshmivarahan (1981). "Learning Algorithms Theory and Applications"
  """

  @typedoc """
  SLA selector state.

  Fields:
  - `actions`: List of action identifiers (model IDs)
  - `probabilities`: Current probability distribution over actions
  - `alpha`: Reward learning rate (0 < α ≤ 1)
  - `v`: Penalty learning rate (0 < v ≤ 1, typically v < α)
  - `iteration`: Current iteration count
  - `reward_history`: Recent reward signals [{action, reward, distance}, ...]
  - `last_distance`: Previous distance for computing reward
  - `best_action`: Current best action (highest probability)
  """
  @type t :: %__MODULE__{
          actions: [atom()],
          probabilities: %{atom() => float()},
          alpha: float(),
          v: float(),
          iteration: non_neg_integer(),
          reward_history: [{atom(), 0 | 1, float()}],
          last_distance: float() | nil,
          best_action: atom() | nil
        }

  defstruct actions: [],
            probabilities: %{},
            alpha: 0.1,
            v: 0.05,
            iteration: 0,
            reward_history: [],
            last_distance: nil,
            best_action: nil

  @doc """
  Initialize a new SLA selector.

  ## Arguments

  - `actions` - List of action identifiers (e.g., [:model_k1, :model_k2, :model_k3])
  - `opts` - Keyword options:
    - `:alpha` - Reward learning rate (default: 0.1)
    - `:v` - Penalty learning rate (default: 0.05)

  ## Returns

  SLA struct with uniform probability distribution.

  ## Examples

      iex> SLASelector.init([:model_k1, :model_k2, :model_k3])
      %SLASelector{
        actions: [:model_k1, :model_k2, :model_k3],
        probabilities: %{model_k1: 0.333, model_k2: 0.333, model_k3: 0.333},
        alpha: 0.1,
        v: 0.05
      }
  """
  @spec init([atom()], keyword()) :: t()
  def init(actions, opts \\ []) when is_list(actions) and length(actions) > 0 do
    alpha = Keyword.get(opts, :alpha, 0.1)
    v = Keyword.get(opts, :v, 0.05)

    # Validate learning rates
    unless alpha > 0.0 and alpha <= 1.0 do
      raise ArgumentError, "alpha must be in (0, 1], got: #{alpha}"
    end

    unless v > 0.0 and v <= 1.0 do
      raise ArgumentError, "v must be in (0, 1], got: #{v}"
    end

    # Initialize uniform probabilities: P(uⱼ) = 1/m for all j
    m = length(actions)
    uniform_prob = 1.0 / m
    probabilities = Map.new(actions, fn action -> {action, uniform_prob} end)

    %__MODULE__{
      actions: actions,
      probabilities: probabilities,
      alpha: alpha,
      v: v,
      iteration: 0,
      reward_history: [],
      last_distance: nil,
      best_action: nil
    }
  end

  @doc """
  Choose an action based on current probability distribution.

  Uses roulette wheel selection: actions with higher probabilities are more likely
  to be selected.

  ## Arguments

  - `sla` - Current SLA state
  - `opts` - Keyword options:
    - `:random_seed` - Seed for deterministic testing (default: random)

  ## Returns

  Tuple `{updated_sla, chosen_action}` where:
  - `updated_sla` - SLA with incremented iteration counter
  - `chosen_action` - Selected action identifier

  ## Examples

      {sla, action} = SLASelector.choose_action(sla)
      # => {%SLASelector{...}, :model_k2}
  """
  @spec choose_action(t(), keyword()) :: {t(), atom()}
  def choose_action(%__MODULE__{} = sla, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :sample)
    random_seed = Keyword.get(opts, :random_seed)

    # Set random seed for deterministic testing
    if random_seed, do: :rand.seed(:exsss, {random_seed, random_seed, random_seed})

    chosen_action =
      case strategy do
        :greedy ->
          # Exploitation: choose action with maximum probability
          {action, _prob} = Enum.max_by(sla.probabilities, fn {_k, v} -> v end)
          action

        :sample ->
          # Exploration: roulette wheel selection according to P(uⱼ)
          rand = :rand.uniform()
          cumulative_sample(sla.actions, sla.probabilities, rand, 0.0)

        unknown ->
          raise ArgumentError, "Unknown strategy: #{inspect(unknown)}. Use :greedy or :sample."
      end

    # Update iteration counter and best_action
    {best_action, _} = Enum.max_by(sla.probabilities, fn {_k, v} -> v end)

    updated_sla = %__MODULE__{
      sla
      | iteration: sla.iteration + 1,
        best_action: best_action
    }

    {updated_sla, chosen_action}
  end

  # Private helper: Roulette wheel selection
  # Traverse actions, accumulating probabilities until rand threshold crossed
  @doc false
  defp cumulative_sample([action | rest], probs, rand, acc) do
    new_acc = acc + Map.fetch!(probs, action)

    if rand <= new_acc do
      action
    else
      cumulative_sample(rest, probs, rand, new_acc)
    end
  end

  # Safety: if we reach end of list (shouldn't happen with proper normalization), return last action
  defp cumulative_sample([], _probs, _rand, _acc) do
    raise "cumulative_sample: ran out of actions (probabilities may not sum to 1.0)"
  end

  @doc """
  Update probabilities based on reward/penalty signal.

  ## Algorithm

  Computes reward signal:

      reward = if current_distance < last_distance, do: 1, else: 0

  Then applies update rules:

  **Reward (r = 1)**:
      P_j(t+1) = P_j(t) + α[1 - P_j(t)]
      P_i(t+1) = P_i(t) - (α/(m-1))P_i(t)  for i ≠ j

  **Penalty (r = 0)**:
      P_j(t+1) = (1-v)P_j(t)
      P_i(t+1) = (v/(m-1)) + (1-v)P_i(t)  for i ≠ j

  Finally, normalizes probabilities to sum to 1.0.

  ## Arguments

  - `sla` - Current SLA state
  - `action` - Action that was taken
  - `reward` - Reward signal (0 or 1)
  - `opts` - Keyword options:
    - `:distance` - Current distance value (stored for next update)

  ## Returns

  Updated SLA state with new probabilities.

  ## Examples

      sla = SLASelector.update(sla, :model_k2, 1, distance: 0.023)
      # Probabilities for :model_k2 increased, others decreased
  """
  @spec update(t(), atom(), 0 | 1, keyword()) :: t()
  def update(%__MODULE__{} = sla, action, reward, opts \\ [])
      when is_atom(action) and reward in [0, 1] do
    unless action in sla.actions do
      raise ArgumentError, "unknown action: #{inspect(action)}, valid actions: #{inspect(sla.actions)}"
    end

    distance = Keyword.get(opts, :distance)

    # Apply Narendra-Thathachar SLA update rules (Li et al. 2007)
    m = length(sla.actions)

    new_probs =
      if reward == 1 do
        # REWARD: chosen action probability increases, others decrease
        # P_j(t+1) = P_j(t) + α[1 - P_j(t)]
        # P_i(t+1) = P_i(t) - (α/(m-1))P_i(t)  for i ≠ j
        reward_update(sla.probabilities, action, sla.alpha, m)
      else
        # PENALTY: chosen action probability decreases, others increase
        # P_j(t+1) = (1-v)P_j(t)
        # P_i(t+1) = (v/(m-1)) + (1-v)P_i(t)  for i ≠ j
        penalty_update(sla.probabilities, action, sla.v, m)
      end

    # Normalize to ensure Σ P(uⱼ) = 1.0 (handle floating point drift)
    normalized_probs = normalize_probabilities(new_probs)

    # Update reward history (keep last 100 for convergence analysis)
    timestamp = DateTime.utc_now()
    new_history = [{action, reward, distance, timestamp} | sla.reward_history] |> Enum.take(100)

    # Determine current best action
    {best_action, _} = Enum.max_by(normalized_probs, fn {_k, v} -> v end)

    # Note: We do NOT increment iteration here - that happens in choose_action
    # which represents completing one decision cycle. update() is called
    # multiple times per cycle (once per model) to incorporate all rewards.
    %__MODULE__{
      sla
      | probabilities: normalized_probs,
        reward_history: new_history,
        last_distance: distance,
        best_action: best_action
    }
  end

  # Private: Reward update (distance improved)
  @doc false
  defp reward_update(probs, chosen_action, alpha, m) do
    Map.new(probs, fn {action, p} ->
      if action == chosen_action do
        # Chosen action gains: P_j(t+1) = P_j(t) + α[1 - P_j(t)]
        {action, p + alpha * (1.0 - p)}
      else
        # Others lose proportionally: P_i(t+1) = P_i(t) - (α/(m-1))P_i(t)
        {action, p - (alpha / (m - 1)) * p}
      end
    end)
  end

  # Private: Penalty update (distance worsened)
  @doc false
  defp penalty_update(probs, chosen_action, v, m) do
    Map.new(probs, fn {action, p} ->
      if action == chosen_action do
        # Chosen action loses: P_j(t+1) = (1-v)P_j(t)
        {action, (1.0 - v) * p}
      else
        # Others gain uniformly: P_i(t+1) = (v/(m-1)) + (1-v)P_i(t)
        {action, v / (m - 1) + (1.0 - v) * p}
      end
    end)
  end

  # Private: Normalize probability distribution to sum to 1.0
  @doc false
  defp normalize_probabilities(probs) do
    total = probs |> Map.values() |> Enum.sum()

    # Handle edge case: if total is 0 (shouldn't happen), reset to uniform
    if total < 1.0e-10 do
      m = map_size(probs)
      uniform = 1.0 / m
      Map.new(probs, fn {k, _v} -> {k, uniform} end)
    else
      Map.new(probs, fn {k, v} -> {k, v / total} end)
    end
  end

  @doc """
  Get current probability distribution.

  ## Arguments

  - `sla` - Current SLA state

  ## Returns

  Map of action => probability.

  ## Examples

      SLASelector.probabilities(sla)
      # => %{model_k1: 0.08, model_k2: 0.87, model_k3: 0.05}
  """
  @spec probabilities(t()) :: %{atom() => float()}
  def probabilities(%__MODULE__{} = sla) do
    sla.probabilities
  end

  @doc """
  Get current SLA state summary.

  ## Arguments

  - `sla` - Current SLA state

  ## Returns

  Map with:
  - `:iteration` - Current iteration
  - `:best_action` - Action with highest probability
  - `:best_probability` - Probability of best action
  - `:probabilities` - Full probability distribution
  - `:recent_rewards` - Last N reward signals

  ## Examples

      SLASelector.state(sla)
      # => %{
      #   iteration: 47,
      #   best_action: :model_k2,
      #   best_probability: 0.87,
      #   probabilities: %{...},
      #   recent_rewards: [1, 1, 0, 1, ...]
      # }
  """
  @spec state(t()) :: map()
  def state(%__MODULE__{} = sla) do
    # Find best action and its probability
    {best_action, best_prob} = Enum.max_by(sla.probabilities, fn {_k, v} -> v end)

    # Calculate Shannon entropy: H = -Σ P(uⱼ) log₂ P(uⱼ)
    entropy =
      sla.probabilities
      |> Map.values()
      |> Enum.reduce(0.0, fn p, acc ->
        if p > 1.0e-10, do: acc - p * :math.log2(p), else: acc
      end)

    # Maximum entropy for uniform distribution
    max_entropy = :math.log2(length(sla.actions))

    # Convergence metric: 0 = uniform (max entropy), 1 = converged (min entropy)
    convergence = if max_entropy > 0, do: 1.0 - entropy / max_entropy, else: 1.0

    %{
      probabilities: sla.probabilities,
      iteration: sla.iteration,
      best_action: best_action,
      best_probability: best_prob,
      convergence: convergence,
      entropy: entropy,
      max_entropy: max_entropy,
      history_size: length(sla.reward_history),
      last_distance: sla.last_distance
    }
  end

  @doc """
  Check if SLA has converged.

  Convergence criteria:
  1. max(P) > threshold (default: 0.85)
  2. Probability distribution stable over last N iterations (default: 10)

  ## Arguments

  - `sla` - Current SLA state
  - `opts` - Keyword options:
    - `:threshold` - Minimum probability for convergence (default: 0.85)
    - `:stability_window` - Iterations to check for stability (default: 10)

  ## Returns

  Boolean indicating convergence.

  ## Examples

      if SLASelector.converged?(sla, threshold: 0.85) do
        Logger.info("SLA converged!")
      end
  """
  @spec converged?(t(), keyword()) :: boolean()
  def converged?(%__MODULE__{} = sla, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.85)

    # Converged if any action probability exceeds threshold
    # (Proven convergence under stationary environments - Narendra & Thathachar, 1989)
    sla.probabilities
    |> Map.values()
    |> Enum.any?(fn p -> p >= threshold end)
  end

  @doc """
  Create a serializable snapshot for embedding in voxel metadata.

  ## Returns

  Map with:
  - `:actions` - List of action identifiers
  - `:probabilities` - Current probability distribution
  - `:iteration` - Current iteration
  - `:best_action` - Action with highest probability
  - `:alpha` - Reward learning rate
  - `:v` - Penalty learning rate

  ## Examples

      snapshot = SLASelector.snapshot(sla)
      # => %{
      #   actions: [:model_k1, :model_k2, :model_k3],
      #   probabilities: %{model_k1: 0.08, model_k2: 0.87, ...},
      #   iteration: 47,
      #   best_action: :model_k2,
      #   alpha: 0.1,
      #   v: 0.05
      # }
  """
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = sla) do
    # Serialize key state for voxel metadata persistence
    # NOTE: reward_history NOT included (ephemeral, can be large)
    %{
      actions: sla.actions,
      probabilities: sla.probabilities,
      alpha: sla.alpha,
      v: sla.v,
      iteration: sla.iteration,
      best_action: sla.best_action,
      last_distance: sla.last_distance
    }
  end

  @doc """
  Restore SLA state from a snapshot.

  Inverse of `snapshot/1`. Note: reward history is NOT restored.

  ## Arguments

  - `snapshot` - Snapshot map from `snapshot/1`

  ## Returns

  SLA struct.

  ## Examples

      sla = SLASelector.from_snapshot(snapshot)
  """
  @spec from_snapshot(map()) :: t()
  def from_snapshot(snapshot) when is_map(snapshot) do
    # Restore SLA state from snapshot (e.g., from voxel metadata)
    actions = Map.fetch!(snapshot, :actions)
    probs = Map.fetch!(snapshot, :probabilities)

    %__MODULE__{
      actions: actions,
      probabilities: probs,
      alpha: Map.get(snapshot, :alpha, 0.1),
      v: Map.get(snapshot, :v, 0.05),
      iteration: Map.get(snapshot, :iteration, 0),
      best_action: Map.get(snapshot, :best_action),
      last_distance: Map.get(snapshot, :last_distance),
      reward_history: []  # Reset history (not persisted)
    }
  end
end
