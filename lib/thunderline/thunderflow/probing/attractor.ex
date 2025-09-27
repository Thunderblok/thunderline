defmodule Thunderline.Thunderflow.Probing.Attractor do
  @moduledoc """
  Attractor/dynamical heuristics over stored `ProbeLap` embeddings.

  Adapts the Raincatcher attractor summary pipeline to operate on
  embeddings queried from the database instead of NDJSON logs.
  """
  alias Thunderline.Thunderflow.Resources.{ProbeLap, ProbeAttractorSummary, ProbeRun}

  @type opts :: [m: pos_integer(), tau: pos_integer(), min_points: pos_integer()]

  def summarize_run(%ProbeRun{id: run_id}, opts \\ []) do
    m = Keyword.get(opts, :m, 3)
    tau = Keyword.get(opts, :tau, 1)
    min_points = Keyword.get(opts, :min_points, 30)

    embeddings = load_embeddings(run_id)
    points = length(embeddings)
    delay = delay_embed(embeddings, m, tau)
    rows = length(delay)

    cd = correlation_dimension(delay)
    ly = lyapunov(delay)
    ro = lyapunov_rosenstein(delay, m: m)
    reliable? = points >= min_points and rows > 5

    %{
      run_id: run_id,
      points: points,
      delay_rows: rows,
      m: m,
      tau: tau,
      corr_dim: cd,
      lyap: ly,
      lyap_r2: ro.r2,
      lyap_window: window_to_string(ro.window),
      reliable: reliable?,
      note: reliability_note(reliable?, points, rows, min_points)
    }
  end

  defp reliability_note(true, _p, _r, _min),
    do: "heuristics only; no scaling region validation performed"

  defp reliability_note(false, p, r, min),
    do: "insufficient data (points=#{p}, delay_rows=#{r}, min_points=#{min})"

  defp load_embeddings(run_id) do
    # Stream lap embeddings ordered by lap_index
    {:ok, laps} =
      Ash.read(ProbeLap, %{run_id: run_id}, action: :read)
      |> case do
        {:ok, q} -> {:ok, Enum.sort_by(q, & &1.lap_index)}
        other -> other
      end

    Enum.map(laps, & &1.embedding)
  rescue
    _ -> []
  end

  # Delay embedding, correlation dimension, lyapunov reused (simplified copy)
  defp delay_embed(vectors, m, tau) when m >= 1 and tau >= 1 do
    t = length(vectors)

    case t - (m - 1) * tau do
      l when l <= 0 ->
        []

      l ->
        for i <- 0..(l - 1) do
          seg = for j <- 0..(m - 1), do: Enum.at(vectors, i + j * tau)
          List.flatten(seg)
        end
    end
  end

  defp correlation_dimension([]), do: 0.0

  defp correlation_dimension(delay_vectors) do
    dists = pairwise_distances(delay_vectors)

    if dists == [] do
      0.0
    else
      {dmin, dmax} = min_max_positive(dists)
      radii = build_radii(dmin, dmax)
      c_vals = Enum.map(radii, fn r -> frac_lt(dists, r) end)
      log_r = Enum.map(radii, &safe_log/1)
      log_c = Enum.map(c_vals, &safe_log/1)
      slope(log_r, log_c)
    end
  end

  defp safe_log(x) when x <= 0.0, do: -1.0e12
  defp safe_log(x), do: :math.log(x)

  defp slope(xs, ys) do
    n = length(xs)
    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n

    num =
      Enum.zip(xs, ys)
      |> Enum.reduce(0.0, fn {x, y}, acc -> acc + (x - mean_x) * (y - mean_y) end)

    den = Enum.reduce(xs, 0.0, fn x, acc -> acc + :math.pow(x - mean_x, 2) end)
    if den == 0.0, do: 0.0, else: num / den
  end

  defp pairwise_distances(vs) do
    n = length(vs)
    arr = :array.from_list(vs)

    for i <- 0..(n - 2), j <- (i + 1)..(n - 1) do
      vi = :array.get(i, arr)
      vj = :array.get(j, arr)
      euclidean(vi, vj)
    end
  end

  defp euclidean(a, b) do
    Enum.zip(a, b)
    |> Enum.reduce(0.0, fn {x, y}, acc -> acc + (x - y) * (x - y) end)
    |> :math.sqrt()
  end

  defp min_max_positive(dists) do
    pos = Enum.filter(dists, &(&1 > 0))

    if pos == [] do
      {1.0e-6, 1.0}
    else
      {Enum.min(pos), Enum.max(pos)}
    end
  end

  defp build_radii(dmin, dmax) do
    log_min = :math.log10(dmin)
    log_max = :math.log10(dmax)
    steps = 20

    for k <- 0..(steps - 1) do
      p = k / (steps - 1)
      :math.pow(10.0, log_min + p * (log_max - log_min))
    end
  end

  defp frac_lt(dists, r) do
    cnt = Enum.count(dists, &(&1 < r))
    (cnt / max(1, length(dists))) |> clamp_prob()
  end

  defp clamp_prob(x) when x <= 0.0, do: 1.0e-12
  defp clamp_prob(x) when x >= 1.0, do: 1.0 - 1.0e-12
  defp clamp_prob(x), do: x

  defp lyapunov([]), do: 0.0
  defp lyapunov([_]), do: 0.0

  defp lyapunov(delay_vectors) do
    n = length(delay_vectors)
    arr = :array.from_list(delay_vectors)

    divs =
      for t <- 0..(n - 2) do
        vt = :array.get(t, arr)
        {j, d0} = nearest_neighbor_simple(vt, arr, t)

        if j < n - 1 do
          vtn1 = :array.get(t + 1, arr)
          vjn1 = :array.get(j + 1, arr)
          d1 = euclidean(vtn1, vjn1) + 1.0e-9
          :math.log(d1 / (d0 + 1.0e-9))
        else
          nil
        end
      end
      |> Enum.reject(&is_nil/1)

    if divs == [], do: 0.0, else: Enum.sum(divs) / length(divs)
  end

  defp nearest_neighbor_simple(vec, arr, exclude_index) do
    last = :array.size(arr) - 1

    Enum.reduce(0..last, {nil, :infinity}, fn i, {best_i, best_d} ->
      if i == exclude_index do
        {best_i, best_d}
      else
        candidate = :array.get(i, arr)
        d = euclidean(vec, candidate)
        if d < best_d, do: {i, d}, else: {best_i, best_d}
      end
    end)
  end

  # Rosenstein estimator (simplified) -------------------------------------------------
  defp lyapunov_rosenstein([], _opts), do: %{lyap: 0.0, r2: 0.0, window: {0, 0}}
  defp lyapunov_rosenstein([_], _opts), do: %{lyap: 0.0, r2: 0.0, window: {0, 0}}

  defp lyapunov_rosenstein(delay_vectors, opts) do
    max_h = min(25, length(delay_vectors) - 2)

    if max_h < 2,
      do: %{lyap: 0.0, r2: 0.0, window: {0, 0}},
      else: rosenstein_fit(delay_vectors, max_h)
  end

  defp rosenstein_fit(vs, max_h) do
    # Build average divergence series
    series =
      for h <- 1..max_h do
        logs =
          for t <- 0..(length(vs) - 1 - h) do
            {j, d0} = nearest_neighbor_simple(Enum.at(vs, t), :array.from_list(vs), t)

            if j && j + h < length(vs) do
              d1 = euclidean(Enum.at(vs, t + h), Enum.at(vs, j + h)) + 1.0e-9
              :math.log(d1 / (d0 + 1.0e-9))
            end
          end
          |> Enum.reject(&is_nil/1)

        if logs == [], do: nil, else: Enum.sum(logs) / length(logs)
      end

    # windows starting at 1 of size >=6
    windows = for w <- 6..max_h, do: {1, w}

    {best, fit} =
      Enum.reduce(windows, {{0, 0}, %{r2: -1.0}}, fn {s, e} = win, {_, best_fit} ->
        seg = Enum.slice(series, (s - 1)..(e - 1)) |> Enum.reject(&is_nil/1)

        if length(seg) < e - s + 1 do
          {win, best_fit}
        else
          xs = Enum.to_list(s..e)
          f = linreg(xs, seg)
          if f.r2 > best_fit.r2, do: {win, f}, else: {win, best_fit}
        end
      end)

    %{window: {h1, h2}} = %{window: best}
    %{lyap: fit.slope, r2: fit.r2, window: {h1, h2}}
  end

  defp linreg(xs, ys) do
    n = length(xs)
    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n

    {num, den} =
      Enum.zip(xs, ys)
      |> Enum.reduce({0.0, 0.0}, fn {x, y}, {a, b} ->
        {a + (x - mean_x) * (y - mean_y), b + :math.pow(x - mean_x, 2)}
      end)

    slope = if den == 0.0, do: 0.0, else: num / den
    intercept = mean_y - slope * mean_x
    ss_tot = Enum.reduce(ys, 0.0, fn y, acc -> acc + :math.pow(y - mean_y, 2) end)

    ss_res =
      Enum.zip(xs, ys)
      |> Enum.reduce(0.0, fn {x, y}, acc -> acc + :math.pow(y - (slope * x + intercept), 2) end)

    r2 = if ss_tot == 0.0, do: 0.0, else: 1.0 - ss_res / ss_tot
    %{slope: slope, intercept: intercept, r2: r2}
  end

  defp window_to_string({a, b}), do: "#{a}..#{b}"
  defp window_to_string(_), do: nil
end
