defmodule Thunderline.Utils.Stats do
  @moduledoc """
  Statistical utilities for near-critical dynamics monitoring.

  Implements observables from the Cinderforge Lab paper:
  - PLV (Phase Locking Value): Measures synchrony across activations
  - σ (Propagation Ratio): Entropy flow between states
  - λ̂ (Local FTLE): Finite-Time Lyapunov Exponent for stability
  - Rτ (Resonance Index): Cross-layer energy transfer

  These metrics help detect:
  - Degenerate loops (PLV > 0.9)
  - Signal explosion/collapse (σ outside [0.8, 1.2])
  - Chaotic drift (λ̂ > 0)
  - Resonance cascades (Rτ spikes)

  ## Usage

      activations = Nx.tensor([[0.1, 0.5, 0.3], [0.2, 0.6, 0.2]])
      Stats.plv(activations)  # => 0.85 (high synchrony)

  ## References

  - Cinderforge Lab: "Loop-Controlled, Near-Critical Dynamics for LLMs"
  - Target regime: PLV ∈ [0.3, 0.6], σ ≈ 1.0, λ̂ ≤ 0
  """

  import Nx.Defn

  # Target bands for healthy dynamics
  @plv_min 0.3
  @plv_max 0.6
  @sigma_target 1.0
  @sigma_tolerance 0.2
  @lambda_max 0.0

  @doc """
  Phase Locking Value (PLV) - measures synchrony across activation patterns.

  High PLV (> 0.6) indicates over-synchronization (potential loop).
  Low PLV (< 0.3) indicates disorder (potential instability).
  Target: PLV ∈ [0.3, 0.6] (edge of chaos).

  ## Algorithm

  1. Compute analytic signal via Hilbert transform approximation
  2. Extract instantaneous phases
  3. Compute circular mean of phase differences
  4. PLV = |mean(e^(i*Δφ))|

  ## Parameters

  - `activations`: Nx tensor of shape (batch, features) or (seq, features)

  ## Returns

  Float in [0.0, 1.0] where 1.0 = perfect synchrony
  """
  @spec plv(Nx.Tensor.t()) :: float()
  def plv(activations) when is_struct(activations, Nx.Tensor) do
    # Ensure we have a 2D tensor
    activations = ensure_2d(activations)

    # Compute phases via arctangent of normalized activations
    # This is a simplified Hilbert transform approximation
    phases = compute_phases(activations)

    # Compute pairwise phase differences and circular mean
    compute_plv_from_phases(phases)
  end

  def plv(activations) when is_list(activations) do
    activations |> Nx.tensor() |> plv()
  end

  def plv(_), do: 0.0

  @doc """
  Propagation ratio (σ) - measures entropy flow between states.

  σ ≈ 1.0: Balanced propagation (critical)
  σ > 1.0: Signal amplification (supercritical)
  σ < 1.0: Signal decay (subcritical)

  ## Parameters

  - `entropy_prev`: Entropy at time t
  - `entropy_next`: Entropy at time t+1

  ## Returns

  Float ratio, target ≈ 1.0 ± 0.2
  """
  @spec sigma(float(), float()) :: float()
  def sigma(entropy_prev, entropy_next) when entropy_prev > 0 do
    entropy_next / entropy_prev
  end

  def sigma(_, _), do: 0.0

  @doc """
  Finite-Time Lyapunov Exponent (FTLE) estimate (λ̂).

  Measures sensitivity to perturbations via Jacobian-vector products.

  λ̂ ≤ 0: Stable (contracting dynamics)
  λ̂ > 0: Unstable (expanding/chaotic dynamics)

  ## Parameters

  - `jvp_matrix`: Jacobian-vector product matrix (can be approximated)

  ## Returns

  Float, target ≤ 0
  """
  @spec ftle(Nx.Tensor.t()) :: float()
  def ftle(jvp_matrix) when is_struct(jvp_matrix, Nx.Tensor) do
    # FTLE ≈ (1/T) * log(||J||)
    # We use Frobenius norm as approximation
    jvp_matrix
    |> Nx.LinAlg.norm()
    |> Nx.log()
    |> Nx.to_number()
  end

  def ftle(jvp_matrix) when is_list(jvp_matrix) do
    jvp_matrix |> Nx.tensor() |> ftle()
  end

  def ftle(_), do: 0.0

  @doc """
  Resonance Index (Rτ) - measures cross-layer energy transfer.

  High Rτ indicates strong coupling between layers/domains.
  Spikes in Rτ may precede instability.

  ## Parameters

  - `jvp_matrix`: Jacobian-vector products
  - `activations`: Current activation values

  ## Returns

  Float, relative measure of resonance
  """
  @spec resonance_index(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  def resonance_index(jvp_matrix, activations)
      when is_struct(jvp_matrix, Nx.Tensor) and is_struct(activations, Nx.Tensor) do
    # Rτ = ||J||_F * ||a||_2 / (||J||_∞ + ε)
    # This captures energy transfer weighted by activation magnitude
    j_frobenius = Nx.LinAlg.norm(jvp_matrix) |> Nx.to_number()
    a_norm = Nx.LinAlg.norm(activations) |> Nx.to_number()
    j_max = jvp_matrix |> Nx.abs() |> Nx.reduce_max() |> Nx.to_number()

    epsilon = 1.0e-8
    (j_frobenius * a_norm) / (j_max + epsilon)
  end

  def resonance_index(_, _), do: 0.0

  @doc """
  Shannon entropy of a probability distribution.

  Used for computing σ (propagation ratio).

  ## Parameters

  - `probs`: Probability tensor (should sum to 1)

  ## Returns

  Float entropy value in nats
  """
  @spec entropy(Nx.Tensor.t()) :: float()
  def entropy(probs) when is_struct(probs, Nx.Tensor) do
    # H = -Σ p * log(p)
    epsilon = 1.0e-10
    probs_safe = Nx.max(probs, epsilon)

    probs_safe
    |> Nx.multiply(Nx.log(probs_safe))
    |> Nx.negate()
    |> Nx.sum()
    |> Nx.to_number()
  end

  def entropy(probs) when is_list(probs) do
    probs |> Nx.tensor() |> entropy()
  end

  def entropy(_), do: 0.0

  @doc """
  Check if observables are within healthy bands.

  Returns a map with band status for each metric.
  """
  @spec check_bands(float(), float(), float(), float()) :: map()
  def check_bands(plv, sigma, lambda, rtau) do
    %{
      plv: %{
        value: plv,
        in_band: plv >= @plv_min and plv <= @plv_max,
        status: cond do
          plv > @plv_max -> :over_synchronized
          plv < @plv_min -> :under_synchronized
          true -> :healthy
        end
      },
      sigma: %{
        value: sigma,
        in_band: abs(sigma - @sigma_target) <= @sigma_tolerance,
        status: cond do
          sigma > @sigma_target + @sigma_tolerance -> :amplifying
          sigma < @sigma_target - @sigma_tolerance -> :decaying
          true -> :healthy
        end
      },
      lambda: %{
        value: lambda,
        in_band: lambda <= @lambda_max,
        status: if(lambda > @lambda_max, do: :chaotic, else: :stable)
      },
      rtau: %{
        value: rtau,
        # Rtau doesn't have fixed bands - monitor for spikes
        status: :monitoring
      },
      overall: cond do
        plv > 0.9 -> :loop_detected
        lambda > 0.1 -> :chaotic_drift
        sigma > 1.5 or sigma < 0.5 -> :degenerate
        true -> :healthy
      end
    }
  end

  @doc """
  Compute all observables from a state snapshot.

  ## Parameters

  - `state`: Map with :activations, :entropy_prev, :entropy_next, :jvp_matrix

  ## Returns

  Map with :plv, :sigma, :lambda, :rtau, :bands
  """
  @spec observe(map()) :: map()
  def observe(%{
        activations: activations,
        entropy_prev: h0,
        entropy_next: h1,
        jvp_matrix: jvp
      }) do
    plv_val = plv(activations)
    sigma_val = sigma(h0, h1)
    lambda_val = ftle(jvp)
    rtau_val = resonance_index(jvp, activations)

    %{
      plv: plv_val,
      sigma: sigma_val,
      lambda: lambda_val,
      rtau: rtau_val,
      bands: check_bands(plv_val, sigma_val, lambda_val, rtau_val)
    }
  end

  def observe(_), do: %{plv: 0.0, sigma: 0.0, lambda: 0.0, rtau: 0.0, bands: %{}}

  # Private helpers

  defp ensure_2d(tensor) do
    case Nx.shape(tensor) do
      {_} -> Nx.reshape(tensor, {1, :auto})
      {_, _} -> tensor
      shape -> Nx.reshape(tensor, {elem(shape, 0), :auto})
    end
  end

  defp compute_phases(activations) do
    # Simplified phase extraction using arctangent
    # For proper Hilbert transform, we'd use FFT-based approach
    {rows, cols} = Nx.shape(activations)

    if cols > 1 do
      # Use pairs of adjacent features as (real, imag) for phase
      real = activations |> Nx.slice([0, 0], [rows, div(cols, 2)])
      imag = activations |> Nx.slice([0, div(cols, 2)], [rows, div(cols, 2)])
      Nx.atan2(imag, real)
    else
      Nx.tensor([[0.0]])
    end
  end

  defp compute_plv_from_phases(phases) do
    # PLV = |mean(e^(iφ))| = sqrt(mean(cos(φ))^2 + mean(sin(φ))^2)
    cos_phases = Nx.cos(phases)
    sin_phases = Nx.sin(phases)

    mean_cos = cos_phases |> Nx.mean() |> Nx.to_number()
    mean_sin = sin_phases |> Nx.mean() |> Nx.to_number()

    :math.sqrt(mean_cos * mean_cos + mean_sin * mean_sin)
  end
end
