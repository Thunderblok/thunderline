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
    raise "Not implemented - Phase 3.3"
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
    raise "Not implemented - Phase 3.3"
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
    raise "Not implemented - Phase 3.3"
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
    raise "Not implemented - Phase 3.3"
  end

  @doc """
  Compute all distance metrics at once.

  Efficient batch computation of KL, cross-entropy, Hellinger, and JS divergence.

  ## Arguments

  - `p` - True distribution (Nx tensor)
  - `q` - Approximate distribution (Nx tensor)

  ## Returns

  Map with all metrics:

      %{
        kl_divergence: float(),
        cross_entropy: float(),
        hellinger: float(),
        js_divergence: float()
      }

  ## Examples

      metrics = Distance.all_metrics(parzen_hist, model_hist)
      # => %{
      #   kl_divergence: 0.123,
      #   cross_entropy: 1.456,
      #   hellinger: 0.234,
      #   js_divergence: 0.067
      # }
  """
  @spec all_metrics(Nx.Tensor.t(), Nx.Tensor.t()) :: %{
          kl_divergence: float(),
          cross_entropy: float(),
          hellinger: float(),
          js_divergence: float()
        }
  def all_metrics(p, q) when is_struct(p, Nx.Tensor) and is_struct(q, Nx.Tensor) do
    raise "Not implemented - Phase 3.3"
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
    raise "Not implemented - Phase 3.3"
  end
end
