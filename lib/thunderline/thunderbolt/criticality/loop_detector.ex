defmodule Thunderline.Thunderbolt.Criticality.LoopDetector do
  @moduledoc """
  Spectral loop detector for identifying repetitive thought patterns.

  Detects when a PAC agent enters repetitive loops by analyzing spectral
  energy in activation sequences. Loops manifest as peaks in the power
  spectrum at specific frequencies.

  ## Detection Methods

  1. **FFT Analysis**: Peaks in power spectrum indicate periodicity
  2. **Autocorrelation**: High self-similarity at lags > 0
  3. **Entropy**: Low entropy indicates repetition
  4. **Edit Distance**: Similar consecutive outputs

  ## Usage

      {:ok, result} = LoopDetector.detect(activation_history)
      # result = %{looping?: true, period: 5, confidence: 0.85}
  """

  @type activation :: list(float()) | float()
  @type detection_result :: %{
          looping?: boolean(),
          period: non_neg_integer() | nil,
          confidence: float(),
          method: atom()
        }

  @doc """
  Detects loops in activation sequence.

  ## Parameters

  - `history` - List of activation vectors (time-ordered, most recent last)
  - `opts` - Options:
    - `:method` - `:spectral` (default), `:autocorr`, `:entropy`, `:combined`
    - `:threshold` - Detection threshold (default: 0.7)
    - `:min_period` - Minimum loop period to detect (default: 2)
    - `:max_period` - Maximum loop period to detect (default: 20)

  ## Returns

  `{:ok, result}` with detection result map.
  """
  @spec detect(list(activation()), keyword()) :: {:ok, detection_result()}
  def detect(history, opts \\ []) when is_list(history) do
    method = Keyword.get(opts, :method, :combined)

    case method do
      :spectral -> detect_spectral(history, opts)
      :autocorr -> detect_autocorrelation(history, opts)
      :entropy -> detect_entropy(history, opts)
      :combined -> detect_combined(history, opts)
      _ -> {:ok, no_loop_result(:unknown)}
    end
  end

  @doc """
  Quick check if currently looping.
  """
  @spec looping?(list(activation()), keyword()) :: boolean()
  def looping?(history, opts \\ []) do
    case detect(history, opts) do
      {:ok, %{looping?: true}} -> true
      _ -> false
    end
  end

  @doc """
  Finds the dominant period in a sequence.
  """
  @spec find_period(list(activation()), keyword()) :: {:ok, pos_integer()} | {:error, :no_period}
  def find_period(history, opts \\ []) do
    case detect(history, Keyword.put(opts, :method, :spectral)) do
      {:ok, %{period: period}} when is_integer(period) and period > 0 ->
        {:ok, period}

      _ ->
        {:error, :no_period}
    end
  end

  # ===========================================================================
  # Private: Spectral Detection
  # ===========================================================================

  defp detect_spectral(history, opts) do
    threshold = Keyword.get(opts, :threshold, 0.7)
    min_period = Keyword.get(opts, :min_period, 2)
    max_period = Keyword.get(opts, :max_period, 20)

    signal = to_signal(history)
    n = length(signal)

    if n < min_period * 2 do
      {:ok, no_loop_result(:spectral)}
    else
      # Compute power spectrum using DFT
      power_spectrum = compute_power_spectrum(signal)

      # Find dominant frequency
      {peak_idx, peak_power, total_power} =
        power_spectrum
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} ->
          # Only look at frequencies corresponding to min_period to max_period
          period = n / max(1, i)
          period >= min_period and period <= max_period
        end)
        |> Enum.max_by(fn {power, _} -> power end, fn -> {0.0, 0} end)
        |> (fn {power, idx} -> {idx, power, Enum.sum(power_spectrum)} end).()

      if total_power > 1.0e-10 do
        # Relative power at peak indicates loop strength
        relative_power = peak_power / total_power * length(power_spectrum)
        period = if peak_idx > 0, do: round(n / peak_idx), else: 0

        if relative_power > threshold and period >= min_period do
          {:ok,
           %{
             looping?: true,
             period: period,
             confidence: min(1.0, relative_power / 2),
             method: :spectral
           }}
        else
          {:ok, no_loop_result(:spectral)}
        end
      else
        {:ok, no_loop_result(:spectral)}
      end
    end
  end

  defp compute_power_spectrum(signal) do
    # Discrete Fourier Transform (simplified)
    n = length(signal)

    if n == 0 do
      []
    else
      0..div(n, 2)
      |> Enum.map(fn k ->
        {real, imag} =
          signal
          |> Enum.with_index()
          |> Enum.reduce({0.0, 0.0}, fn {x, j}, {r, i} ->
            angle = -2.0 * :math.pi() * k * j / n
            {r + x * :math.cos(angle), i + x * :math.sin(angle)}
          end)

        (real * real + imag * imag) / n
      end)
    end
  end

  # ===========================================================================
  # Private: Autocorrelation Detection
  # ===========================================================================

  defp detect_autocorrelation(history, opts) do
    threshold = Keyword.get(opts, :threshold, 0.7)
    min_period = Keyword.get(opts, :min_period, 2)
    max_period = Keyword.get(opts, :max_period, 20)

    signal = to_signal(history)
    n = length(signal)

    if n < min_period * 2 do
      {:ok, no_loop_result(:autocorr)}
    else
      # Compute autocorrelation for different lags
      max_lag = min(max_period, div(n, 2))

      acf =
        1..max_lag
        |> Enum.map(fn lag ->
          corr = autocorrelation(signal, lag)
          {lag, corr}
        end)

      # Find peak autocorrelation (excluding lag 0)
      {peak_lag, peak_corr} =
        acf
        |> Enum.filter(fn {lag, _} -> lag >= min_period end)
        |> Enum.max_by(fn {_, corr} -> corr end, fn -> {0, 0.0} end)

      if peak_corr > threshold do
        {:ok,
         %{
           looping?: true,
           period: peak_lag,
           confidence: peak_corr,
           method: :autocorr
         }}
      else
        {:ok, no_loop_result(:autocorr)}
      end
    end
  end

  defp autocorrelation(signal, lag) do
    n = length(signal)

    if n <= lag do
      0.0
    else
      mean = Enum.sum(signal) / n

      variance =
        Enum.reduce(signal, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end)

      if variance < 1.0e-10 do
        # Constant signal = perfect autocorrelation
        1.0
      else
        covariance =
          0..(n - lag - 1)
          |> Enum.reduce(0.0, fn i, acc ->
            x1 = Enum.at(signal, i) - mean
            x2 = Enum.at(signal, i + lag) - mean
            acc + x1 * x2
          end)

        covariance / variance
      end
    end
  end

  # ===========================================================================
  # Private: Entropy Detection
  # ===========================================================================

  defp detect_entropy(history, opts) do
    # Low entropy = looping
    threshold = Keyword.get(opts, :threshold, 0.3)

    signal = to_signal(history)
    n = length(signal)

    if n < 4 do
      {:ok, no_loop_result(:entropy)}
    else
      # Compute sample entropy or permutation entropy
      entropy = sample_entropy(signal)

      # Normalize entropy (0 = perfectly repetitive, 1 = random)
      max_entropy = :math.log(n)
      normalized = if max_entropy > 0, do: entropy / max_entropy, else: 1.0

      if normalized < threshold do
        {:ok,
         %{
           looping?: true,
           period: estimate_period_from_entropy(signal),
           confidence: 1.0 - normalized,
           method: :entropy
         }}
      else
        {:ok, no_loop_result(:entropy)}
      end
    end
  end

  defp sample_entropy(signal) do
    # Approximate entropy using binned histogram
    n = length(signal)

    if n == 0 do
      0.0
    else
      {min_val, max_val} = Enum.min_max(signal)
      range = max_val - min_val

      if range < 1.0e-10 do
        # Constant = zero entropy
        0.0
      else
        # Bin the signal
        num_bins = min(10, max(2, round(:math.sqrt(n))))
        bin_width = range / num_bins

        bin_counts =
          signal
          |> Enum.map(fn x ->
            bin = min(num_bins - 1, floor((x - min_val) / bin_width))
            bin
          end)
          |> Enum.frequencies()
          |> Map.values()

        # Compute entropy
        Enum.reduce(bin_counts, 0.0, fn count, acc ->
          p = count / n
          if p > 0, do: acc - p * :math.log(p), else: acc
        end)
      end
    end
  end

  defp estimate_period_from_entropy(signal) do
    # Use run-length encoding to estimate period
    runs =
      signal
      |> Enum.chunk_by(fn x -> round(x * 10) end)
      |> Enum.map(&length/1)

    if length(runs) > 1 do
      round(Enum.sum(runs) / length(runs))
    else
      0
    end
  end

  # ===========================================================================
  # Private: Combined Detection
  # ===========================================================================

  defp detect_combined(history, opts) do
    results =
      [:spectral, :autocorr, :entropy]
      |> Enum.map(fn method ->
        case detect(history, Keyword.put(opts, :method, method)) do
          {:ok, result} -> result
          _ -> no_loop_result(method)
        end
      end)

    # Voting: loop detected if majority agree
    loop_votes = Enum.count(results, & &1.looping?)
    looping? = loop_votes >= 2

    # Take period from highest confidence detection
    best_result =
      results
      |> Enum.filter(& &1.looping?)
      |> Enum.max_by(& &1.confidence, fn -> hd(results) end)

    # Average confidence
    avg_confidence =
      if looping? do
        results
        |> Enum.filter(& &1.looping?)
        |> Enum.map(& &1.confidence)
        |> then(fn confs -> Enum.sum(confs) / max(1, length(confs)) end)
      else
        0.0
      end

    {:ok,
     %{
       looping?: looping?,
       period: best_result.period,
       confidence: avg_confidence,
       method: :combined
     }}
  end

  # ===========================================================================
  # Private: Utilities
  # ===========================================================================

  defp to_signal(history) do
    history
    |> Enum.map(fn
      x when is_number(x) -> x
      x when is_list(x) -> Enum.sum(x) / max(1, length(x))
      %{value: v} when is_number(v) -> v
      _ -> 0.0
    end)
  end

  defp no_loop_result(method) do
    %{
      looping?: false,
      period: nil,
      confidence: 0.0,
      method: method
    }
  end

  # ===========================================================================
  # Streaming API
  # ===========================================================================

  @doc """
  Creates a streaming loop detector state.
  """
  @spec stream_init(keyword()) :: map()
  def stream_init(opts \\ []) do
    window_size = Keyword.get(opts, :window_size, 30)
    check_interval = Keyword.get(opts, :check_interval, 5)

    %{
      history: :queue.new(),
      window_size: window_size,
      check_interval: check_interval,
      sample_count: 0,
      current_result: no_loop_result(:stream),
      opts: opts
    }
  end

  @doc """
  Updates streaming detector with a new activation.
  """
  @spec stream_update(map(), activation()) :: {detection_result(), map()}
  def stream_update(state, activation) do
    history = :queue.in(activation, state.history)

    history =
      if :queue.len(history) > state.window_size do
        {_, new_q} = :queue.out(history)
        new_q
      else
        history
      end

    sample_count = state.sample_count + 1

    # Only check periodically
    if rem(sample_count, state.check_interval) == 0 and :queue.len(history) >= 10 do
      points = :queue.to_list(history)

      new_result =
        case detect(points, state.opts) do
          {:ok, result} -> result
          _ -> state.current_result
        end

      new_state = %{
        state
        | history: history,
          sample_count: sample_count,
          current_result: new_result
      }

      {new_result, new_state}
    else
      new_state = %{state | history: history, sample_count: sample_count}
      {state.current_result, new_state}
    end
  end
end
