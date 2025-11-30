defmodule Thunderline.Thundercrown.CurriculumRewards do
  @moduledoc """
  Agent0-style Curriculum Rewards for Self-Evolving PACs.

  Based on: "Agent0: Unleashing Self-Evolving Agents from Zero Data" (arXiv:2511.16043)

  Implements the reward signals used by the Curriculum Agent (ThunderCrown) to
  generate frontier tasks that maximally improve the Executor Agent (Cerebros).

  ## Reward Components

  1. **Uncertainty Reward (R_unc)** - Maximized when executor is ~50% uncertain
     Encourages tasks at the edge of capability (frontier zone).

  2. **Tool Use Reward (R_tool)** - Rewards tasks that require tool integration
     Breaks the capability ceiling by forcing tool learning.

  3. **Repetition Penalty (R_rep)** - Penalizes similar tasks
     Ensures diversity in the curriculum.

  ## Combined Reward

  R_C = α · R_unc + β · R_tool - γ · R_rep

  Default weights: α=1.0, β=0.6, γ=0.3

  ## Reference

  Xia et al., "Agent0: Unleashing Self-Evolving Agents from Zero Data via Tool-Integrated Reasoning", 2025
  """

  require Logger

  @default_alpha 1.0    # Uncertainty weight
  @default_beta 0.6     # Tool use weight
  @default_gamma 0.3    # Repetition penalty weight
  @default_tool_cap 4   # Maximum tool calls to reward
  @frontier_band {0.3, 0.8}  # Capability frontier: 30-80% success rate

  # ═══════════════════════════════════════════════════════════════
  # UNCERTAINTY REWARD
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute uncertainty reward from executor's consistency score.

  The consistency score p̂(x) is computed via majority voting over k samples.
  R_unc is maximized when p̂ ≈ 0.5 (maximum uncertainty).

  Formula: R_unc = 1 - 2|p̂(x) - 0.5|

  ## Arguments

  - `consistency_score` - Fraction of samples that agree (0.0 to 1.0)

  ## Returns

  Uncertainty reward in [0.0, 1.0], maximized at consistency = 0.5
  """
  @spec uncertainty_reward(float()) :: float()
  def uncertainty_reward(consistency_score) when is_float(consistency_score) do
    # Clamp to [0, 1]
    p_hat = max(0.0, min(1.0, consistency_score))
    
    # R_unc = 1 - 2|p̂ - 0.5|
    # Maximum (1.0) when p̂ = 0.5, minimum (0.0) when p̂ = 0 or 1
    1.0 - 2.0 * abs(p_hat - 0.5)
  end

  @doc """
  Compute consistency score from multiple executor responses.

  Uses majority voting: the consistency is the fraction that matches the majority.

  ## Arguments

  - `responses` - List of executor responses (any comparable terms)

  ## Returns

  Consistency score in [0.0, 1.0]
  """
  @spec compute_consistency([term()]) :: float()
  def compute_consistency([]), do: 0.0
  def compute_consistency([_single]), do: 1.0
  
  def compute_consistency(responses) when is_list(responses) do
    total = length(responses)
    
    # Count occurrences of each response
    counts = Enum.frequencies(responses)
    
    # Find majority count
    max_count = counts |> Map.values() |> Enum.max()
    
    # Consistency = majority_count / total
    max_count / total
  end

  # ═══════════════════════════════════════════════════════════════
  # TOOL USE REWARD
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute tool use reward from number of tool calls.

  Rewards tasks that require tool integration, capped at a maximum.

  Formula: R_tool = γ · min(N_tool, C) / C

  ## Arguments

  - `tool_calls` - Number of tool invocations
  - `opts` - Options:
    - `:gamma` - Scaling factor (default: 0.6)
    - `:cap` - Maximum tool calls to reward (default: 4)

  ## Returns

  Tool use reward in [0.0, gamma]
  """
  @spec tool_use_reward(non_neg_integer(), keyword()) :: float()
  def tool_use_reward(tool_calls, opts \\ []) when is_integer(tool_calls) do
    gamma = Keyword.get(opts, :gamma, @default_beta)
    cap = Keyword.get(opts, :cap, @default_tool_cap)
    
    # R_tool = γ · min(N_tool, C) / C
    gamma * min(tool_calls, cap) / cap
  end

  @doc """
  Check if a task is in the capability frontier band.

  Tasks in the frontier (default 30-80% success rate) are most valuable
  for learning - not too easy, not too hard.

  ## Arguments

  - `success_rate` - Executor's success rate on similar tasks
  - `opts` - Options:
    - `:low` - Lower bound (default: 0.3)
    - `:high` - Upper bound (default: 0.8)

  ## Returns

  `true` if task is in frontier band
  """
  @spec in_frontier_band?(float(), keyword()) :: boolean()
  def in_frontier_band?(success_rate, opts \\ []) do
    {default_low, default_high} = @frontier_band
    low = Keyword.get(opts, :low, default_low)
    high = Keyword.get(opts, :high, default_high)
    
    success_rate >= low and success_rate <= high
  end

  # ═══════════════════════════════════════════════════════════════
  # REPETITION PENALTY
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute repetition penalty based on task similarity.

  Uses cosine similarity between task embeddings to penalize similar tasks.

  ## Arguments

  - `task_embedding` - Vector representation of current task
  - `history_embeddings` - List of recent task embeddings
  - `opts` - Options:
    - `:threshold` - Similarity threshold for penalty (default: 0.8)
    - `:decay` - Decay factor for older tasks (default: 0.9)

  ## Returns

  Repetition penalty in [0.0, 1.0]
  """
  @spec repetition_penalty(list(float()), list(list(float())), keyword()) :: float()
  def repetition_penalty(task_embedding, history_embeddings, opts \\ [])
  
  def repetition_penalty(_task, [], _opts), do: 0.0
  
  def repetition_penalty(task_embedding, history_embeddings, opts) do
    threshold = Keyword.get(opts, :threshold, 0.8)
    decay = Keyword.get(opts, :decay, 0.9)
    
    # Compute decayed similarity scores
    penalties =
      history_embeddings
      |> Enum.with_index()
      |> Enum.map(fn {hist_emb, idx} ->
        sim = cosine_similarity(task_embedding, hist_emb)
        decay_factor = :math.pow(decay, idx)
        
        # Apply penalty if similarity exceeds threshold
        if sim > threshold do
          (sim - threshold) / (1.0 - threshold) * decay_factor
        else
          0.0
        end
      end)
    
    # Sum penalties (capped at 1.0)
    min(1.0, Enum.sum(penalties))
  end

  defp cosine_similarity(a, b) when length(a) == length(b) do
    dot = Enum.zip(a, b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
    norm_a = :math.sqrt(Enum.map(a, &(&1 * &1)) |> Enum.sum())
    norm_b = :math.sqrt(Enum.map(b, &(&1 * &1)) |> Enum.sum())
    
    if norm_a * norm_b > 0.0 do
      dot / (norm_a * norm_b)
    else
      0.0
    end
  end

  defp cosine_similarity(_a, _b), do: 0.0

  # ═══════════════════════════════════════════════════════════════
  # COMBINED CURRICULUM REWARD
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute combined curriculum reward for task generation.

  R_C = α · R_unc + β · R_tool - γ · R_rep

  ## Arguments

  - `metrics` - Map containing:
    - `:consistency_score` - Executor consistency (0-1)
    - `:tool_calls` - Number of tool invocations
    - `:task_embedding` - Task vector (optional)
    - `:history_embeddings` - Recent task vectors (optional)

  - `opts` - Options:
    - `:alpha` - Uncertainty weight (default: 1.0)
    - `:beta` - Tool use weight (default: 0.6)
    - `:gamma` - Repetition penalty weight (default: 0.3)

  ## Returns

  Combined reward value
  """
  @spec curriculum_reward(map(), keyword()) :: float()
  def curriculum_reward(metrics, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, @default_alpha)
    beta = Keyword.get(opts, :beta, @default_beta)
    gamma = Keyword.get(opts, :gamma, @default_gamma)
    
    # Compute components
    r_unc = uncertainty_reward(Map.get(metrics, :consistency_score, 0.5))
    r_tool = tool_use_reward(Map.get(metrics, :tool_calls, 0))
    
    r_rep = 
      case {Map.get(metrics, :task_embedding), Map.get(metrics, :history_embeddings)} do
        {task_emb, hist_embs} when is_list(task_emb) and is_list(hist_embs) ->
          repetition_penalty(task_emb, hist_embs)
        _ ->
          0.0
      end
    
    # Combined reward
    reward = alpha * r_unc + beta * r_tool - gamma * r_rep
    
    Logger.debug("[CurriculumRewards] R_unc=#{Float.round(r_unc, 3)}, R_tool=#{Float.round(r_tool, 3)}, R_rep=#{Float.round(r_rep, 3)} => R_C=#{Float.round(reward, 3)}")
    
    reward
  end

  # ═══════════════════════════════════════════════════════════════
  # ADPO (Ambiguity-Dynamic Policy Optimization) HELPERS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute ambiguity-scaled advantage for ADPO.

  Scale the advantage by consistency score to down-weight unreliable labels.

  Formula: Ã = Â · s(p̂), where s is an increasing function of p̂
  """
  @spec ambiguity_scaled_advantage(float(), float()) :: float()
  def ambiguity_scaled_advantage(raw_advantage, consistency_score) do
    # Scale factor: s(p̂) = p̂ (simple linear scaling)
    # Higher consistency = more reliable label = higher weight
    scale = max(0.0, min(1.0, consistency_score))
    raw_advantage * scale
  end

  @doc """
  Compute dynamic trust region upper bound for ADPO.

  For high-ambiguity tasks (low p̂), relax the clipping constraint to allow
  larger gradient steps for exploration.

  Formula: ε_high(x) = ε_base + (1 - p̂) · ε_bonus
  """
  @spec dynamic_clip_bound(float(), keyword()) :: float()
  def dynamic_clip_bound(consistency_score, opts \\ []) do
    eps_base = Keyword.get(opts, :eps_base, 0.2)
    eps_bonus = Keyword.get(opts, :eps_bonus, 0.3)
    
    # Higher bonus for lower consistency (more ambiguous)
    eps_base + (1.0 - consistency_score) * eps_bonus
  end

  # ═══════════════════════════════════════════════════════════════
  # TASK FILTERING
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Filter tasks to keep only those in the capability frontier.

  Tasks with consistency in [0.3, 0.8] are most valuable for learning.
  """
  @spec filter_frontier_tasks(list({term(), float()}), keyword()) :: list({term(), float()})
  def filter_frontier_tasks(tasks_with_consistency, opts \\ []) do
    {low, high} = Keyword.get(opts, :band, @frontier_band)
    
    Enum.filter(tasks_with_consistency, fn {_task, consistency} ->
      consistency >= low and consistency <= high
    end)
  end

  @doc """
  Rank tasks by curriculum reward.

  Returns tasks sorted by descending reward value.
  """
  @spec rank_tasks(list({term(), map()}), keyword()) :: list({term(), float()})
  def rank_tasks(tasks_with_metrics, opts \\ []) do
    tasks_with_metrics
    |> Enum.map(fn {task, metrics} ->
      reward = curriculum_reward(metrics, opts)
      {task, reward}
    end)
    |> Enum.sort_by(fn {_task, reward} -> reward end, :desc)
  end
end
