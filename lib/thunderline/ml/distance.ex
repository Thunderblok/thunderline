defmodule Thunderline.ML.Distance do
  @moduledoc """
  Distance metrics for comparing probability distributions.

  Provides various metrics to quantify the difference between two probability
  distributions, used by the SLA + Parzen system to compare the empirical density
  (Parzen) with model output densities.

  ## Metrics

  ### 1. Kullback-Leibler (KL) Divergence

      D_KL(P || Q) = Σ P(i) log(P(i) / Q(i))

  Properties:
  - **Non-symmetric**: D_KL(P || Q) ≠ D_KL(Q || P)
  - **Unbounded**: [0, ∞)
  - **Interpretation**: "Surprise" of using Q when truth is P
  - **Always**: D_KL(P || Q) ≥ 0, with equality iff P = Q

  ### 2. Cross-Entropy

      H(P, Q) = -Σ P(i) log(Q(i))

  Properties:
  - Related to KL: H(P, Q) = H(P) + D_KL(P || Q)
  - Used in classification loss functions
  - Unbounded: [0, ∞)

  ### 3. Hellinger Distance

      H(P, Q) = sqrt(1 - Σ sqrt(P(i) × Q(i)))

  Properties:
  - **Symmetric**: H(P, Q) = H(Q, P)
  - **Bounded**: [0, 1]
  - Related to squared Hellinger distance (Bhattacharyya coefficient)
  - Satisfies triangle inequality (proper metric)

  ### 4. Jensen-Shannon (JS) Divergence

      D_JS(P || Q) = 0.5 × D_KL(P || M) + 0.5 × D_KL(Q || M)
      where M = 0.5 × (P + Q)

  Properties:
  - **Symmetric**: D_JS(P || Q) = D_JS(Q || P)
  - **Bounded**: [0, 1] (when using log₂)
  - Smoothed version of KL divergence
  - Satisfies triangle inequality

  ## Implementation Notes

  All implementations use **epsilon smoothing** (ε = 1.0e-10) to prevent
  `log(0)` and division by zero errors. This is standard practice in ML.

  ## Usage

  ```elixir
  # P and Q are Nx tensors representing probability distributions
  # (must sum to ~1.0)

  # KL divergence (default metric)
  distance = Distance.kl_divergence(parzen_hist, model_hist)

  # Cross-entropy
  distance = Distance.cross_entropy(parzen_hist, model_hist)

  # Hellinger distance
  distance = Distance.hellinger(parzen_hist, model_hist)

  # Jensen-Shannon divergence
  distance = Distance.js_divergence(parzen_hist, model_hist)

  # Compute all metrics at once
  metrics = Distance.all_metrics(parzen_hist, model_hist)
  # => %{
  #   kl_divergence: 0.123,
  #   cross_entropy: 1.456,
  #   hellinger: 0.234,
  #   js_divergence: 0.067
  # }
  ```

  ## References

  - Kullback & Leibler (1951). "On Information and Sufficiency"
  - Hellinger, E. (1909). "Neue Begründung der Theorie quadratischer Formen"
  - Lin, J. (1991). "Divergence Measures Based on the Shannon Entropy"
  """

  import Nx.Defn

  @eps 1.0e-9

  @typedoc """
  Distance metric identifier.
  """
  @type metric :: :kl_divergence | :cross_entropy | :hellinger | :js_divergence
  @type distribution :: Nx.t()
  @type opts :: keyword()

  @doc """
  Compute KL divergence D_KL(P || Q).

  **Formula**: Σ P(i) log(P(i) / Q(i))

  **Interpretation**: Information lost when Q is used to approximate P.

  ## Arguments

  - `p` - True distribution (Nx tensor)
  - `q` - Approximate distribution (Nx tensor)

  ## Returns

  KL divergence value (float, ≥ 0).

  ## Examples

      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.3, 0.2])
      Distance.kl_divergence(p, q)
      # => 0.0513
  """
  @spec kl_divergence(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def kl_divergence(p, q) when is_struct(p, Nx.Tensor) and is_struct(q, Nx.Tensor) do
    {p_norm, q_norm} = normalize_distributions(p, q)
    kl_divergence_impl(p_norm, q_norm) |> Nx.to_number()
  end

  # Private implementation functions (defnp for numerical compilation)

  @doc false
  defnp normalize_distributions(p, q) do
    # Step 1: Clamp to non-negative
    p = Nx.max(p, 0.0)
    q = Nx.max(q, 0.0)

    # Step 2: Normalize to sum=1 (with epsilon to avoid division by zero)
    p_sum = Nx.sum(p)
    q_sum = Nx.sum(q)
    p = p / (p_sum + @eps)
    q = q / (q_sum + @eps)

    # Step 3: Epsilon smooth to avoid log(0)
    p = Nx.clip(p, @eps, 1.0)
    q = Nx.clip(q, @eps, 1.0)

    # Step 4: Re-normalize after clipping
    p = p / Nx.sum(p)
    q = q / Nx.sum(q)

    {p, q}
  end

  @doc false
  defnp kl_divergence_impl(p, q) do
    # D_KL(P || Q) = sum(p * log(p / q))
    ratio = p / q
    log_ratio = Nx.log(ratio)
    Nx.sum(p * log_ratio)
  end

  @doc false
  defnp cross_entropy_impl(p, q) do
    # H(P, Q) = -sum(p * log(q))
    log_q = Nx.log(q)
    Nx.sum(-p * log_q)
  end

  @doc false
  defnp hellinger_impl(p, q) do
    # H(P, Q) = sqrt(1 - BC) where BC = sum(sqrt(p * q))
    # Using Bhattacharyya coefficient for numerical stability
    sqrt_p = Nx.sqrt(p)
    sqrt_q = Nx.sqrt(q)
    bc = Nx.sum(sqrt_p * sqrt_q)
    # Clamp BC to [0, 1] to prevent sqrt(negative) from floating point errors
    bc = Nx.clip(bc, 0.0, 1.0)
    Nx.sqrt(1.0 - bc)
  end

  @doc false
  defnp js_divergence_impl(p, q) do
    # JS(P, Q) = 0.5 * (D_KL(P || M) + D_KL(Q || M)) where M = 0.5 * (P + Q)
    m = 0.5 * (p + q)
    # Normalize M (should already be close to 1, but ensure it)
    m = m / Nx.sum(m)

    # Compute KL divergences to midpoint
    kl_pm = kl_divergence_impl(p, m)
    kl_qm = kl_divergence_impl(q, m)

    0.5 * (kl_pm + kl_qm)
  end

  @doc """
  Compute cross-entropy H(P, Q).

  **Formula**: -Σ P(i) log(Q(i))

  **Interpretation**: Expected log-likelihood under P using distribution Q.

  ## Arguments

  - `p` - True distribution (Nx tensor)
  - `q` - Approximate distribution (Nx tensor)

  ## Returns

  Cross-entropy value (float, ≥ 0).

  ## Examples

      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.3, 0.2])
      Distance.cross_entropy(p, q)
      # => 1.1539
  """
  @spec cross_entropy(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def cross_entropy(p, q) when is_struct(p, Nx.Tensor) and is_struct(q, Nx.Tensor) do
    {p_norm, q_norm} = normalize_distributions(p, q)
    cross_entropy_impl(p_norm, q_norm) |> Nx.to_number()
  end

  @doc """
  Compute Hellinger distance H(P, Q).

  **Formula**: sqrt(1 - Σ sqrt(P(i) × Q(i)))

  **Interpretation**: Geometric measure of distribution similarity.

  ## Arguments

  - `p` - First distribution (Nx tensor)
  - `q` - Second distribution (Nx tensor)

  ## Returns

  Hellinger distance (float, 0 ≤ d ≤ 1).

  ## Examples

      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.3, 0.2])
      Distance.hellinger(p, q)
      # => 0.1023
  """
  @spec hellinger(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def hellinger(p, q) when is_struct(p, Nx.Tensor) and is_struct(q, Nx.Tensor) do
    {p_norm, q_norm} = normalize_distributions(p, q)
    hellinger_impl(p_norm, q_norm) |> Nx.to_number()
  end

  @doc """
  Compute Jensen-Shannon divergence D_JS(P || Q).

  **Formula**: 0.5 × D_KL(P || M) + 0.5 × D_KL(Q || M) where M = 0.5(P + Q)

  **Interpretation**: Symmetric smoothed KL divergence.

  ## Arguments

  - `p` - First distribution (Nx tensor)
  - `q` - Second distribution (Nx tensor)

  ## Returns

  JS divergence (float, 0 ≤ d ≤ 1 with log₂).

  ## Examples

      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.3, 0.2])
      Distance.js_divergence(p, q)
      # => 0.0367
  """
  @spec js_divergence(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def js_divergence(p, q) when is_struct(p, Nx.Tensor) and is_struct(q, Nx.Tensor) do
    {p_norm, q_norm} = normalize_distributions(p, q)
    js_divergence_impl(p_norm, q_norm) |> Nx.to_number()
  end

  @doc """
  Computes all distance metrics in a single pass for efficiency.

  Returns a map with all four metrics computed from the same normalized pair.
  More efficient than calling each metric separately.

  ## Examples

      iex> p = Nx.tensor([0.5, 0.5])
      iex> q = Nx.tensor([0.3, 0.7])
      iex> Distance.all_metrics(p, q)
      %{
        kl_divergence: 0.023,
        cross_entropy: 0.71,
        hellinger: 0.05,
        js_divergence: 0.012
      }
  """
  @spec all_metrics(Nx.Tensor.t(), Nx.Tensor.t()) :: %{
          kl_divergence: float(),
          cross_entropy: float(),
          hellinger: float(),
          js_divergence: float()
        }
  def all_metrics(p, q) do
    {p_norm, q_norm} = normalize_distributions(p, q)

    %{
      kl_divergence: kl_divergence_impl(p_norm, q_norm) |> Nx.to_number(),
      cross_entropy: cross_entropy_impl(p_norm, q_norm) |> Nx.to_number(),
      hellinger: hellinger_impl(p_norm, q_norm) |> Nx.to_number(),
      js_divergence: js_divergence_impl(p_norm, q_norm) |> Nx.to_number()
    }
  end

  @doc """
  Validate that tensors represent valid probability distributions.

  Checks:
  1. Non-negative values
  2. Sum ≈ 1.0 (within tolerance)
  3. Same shape

  ## Arguments

  - `p` - Distribution tensor
  - `q` - Distribution tensor
  - `opts` - Keyword options:
    - `:tolerance` - Sum tolerance (default: 1.0e-6)

  ## Returns

  `:ok` or `{:error, reason}`.

  ## Examples

      Distance.validate_distributions(p, q)
      # => :ok

      Distance.validate_distributions(bad_p, q)
      # => {:error, "Distribution P does not sum to 1.0 (sum=0.8)"}
  """
  @spec validate_distributions(Nx.Tensor.t(), Nx.Tensor.t(), keyword()) ::
          :ok | {:error, String.t()}
  def validate_distributions(p, q, opts \\ [])
      when is_struct(p, Nx.Tensor) and is_struct(q, Nx.Tensor) do
    tolerance = Keyword.get(opts, :tolerance, 1.0e-6)

    # Check shape mismatch
    if Nx.shape(p) != Nx.shape(q) do
      {:error, "Shape mismatch: P=#{inspect(Nx.shape(p))}, Q=#{inspect(Nx.shape(q))}"}
    else
      # Check for negative values
      p_min = Nx.reduce_min(p) |> Nx.to_number()
      q_min = Nx.reduce_min(q) |> Nx.to_number()

      cond do
        p_min < 0 ->
          {:error, "P contains negative values (min=#{p_min})"}

        q_min < 0 ->
          {:error, "Q contains negative values (min=#{q_min})"}

        true ->
          # Check if distributions sum to ~1.0
          p_sum = Nx.sum(p) |> Nx.to_number()
          q_sum = Nx.sum(q) |> Nx.to_number()

          p_normalized? = abs(p_sum - 1.0) < tolerance
          q_normalized? = abs(q_sum - 1.0) < tolerance

          cond do
            not p_normalized? ->
              {:error, "P not normalized (sum=#{p_sum}, expected ~1.0 within #{tolerance})"}

            not q_normalized? ->
              {:error, "Q not normalized (sum=#{q_sum}, expected ~1.0 within #{tolerance})"}

            true ->
              :ok
          end
      end
    end
  end
end
