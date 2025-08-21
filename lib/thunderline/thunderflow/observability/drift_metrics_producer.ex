defmodule Thunderline.Thunderflow.Observability.DriftMetricsProducer do
  @moduledoc """
  DriftMetricsProducer

  Domain: ThunderFlow (observability).

  Consumes embedding/time-series events (`{:timeseries_embedding, data}`) emitted
  via the real-time pipeline (see `RealTimePipeline` side-channel broadcast to
  topic `"drift:embedding"`). Maintains a sliding window of recent embedding
  vectors and incrementally approximates:

  * λ (Lyapunov-like divergence): average log ratio of distances between
    successive embedding vectors.
  * Correlation dimension (D2) using a simplified Grassberger–Procaccia style
    count of pair distances below multiple radii.
  * Coherence: reused placeholder function combining stability & attractor thickness.

  Broadcasts drift updates over topic `"drift:demo"` consumed by
  `ThunderlineWeb.CerebrosLive`.

  NOTE: This is an approximate / lightweight implementation intended for live
  UI feedback, not scientific-grade estimates. Window size & radii are tunable.
  """
  use GenServer
  require Logger
  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @topic "drift:demo"
  @embedding_topic "drift:embedding"
  @tick 3_000 # periodic recompute cadence (ms)
  @window_size 300
  @radii [0.05, 0.1, 0.2, 0.4]

  @type drift_sample :: %{
          lambda: float(),
          corr_dim: float(),
          sample: non_neg_integer(),
          coherence: float(),
          updated_at: DateTime.t()
        }

  # Public API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Return the latest drift metrics snapshot (non-blocking approximation for UI/tests).

  Fields: :lambda, :corr_dim, :coherence, :sample, :updated_at
  """
  def current_metrics do
    try do
      GenServer.call(__MODULE__, :metrics, 2_000)
    catch
      :exit, _ -> %{lambda: 0.0, corr_dim: 0.0, coherence: 0.0, sample: 0, updated_at: nil}
    end
  end

  # GenServer callbacks
  @impl true
  def init(_opts) do
    Logger.info("[DriftMetricsProducer] starting (embedding-driven mode)")
    Phoenix.PubSub.subscribe(@pubsub, @embedding_topic)
    :timer.send_interval(@tick, :tick)

    {:ok,
     %{
       lambda: 0.0,
       corr_dim: 0.0,
       coherence: 0.0,
       sample: 0,
       updated_at: DateTime.utc_now(),
       embeddings: :queue.new(),
       last_vector: nil
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    # Recompute drift metrics from current window
    {lambda, d2} = compute_metrics(state.embeddings, state.last_vector)
    coherence = recompute_coherence(lambda, d2)
    now = DateTime.utc_now()
    new_state = %{state | lambda: lambda, corr_dim: d2, coherence: coherence, updated_at: now}
    payload = Map.take(new_state, [:lambda, :corr_dim, :sample, :coherence]) |> Map.put(:updated_at, now)
    PubSub.broadcast(@pubsub, @topic, {:drift_update, payload})
    {:noreply, new_state}
  end

  def handle_info({:timeseries_embedding, data}, state) do
    vector = extract_vector(data)
    {queue, size} = enqueue_embedding(state.embeddings, vector)
    sample = state.sample + 1
    new_state = %{state | embeddings: queue, sample: sample, last_vector: vector}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:metrics, _from, state) do
    payload = Map.take(state, [:lambda, :corr_dim, :coherence, :sample, :updated_at])
    {:reply, payload, state}
  end

  # Fall-through for unexpected messages
  def handle_info(_other, state), do: {:noreply, state}

  defp recompute_coherence(lambda, d2) do
    stability = 1.0 / (1.0 + :math.exp(8 * lambda))
    thickness = :math.exp(-0.05 * :math.pow(max(d2 - 3.0, 0.0), 2))
    min(max(stability * thickness, 0.0), 1.0)
  end

  # ----- Embedding Window Management -----
  defp enqueue_embedding(queue, vector) do
    q2 = :queue.in(vector, queue)
    if :queue.len(q2) > @window_size do
      {{:value, _dropped}, q3} = :queue.out(q2)
      {q3, :queue.len(q3)}
    else
      {q2, :queue.len(q2)}
    end
  end

  defp extract_vector(%{embedding: v}) when is_list(v), do: :erlang.list_to_tuple(v)
  defp extract_vector(%{embedding: v}) when is_tuple(v), do: v
  defp extract_vector(%{"embedding" => v}) when is_list(v), do: :erlang.list_to_tuple(v)
  defp extract_vector(%{"embedding" => v}) when is_tuple(v), do: v
  defp extract_vector(v) when is_list(v), do: :erlang.list_to_tuple(v)
  defp extract_vector(v) when is_tuple(v), do: v
  defp extract_vector(_), do: {}

  # Compute λ and correlation dimension approximations
  defp compute_metrics(queue, last_vector) do
    embeddings = :queue.to_list(queue)
    cond do
      length(embeddings) < 5 -> {0.0, 0.0}
      true ->
        lambda = estimate_lambda(embeddings)
        d2 = estimate_corr_dim(embeddings)
        {lambda, d2}
    end
  rescue
    _ -> {0.0, 0.0}
  end

  defp estimate_lambda([]), do: 0.0
  defp estimate_lambda([_]), do: 0.0
  defp estimate_lambda(list) do
    diffs =
      list
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> distance(a, b) end)
      |> Enum.reject(&(&1 <= 0.0))

    case diffs do
      [] -> 0.0
      [_] -> 0.0
      _ ->
        ratios =
          diffs
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [d1, d2] -> if d1 > 0.0, do: d2 / d1, else: 1.0 end)
          |> Enum.reject(&(&1 <= 0.0))
        if ratios == [], do: 0.0, else: ratios |> Enum.map(&:math.log/1) |> average() |> clamp(-0.05, 0.6)
    end
  end

  defp estimate_corr_dim(list) do
    points = list
    n = length(points)
    if n < 10 do
      0.0
    else
      # Sample subset for O(n^2) control
      sample = if n > 120, do: Enum.take(points, 120), else: points
      pair_dists = for i <- 0..(length(sample)-2), j <- (i+1)..(length(sample)-1), do: distance(Enum.at(sample, i), Enum.at(sample, j))
      counts = Enum.map(@radii, fn r -> Enum.count(pair_dists, & &1 <= r) end)
      # Avoid log(0); shift counts minimally
      log_r = Enum.map(@radii, &:math.log/1)
      log_c = counts |> Enum.map(&:math.log(max(&1, 1)))
      slope(log_r, log_c) |> clamp(0.0, 6.0)
    end
  end

  defp distance({}, _), do: 0.0
  defp distance(_, {}), do: 0.0
  defp distance(a, b) when tuple_size(a) == tuple_size(b) do
    size = tuple_size(a)
    0..(size-1)
    |> Enum.reduce(0.0, fn i, acc ->
      da = elem(a, i) - elem(b, i)
      acc + da * da
    end)
    |> :math.sqrt()
  end
  defp distance(_, _), do: 0.0

  defp slope(xs, ys) do
    n = length(xs)
    mean_x = average(xs)
    mean_y = average(ys)
    num = Enum.zip(xs, ys) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + (x - mean_x) * (y - mean_y) end)
    den = Enum.reduce(xs, 0.0, fn x, acc -> acc + :math.pow(x - mean_x, 2) end)
    if den == 0.0, do: 0.0, else: num / den
  end

  defp average(list) when is_list(list) and list != [] do
    Enum.sum(list) / length(list)
  end
  defp average(_), do: 0.0

  defp clamp(v, min_v, max_v) when v < min_v, do: min_v
  defp clamp(v, min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v
end
