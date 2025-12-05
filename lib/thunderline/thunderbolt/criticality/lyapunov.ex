defmodule Thunderline.Thunderbolt.Criticality.Lyapunov do
  @moduledoc """
  Lyapunov exponent (λ̂) estimator for trajectory divergence analysis.

  The maximal Lyapunov exponent quantifies how quickly nearby trajectories
  diverge in phase space. Positive λ indicates chaos; negative λ indicates
  stable convergence.

  ## Mathematical Foundation

  For two trajectories x(t) and x'(t) starting at distance δ₀:

      λ = lim_{t→∞} (1/t) · ln(||x(t) - x'(t)|| / δ₀)

  ## Interpretation

  - λ < 0: Stable, trajectories converge
  - λ ≈ 0: Marginal, edge of stability
  - λ > 0: Chaotic, trajectories diverge exponentially

  ## For PAC Agents

  - λ ≤ 0: Safe operation
  - λ > 0: Trigger safe mode, thought paths diverging chaotically
  - λ >> 0: Emergency intervention required

  ## Usage

      {:ok, lambda} = Lyapunov.estimate(trajectory_samples)
  """

  @type trajectory_point :: list(float()) | %{state: list(float()), time: number()}
  @type result :: {:ok, float()} | {:error, atom()}

  @doc """
  Estimates the maximal Lyapunov exponent from trajectory data.

  ## Parameters

  - `trajectory` - List of state vectors (time-ordered)
  - `opts` - Options:
    - `:method` - `:rosenstein` (default), `:wolf`, `:kantz`
    - `:embedding_dim` - Embedding dimension for reconstruction (default: 3)
    - `:delay` - Time delay for embedding (default: 1)
    - `:epsilon` - Initial separation for neighbor search (default: 0.01)

  ## Returns

  `{:ok, lambda}` or `{:error, reason}`.
  """
  @spec estimate(list(trajectory_point()), keyword()) :: result()
  def estimate(trajectory, opts \\ []) when is_list(trajectory) do
    method = Keyword.get(opts, :method, :rosenstein)

    case method do
      :rosenstein -> rosenstein(trajectory, opts)
      :wolf -> wolf_algorithm(trajectory, opts)
      :kantz -> kantz_algorithm(trajectory, opts)
      :simple -> simple_divergence(trajectory, opts)
      _ -> {:error, :unknown_method}
    end
  end

  @doc """
  Quick stability check using recent trajectory samples.
  Returns true if system appears stable (λ ≤ threshold).
  """
  @spec stable?(list(trajectory_point()), keyword()) :: boolean()
  def stable?(trajectory, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.0)

    case estimate(trajectory, Keyword.put(opts, :method, :simple)) do
      {:ok, lambda} -> lambda <= threshold
      # Assume stable on error
      {:error, _} -> true
    end
  end

  @doc """
  Computes instantaneous divergence rate between two trajectories.
  """
  @spec divergence_rate(list(trajectory_point()), list(trajectory_point())) :: result()
  def divergence_rate(traj1, traj2) when is_list(traj1) and is_list(traj2) do
    if length(traj1) < 2 or length(traj2) < 2 do
      {:error, :insufficient_samples}
    else
      distances =
        Enum.zip(traj1, traj2)
        |> Enum.map(fn {p1, p2} -> euclidean_distance(p1, p2) end)

      # Compute rate of change of log(distance)
      log_distances =
        distances
        |> Enum.filter(&(&1 > 1.0e-15))
        |> Enum.map(&:math.log/1)

      if length(log_distances) < 2 do
        {:error, :trajectories_too_close}
      else
        # Linear regression slope ≈ Lyapunov exponent
        {:ok, linear_slope(log_distances)}
      end
    end
  end

  # ===========================================================================
  # Private: Rosenstein Algorithm
  # ===========================================================================

  defp rosenstein(trajectory, opts) do
    # Rosenstein et al. (1993) algorithm
    # Fast method using nearest neighbors

    embedding_dim = Keyword.get(opts, :embedding_dim, 3)
    delay = Keyword.get(opts, :delay, 1)
    min_separation = Keyword.get(opts, :min_separation, 10)

    vectors = extract_vectors(trajectory)

    if length(vectors) < embedding_dim + min_separation do
      {:error, :insufficient_samples}
    else
      # Create time-delay embedding
      embedded = embed_trajectory(vectors, embedding_dim, delay)

      if length(embedded) < min_separation * 2 do
        {:error, :insufficient_embedded_points}
      else
        # Find nearest neighbors and track divergence
        divergences = compute_divergences(embedded, min_separation)

        if length(divergences) == 0 do
          {:ok, 0.0}
        else
          # Average slope of log(divergence) vs time
          lambda = mean_divergence_slope(divergences)
          {:ok, lambda}
        end
      end
    end
  end

  defp embed_trajectory(vectors, dim, delay) do
    n = length(vectors)
    max_start = n - (dim - 1) * delay

    if max_start <= 0 do
      []
    else
      0..(max_start - 1)
      |> Enum.map(fn i ->
        0..(dim - 1)
        |> Enum.map(fn d -> Enum.at(vectors, i + d * delay) end)
        |> List.flatten()
      end)
    end
  end

  defp compute_divergences(embedded, min_separation) do
    n = length(embedded)

    0..(n - min_separation - 1)
    |> Enum.map(fn i ->
      point = Enum.at(embedded, i)

      # Find nearest neighbor with temporal separation
      {nearest_idx, _dist} = find_nearest_neighbor(embedded, point, i, min_separation)

      if nearest_idx do
        # Track divergence over time
        track_divergence(embedded, i, nearest_idx, min(20, n - max(i, nearest_idx) - 1))
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp find_nearest_neighbor(embedded, point, current_idx, min_sep) do
    n = length(embedded)

    result =
      0..(n - 1)
      |> Enum.reject(fn j -> abs(j - current_idx) < min_sep end)
      |> Enum.map(fn j ->
        other = Enum.at(embedded, j)
        {j, euclidean_distance(point, other)}
      end)
      |> Enum.min_by(fn {_, d} -> d end, fn -> {nil, :infinity} end)

    case result do
      {nil, _} -> {nil, nil}
      {_idx, dist} when dist == :infinity -> {nil, nil}
      pair -> pair
    end
  end

  defp track_divergence(embedded, i, j, steps) when steps > 0 do
    0..(steps - 1)
    |> Enum.map(fn k ->
      p1 = Enum.at(embedded, i + k)
      p2 = Enum.at(embedded, j + k)

      if p1 && p2 do
        euclidean_distance(p1, p2)
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp track_divergence(_, _, _, _), do: []

  defp mean_divergence_slope(divergences) do
    # Average the log-divergence slopes
    slopes =
      divergences
      |> Enum.map(fn divs ->
        log_divs =
          divs
          |> Enum.filter(&(&1 > 1.0e-15))
          |> Enum.map(&:math.log/1)

        if length(log_divs) >= 2 do
          linear_slope(log_divs)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if length(slopes) > 0 do
      Enum.sum(slopes) / length(slopes)
    else
      0.0
    end
  end

  # ===========================================================================
  # Private: Wolf Algorithm (Simplified)
  # ===========================================================================

  defp wolf_algorithm(trajectory, opts) do
    # Wolf et al. (1985) algorithm - simplified version
    # Tracks fiducial trajectory and replacement neighbors

    epsilon = Keyword.get(opts, :epsilon, 0.01)
    vectors = extract_vectors(trajectory)
    n = length(vectors)

    if n < 10 do
      {:error, :insufficient_samples}
    else
      # Initialize
      {lambdas, _} =
        Enum.reduce(1..(n - 1), {[], 0}, fn i, {acc_lambdas, prev_neighbor_idx} ->
          current = Enum.at(vectors, i)
          _prev = Enum.at(vectors, i - 1)

          # Find neighbor distance growth
          neighbor_idx =
            if prev_neighbor_idx > 0 and prev_neighbor_idx < n do
              prev_neighbor_idx
            else
              find_epsilon_neighbor(vectors, current, i, epsilon)
            end

          if neighbor_idx && neighbor_idx < n do
            neighbor = Enum.at(vectors, neighbor_idx)
            dist = euclidean_distance(current, neighbor)

            if dist > epsilon do
              lambda_local = :math.log(dist / epsilon)
              {[lambda_local | acc_lambdas], find_epsilon_neighbor(vectors, current, i, epsilon)}
            else
              {acc_lambdas, neighbor_idx}
            end
          else
            {acc_lambdas, prev_neighbor_idx}
          end
        end)

      if length(lambdas) > 0 do
        {:ok, Enum.sum(lambdas) / length(lambdas)}
      else
        {:ok, 0.0}
      end
    end
  end

  defp find_epsilon_neighbor(vectors, point, current_idx, epsilon) do
    vectors
    |> Enum.with_index()
    |> Enum.reject(fn {_, j} -> abs(j - current_idx) < 5 end)
    |> Enum.filter(fn {v, _} -> euclidean_distance(point, v) < epsilon * 10 end)
    |> Enum.min_by(fn {v, _} -> euclidean_distance(point, v) end, fn -> {nil, nil} end)
    |> elem(1)
  end

  # ===========================================================================
  # Private: Kantz Algorithm (Simplified)
  # ===========================================================================

  defp kantz_algorithm(trajectory, opts) do
    # Kantz (1994) algorithm - uses local slopes
    # More robust but similar to Rosenstein
    rosenstein(trajectory, Keyword.merge(opts, method: :rosenstein))
  end

  # ===========================================================================
  # Private: Simple Divergence
  # ===========================================================================

  defp simple_divergence(trajectory, _opts) do
    vectors = extract_vectors(trajectory)
    n = length(vectors)

    if n < 3 do
      {:error, :insufficient_samples}
    else
      # Simple approach: look at variance growth
      # Split into halves and compare local variance
      half = div(n, 2)
      first_half = Enum.take(vectors, half)
      second_half = Enum.drop(vectors, half) |> Enum.take(half)

      var1 = trajectory_variance(first_half)
      var2 = trajectory_variance(second_half)

      if var1 > 1.0e-10 do
        lambda = :math.log(var2 / var1) / half
        {:ok, lambda}
      else
        {:ok, 0.0}
      end
    end
  end

  defp trajectory_variance(vectors) do
    if length(vectors) == 0 do
      0.0
    else
      flat = List.flatten(vectors)
      n = length(flat)

      if n == 0 do
        0.0
      else
        mean = Enum.sum(flat) / n
        Enum.reduce(flat, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / n
      end
    end
  end

  # ===========================================================================
  # Private: Utility Functions
  # ===========================================================================

  defp extract_vectors(trajectory) do
    Enum.map(trajectory, fn
      %{state: s} when is_list(s) -> s
      v when is_list(v) -> v
      v when is_number(v) -> [v]
      _ -> [0.0]
    end)
  end

  defp euclidean_distance(v1, v2) when is_list(v1) and is_list(v2) do
    max_len = max(length(v1), length(v2))
    v1_padded = v1 ++ List.duplicate(0.0, max_len - length(v1))
    v2_padded = v2 ++ List.duplicate(0.0, max_len - length(v2))

    Enum.zip(v1_padded, v2_padded)
    |> Enum.reduce(0.0, fn {a, b}, acc -> acc + (a - b) * (a - b) end)
    |> :math.sqrt()
  end

  defp euclidean_distance(v1, v2), do: euclidean_distance(List.wrap(v1), List.wrap(v2))

  defp linear_slope(values) do
    n = length(values)

    if n < 2 do
      0.0
    else
      # Simple linear regression slope: Σ((x-x̄)(y-ȳ)) / Σ((x-x̄)²)
      x_mean = (n - 1) / 2.0
      y_mean = Enum.sum(values) / n

      {num, denom} =
        values
        |> Enum.with_index()
        |> Enum.reduce({0.0, 0.0}, fn {y, x}, {n_acc, d_acc} ->
          x_diff = x - x_mean
          y_diff = y - y_mean
          {n_acc + x_diff * y_diff, d_acc + x_diff * x_diff}
        end)

      if denom > 1.0e-10, do: num / denom, else: 0.0
    end
  end

  # ===========================================================================
  # Streaming API
  # ===========================================================================

  @doc """
  Creates a streaming Lyapunov estimator state.
  """
  @spec stream_init(keyword()) :: map()
  def stream_init(opts \\ []) do
    window_size = Keyword.get(opts, :window_size, 50)
    ema_alpha = Keyword.get(opts, :ema_alpha, 0.2)

    %{
      trajectory: :queue.new(),
      window_size: window_size,
      ema_alpha: ema_alpha,
      current_lambda: 0.0,
      sample_count: 0
    }
  end

  @doc """
  Updates streaming λ with a new trajectory point.
  """
  @spec stream_update(map(), trajectory_point()) :: {float(), map()}
  def stream_update(state, point) do
    trajectory = :queue.in(point, state.trajectory)

    trajectory =
      if :queue.len(trajectory) > state.window_size do
        {_, new_q} = :queue.out(trajectory)
        new_q
      else
        trajectory
      end

    new_state = %{state | trajectory: trajectory, sample_count: state.sample_count + 1}

    if :queue.len(trajectory) >= 10 do
      points = :queue.to_list(trajectory)

      new_lambda =
        case estimate(points, method: :simple) do
          {:ok, lambda} ->
            state.ema_alpha * lambda + (1 - state.ema_alpha) * state.current_lambda

          {:error, _} ->
            state.current_lambda
        end

      {new_lambda, %{new_state | current_lambda: new_lambda}}
    else
      {state.current_lambda, new_state}
    end
  end
end
