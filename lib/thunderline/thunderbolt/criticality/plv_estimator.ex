defmodule Thunderline.Thunderbolt.Criticality.PLVEstimator do
  @moduledoc """
  Phase Locking Value (PLV) estimator for attention pattern synchrony.

  PLV measures the synchronization strength between oscillatory signals.
  In the context of PAC agents, it quantifies how strongly attention patterns
  lock to each other across processing cycles.

  ## Mathematical Foundation

  For two signals with phases φ₁(t) and φ₂(t):

      PLV = |⟨e^(i·Δφ(t))⟩|

  Where Δφ(t) = φ₁(t) - φ₂(t) is the phase difference.

  A PLV of 1.0 means perfect synchrony (fixed phase relationship).
  A PLV of 0.0 means no synchrony (random phase relationship).

  ## Interpretation for PAC Agents

  - PLV > 0.60: Over-synchronized → repetitive loops
  - PLV 0.30-0.60: Metastable → creative, coherent thinking
  - PLV < 0.30: Desynchronized → rambling, unfocused

  ## Usage

      {:ok, plv} = PLVEstimator.estimate(attention_patterns)
  """

  @type attention_pattern :: %{
          optional(:weights) => list(float()),
          optional(:focus_score) => float(),
          optional(:timestamp) => integer()
        }

  @type result :: {:ok, float()} | {:error, atom()}

  @doc """
  Estimates PLV from a sequence of attention patterns.

  ## Parameters

  - `patterns` - List of attention pattern maps with `:weights` or `:focus_score`
  - `opts` - Options:
    - `:method` - Estimation method: `:hilbert` (default), `:wavelet`, `:simple`
    - `:reference_pattern` - Optional reference for pairwise PLV

  ## Returns

  `{:ok, plv}` where plv is in range [0.0, 1.0], or `{:error, reason}`.
  """
  @spec estimate(list(attention_pattern()), keyword()) :: result()
  def estimate(patterns, opts \\ []) when is_list(patterns) do
    method = Keyword.get(opts, :method, :simple)

    case method do
      :hilbert -> estimate_hilbert(patterns, opts)
      :wavelet -> estimate_wavelet(patterns, opts)
      :simple -> estimate_simple(patterns, opts)
      _ -> {:error, :unknown_method}
    end
  end

  @doc """
  Estimates PLV from raw phase values (in radians).
  """
  @spec from_phases(list(float())) :: result()
  def from_phases(phases) when is_list(phases) do
    n = length(phases)

    if n < 2 do
      {:error, :insufficient_samples}
    else
      # Compute mean resultant vector length
      # PLV = |1/N · Σ e^(iφₖ)|
      {sum_cos, sum_sin} =
        Enum.reduce(phases, {0.0, 0.0}, fn phase, {cos_acc, sin_acc} ->
          {cos_acc + :math.cos(phase), sin_acc + :math.sin(phase)}
        end)

      mean_cos = sum_cos / n
      mean_sin = sum_sin / n
      plv = :math.sqrt(mean_cos * mean_cos + mean_sin * mean_sin)

      {:ok, min(1.0, max(0.0, plv))}
    end
  end

  @doc """
  Computes pairwise PLV between two pattern sequences.
  """
  @spec pairwise(list(attention_pattern()), list(attention_pattern())) :: result()
  def pairwise(patterns1, patterns2) when is_list(patterns1) and is_list(patterns2) do
    # Extract phases from both pattern sequences
    phases1 = extract_phases(patterns1)
    phases2 = extract_phases(patterns2)

    # Ensure same length
    min_len = min(length(phases1), length(phases2))

    if min_len < 2 do
      {:error, :insufficient_samples}
    else
      phase_diffs =
        Enum.zip(Enum.take(phases1, min_len), Enum.take(phases2, min_len))
        |> Enum.map(fn {p1, p2} -> p1 - p2 end)

      from_phases(phase_diffs)
    end
  end

  # ===========================================================================
  # Private: Estimation Methods
  # ===========================================================================

  defp estimate_simple(patterns, _opts) do
    phases = extract_phases(patterns)
    from_phases(phases)
  end

  defp estimate_hilbert(patterns, _opts) do
    # Hilbert transform to extract instantaneous phase
    # Simplified: use focus scores as signal, apply discrete Hilbert
    signal = extract_signal(patterns)

    if length(signal) < 4 do
      # Fall back to simple method for short sequences
      estimate_simple(patterns, [])
    else
      phases = hilbert_phases(signal)
      from_phases(phases)
    end
  end

  defp estimate_wavelet(patterns, _opts) do
    # Morlet wavelet for phase extraction
    # Simplified implementation using windowed FFT
    signal = extract_signal(patterns)

    if length(signal) < 8 do
      estimate_simple(patterns, [])
    else
      phases = wavelet_phases(signal)
      from_phases(phases)
    end
  end

  # ===========================================================================
  # Private: Phase Extraction
  # ===========================================================================

  defp extract_phases(patterns) do
    patterns
    |> Enum.map(&pattern_to_phase/1)
  end

  defp pattern_to_phase(%{weights: weights}) when is_list(weights) do
    # Convert weight distribution to phase
    # Using weighted circular mean
    n = length(weights)

    if n == 0 do
      0.0
    else
      indexed =
        weights
        |> Enum.with_index()
        |> Enum.reduce({0.0, 0.0}, fn {w, i}, {cos_acc, sin_acc} ->
          angle = 2.0 * :math.pi() * i / n
          {cos_acc + w * :math.cos(angle), sin_acc + w * :math.sin(angle)}
        end)

      {cos_sum, sin_sum} = indexed
      :math.atan2(sin_sum, cos_sum)
    end
  end

  defp pattern_to_phase(%{focus_score: score}) when is_number(score) do
    # Map focus score to phase
    # Score in [0,1] -> phase in [0, 2π]
    2.0 * :math.pi() * score
  end

  defp pattern_to_phase(_), do: 0.0

  defp extract_signal(patterns) do
    Enum.map(patterns, fn
      %{focus_score: score} when is_number(score) -> score
      %{weights: [w | _]} when is_number(w) -> w
      _ -> 0.0
    end)
  end

  # ===========================================================================
  # Private: Hilbert Transform (Simplified)
  # ===========================================================================

  defp hilbert_phases(signal) do
    # Simplified discrete Hilbert transform
    # For production: use proper FFT-based Hilbert or Nx
    n = length(signal)

    # Create analytic signal approximation using finite impulse response
    analytic =
      signal
      |> Enum.with_index()
      |> Enum.map(fn {_, i} ->
        # Approximate Hilbert transform with kernel
        hilbert_value = approximate_hilbert(signal, i, n)
        {Enum.at(signal, i), hilbert_value}
      end)

    # Extract phases
    Enum.map(analytic, fn {real, imag} ->
      :math.atan2(imag, real)
    end)
  end

  defp approximate_hilbert(signal, i, n) do
    # Simplified FIR Hilbert approximation
    # h[k] = 2/(π·k) for odd k, 0 for even k
    half_window = min(4, div(n, 2))

    Enum.reduce(-half_window..half_window, 0.0, fn k, acc ->
      if k != 0 and rem(k, 2) != 0 do
        j = i + k

        if j >= 0 and j < n do
          h = 2.0 / (:math.pi() * k)
          acc + h * Enum.at(signal, j)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  # ===========================================================================
  # Private: Wavelet Transform (Simplified)
  # ===========================================================================

  defp wavelet_phases(signal) do
    # Simplified Morlet wavelet phase extraction
    # Using windowed analysis
    n = length(signal)
    window_size = min(8, n)

    signal
    |> Enum.with_index()
    |> Enum.map(fn {_, i} ->
      start_idx = max(0, i - div(window_size, 2))
      end_idx = min(n, start_idx + window_size)
      window = Enum.slice(signal, start_idx, end_idx - start_idx)
      morlet_phase(window)
    end)
  end

  defp morlet_phase(window) do
    # Morlet wavelet: ψ(t) = e^(iω₀t) · e^(-t²/2)
    # Compute convolution and extract phase
    n = length(window)
    omega0 = 6.0

    {real_sum, imag_sum} =
      window
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0.0}, fn {val, i}, {r_acc, i_acc} ->
        t = (i - n / 2.0) / (n / 4.0)
        gaussian = :math.exp(-t * t / 2.0)

        {r_acc + val * gaussian * :math.cos(omega0 * t),
         i_acc + val * gaussian * :math.sin(omega0 * t)}
      end)

    :math.atan2(imag_sum, real_sum)
  end

  # ===========================================================================
  # Streaming API
  # ===========================================================================

  @doc """
  Creates a streaming PLV estimator state.
  """
  @spec stream_init(keyword()) :: map()
  def stream_init(opts \\ []) do
    window_size = Keyword.get(opts, :window_size, 20)

    %{
      phases: :queue.new(),
      window_size: window_size,
      current_plv: 0.5,
      sample_count: 0
    }
  end

  @doc """
  Updates streaming PLV with a new pattern.
  """
  @spec stream_update(map(), attention_pattern()) :: {float(), map()}
  def stream_update(state, pattern) do
    phase = pattern_to_phase(pattern)
    phases = :queue.in(phase, state.phases)

    {phases, dropped} =
      if :queue.len(phases) > state.window_size do
        {{:value, _}, new_q} = :queue.out(phases)
        {new_q, 1}
      else
        {phases, 0}
      end

    phase_list = :queue.to_list(phases)

    new_plv =
      case from_phases(phase_list) do
        {:ok, plv} -> plv
        {:error, _} -> state.current_plv
      end

    new_state = %{
      state
      | phases: phases,
        current_plv: new_plv,
        sample_count: state.sample_count + 1 - dropped
    }

    {new_plv, new_state}
  end
end
