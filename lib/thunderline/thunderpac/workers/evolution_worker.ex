defmodule Thunderline.Thunderpac.Workers.EvolutionWorker do
  @moduledoc """
  Oban worker for PAC trait evolution (HC-Ω-6).

  This worker:
  1. Pulls recent reflex events for a given PAC
  2. Runs Cerebros multivariate TPE on a local embedding vector
  3. Updates the PAC's trait_vector via Thunderpac.State

  ## Job Args

  - `job_id` - TraitsEvolutionJob ID
  - `pac_id` - Target PAC ID

  ## Execution Flow

  ```
  1. Load TraitsEvolutionJob and PAC
  2. Fetch recent reflex events (within fitness_window)
  3. Compute aggregate metrics from reflex events
  4. Initialize TPE with current PAC traits
  5. Run TPE iterations until convergence or max_iterations
  6. Apply best traits to PAC
  7. Update job with results
  ```

  ## Events Emitted

  - `pac.evolution.worker.started`
  - `pac.evolution.worker.iteration`
  - `pac.evolution.worker.completed`
  - `pac.evolution.worker.failed`
  """

  use Oban.Worker,
    queue: :pac_evolution,
    max_attempts: 3,
    unique: [period: 60, fields: [:args, :queue]]

  require Logger

  alias Thunderline.Thunderpac.Resources.{PAC, TraitsEvolutionJob}
  alias Thunderline.Thunderpac.Evolution
  alias Thunderline.Thunderbolt.Cerebros.TPEBridge
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Event

  @telemetry_event [:thunderline, :pac, :evolution_worker]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    job_id = args["job_id"]
    pac_id = args["pac_id"]

    started = System.monotonic_time(:millisecond)

    Logger.info("[EvolutionWorker] Starting evolution for PAC #{pac_id}, job #{job_id}")

    :telemetry.execute(@telemetry_event, %{started: 1}, %{pac_id: pac_id, job_id: job_id})

    with {:ok, job} <- load_job(job_id),
         {:ok, pac} <- load_pac(pac_id),
         {:ok, job} <- mark_job_started(job, pac),
         {:ok, reflex_events} <- fetch_reflex_events(pac_id, job.fitness_window_ms),
         {:ok, metrics} <- compute_metrics_from_reflexes(reflex_events),
         {:ok, result} <- run_evolution(job, pac, metrics),
         {:ok, _updated_pac} <- apply_evolved_traits(pac, result),
         {:ok, _job} <- complete_job(job, result, metrics) do
      duration = System.monotonic_time(:millisecond) - started

      Logger.info(
        "[EvolutionWorker] Completed evolution for PAC #{pac_id} in #{duration}ms, fitness: #{result.best_fitness}"
      )

      :telemetry.execute(
        @telemetry_event,
        %{completed: 1, duration_ms: duration, fitness: result.best_fitness},
        %{pac_id: pac_id, job_id: job_id, iterations: result.iterations}
      )

      emit_worker_event(:completed, pac_id, job_id, %{
        fitness: result.best_fitness,
        iterations: result.iterations,
        duration_ms: duration
      })

      :ok
    else
      {:error, reason} ->
        Logger.error("[EvolutionWorker] Failed for PAC #{pac_id}: #{inspect(reason)}")

        if job_id do
          fail_job(job_id, inspect(reason))
        end

        emit_worker_event(:failed, pac_id, job_id, %{error: inspect(reason)})

        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Job & PAC Loading
  # ═══════════════════════════════════════════════════════════════

  defp load_job(nil), do: {:error, :missing_job_id}

  defp load_job(job_id) do
    case Ash.get(TraitsEvolutionJob, job_id) do
      {:ok, job} -> {:ok, job}
      {:error, _} -> {:error, :job_not_found}
    end
  end

  defp load_pac(nil), do: {:error, :missing_pac_id}

  defp load_pac(pac_id) do
    case Ash.get(PAC, pac_id) do
      {:ok, pac} -> {:ok, pac}
      {:error, _} -> {:error, :pac_not_found}
    end
  end

  defp mark_job_started(job, pac) do
    with {:ok, job} <- TraitsEvolutionJob.start(job),
         {:ok, job} <- TraitsEvolutionJob.set_initial_traits(job, pac.trait_vector || []) do
      {:ok, job}
    end
  end

  defp fail_job(job_id, error_message) do
    case load_job(job_id) do
      {:ok, job} -> TraitsEvolutionJob.fail(job, error_message)
      _ -> :ok
    end
  end

  defp complete_job(job, result, metrics) do
    result_map = %{
      best_fitness: result.best_fitness,
      best_traits: result.best_traits,
      iterations: result.iterations,
      converged: result.converged,
      fitness_improvement: result.fitness_improvement
    }

    metrics_summary = %{
      reflex_count: metrics.reflex_count,
      avg_plv: metrics.plv,
      avg_entropy: metrics.entropy,
      avg_lambda_hat: metrics.lambda_hat,
      dominant_reflex_type: metrics.dominant_reflex_type
    }

    TraitsEvolutionJob.complete(job, result_map, metrics_summary)
  end

  # ═══════════════════════════════════════════════════════════════
  # Reflex Event Fetching
  # ═══════════════════════════════════════════════════════════════

  defp fetch_reflex_events(pac_id, fitness_window_ms) do
    # Calculate time window
    since = DateTime.add(DateTime.utc_now(), -fitness_window_ms, :millisecond)

    # Query reflex events from event store or collect from PubSub history
    # For now, we'll query from the local event buffer if available
    # fetch_from_event_store/2 always returns {:ok, _} (rescue fallback to synthetic data)
    {:ok, events} = fetch_from_event_store(pac_id, since)

    Logger.debug("[EvolutionWorker] Fetched #{length(events)} reflex events for PAC #{pac_id}")

    {:ok, events}
  end

  defp fetch_from_event_store(pac_id, since) do
    # Try to fetch from Thunderflow event buffer
    # This is a simplified implementation - in production, query the event store
    try do
      # EventBuffer.snapshot/1 returns up to N recent events (default 100)
      events =
        Thunderline.Thunderflow.EventBuffer.snapshot()
        |> Enum.filter(fn event ->
          is_reflex_event?(event) and
            matches_pac?(event, pac_id) and
            after_time?(event, since)
        end)

      {:ok, events}
    rescue
      _ ->
        # Fallback: generate synthetic events from PAC state
        {:ok, generate_synthetic_reflex_data(pac_id)}
    end
  end

  defp is_reflex_event?(%{name: "bolt.reflex.triggered"}), do: true
  defp is_reflex_event?(%{name: "bolt.reflex.chunk_triggered"}), do: true
  defp is_reflex_event?(%{kind: :reflex}), do: true
  defp is_reflex_event?(%{message: msg}) when is_binary(msg), do: String.contains?(msg, "reflex")
  defp is_reflex_event?(_), do: false

  defp matches_pac?(%{payload: %{pac_id: event_pac_id}}, pac_id), do: event_pac_id == pac_id
  # Include events without pac_id
  defp matches_pac?(_, _), do: true

  defp after_time?(%{timestamp: ts}, since) when is_struct(ts, DateTime) do
    DateTime.compare(ts, since) in [:gt, :eq]
  end

  defp after_time?(%{ts: ts}, since) when is_integer(ts) do
    event_time = DateTime.from_unix!(ts, :millisecond)
    DateTime.compare(event_time, since) in [:gt, :eq]
  end

  defp after_time?(_, _), do: true

  defp generate_synthetic_reflex_data(pac_id) do
    # Generate synthetic data when no real events available
    # This allows evolution to proceed with random exploration
    Logger.debug("[EvolutionWorker] Using synthetic reflex data for PAC #{pac_id}")

    Enum.map(1..10, fn i ->
      %{
        type: Enum.random([:stability, :chaos, :trust, :decay]),
        reflex_type: Enum.random([:stability, :chaos, :trust, :decay]),
        trigger: Enum.random([:low_stability, :chaos_spike, :trust_boost, :idle_decay]),
        data: %{
          sigma_flow: :rand.uniform(),
          plv: :rand.uniform(),
          lambda_hat: 0.2 + :rand.uniform() * 0.2,
          entropy: :rand.uniform()
        },
        ts: System.system_time(:millisecond) - i * 1000
      }
    end)
  end

  # ═══════════════════════════════════════════════════════════════
  # Metrics Computation
  # ═══════════════════════════════════════════════════════════════

  defp compute_metrics_from_reflexes([]) do
    # Return default metrics when no events
    {:ok,
     %{
       plv: 0.5,
       entropy: 0.5,
       lambda_hat: 0.273,
       lyapunov: 0.0,
       reflex_count: 0,
       dominant_reflex_type: :none,
       stability_score: 0.5,
       chaos_score: 0.5
     }}
  end

  defp compute_metrics_from_reflexes(events) do
    reflex_count = length(events)

    # Count reflex types
    type_counts =
      events
      |> Enum.group_by(fn e ->
        Map.get(e, :reflex_type) || Map.get(e, :type) || :unknown
      end)
      |> Enum.map(fn {type, evts} -> {type, length(evts)} end)
      |> Map.new()

    dominant_reflex_type =
      type_counts
      |> Enum.max_by(fn {_type, count} -> count end, fn -> {:none, 0} end)
      |> elem(0)

    # Extract numeric metrics from event data
    all_data =
      events
      |> Enum.map(fn e -> Map.get(e, :data, %{}) end)
      |> Enum.filter(&is_map/1)

    plv = average_metric(all_data, :plv, 0.5)
    entropy = average_metric(all_data, :entropy, 0.5)
    lambda_hat = average_metric(all_data, :lambda_hat, 0.273)
    sigma_flow = average_metric(all_data, :sigma_flow, 0.5)

    # Compute derived scores
    stability_count = Map.get(type_counts, :stability, 0)
    chaos_count = Map.get(type_counts, :chaos, 0)

    stability_score =
      if reflex_count > 0 do
        # More stability events = lower score
        1.0 - stability_count / reflex_count
      else
        0.5
      end

    chaos_score =
      if reflex_count > 0 do
        chaos_count / reflex_count
      else
        0.5
      end

    # Estimate Lyapunov from entropy variance
    lyapunov = estimate_lyapunov(all_data)

    {:ok,
     %{
       plv: plv,
       entropy: entropy,
       lambda_hat: lambda_hat,
       lyapunov: lyapunov,
       reflex_count: reflex_count,
       dominant_reflex_type: dominant_reflex_type,
       stability_score: stability_score,
       chaos_score: chaos_score,
       sigma_flow: sigma_flow,
       type_counts: type_counts
     }}
  end

  defp average_metric(data_list, key, default) do
    values =
      data_list
      |> Enum.map(&Map.get(&1, key))
      |> Enum.filter(&is_number/1)

    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      default
    end
  end

  defp estimate_lyapunov(data_list) do
    # Estimate Lyapunov exponent from entropy time series
    entropies =
      data_list
      |> Enum.map(&Map.get(&1, :entropy))
      |> Enum.filter(&is_number/1)

    if length(entropies) > 2 do
      # Simple approximation: variance in entropy indicates chaos
      mean = Enum.sum(entropies) / length(entropies)

      variance =
        entropies
        |> Enum.map(fn e -> (e - mean) ** 2 end)
        |> Enum.sum()
        |> Kernel./(length(entropies))

      # Map variance to Lyapunov-like value
      # Near 0 = edge of chaos, positive = chaotic, negative = stable
      (:math.sqrt(variance) - 0.5) * 2
    else
      0.0
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # TPE Evolution
  # ═══════════════════════════════════════════════════════════════

  defp run_evolution(job, pac, metrics) do
    profile = job.evolution_profile
    max_iterations = job.max_iterations
    convergence_threshold = job.convergence_threshold
    tpe_params = job.tpe_params

    # Get current traits
    current_traits = Evolution.vector_to_traits(pac.trait_vector)

    # Initialize state
    state = %{
      best_fitness: 0.0,
      best_traits: current_traits,
      current_traits: current_traits,
      iterations: 0,
      converged: false,
      fitness_history: [],
      pac: pac,
      profile: profile,
      metrics: metrics
    }

    # Run evolution loop
    final_state = evolution_loop(state, max_iterations, convergence_threshold, tpe_params, job)

    fitness_improvement =
      if length(final_state.fitness_history) > 1 do
        List.last(final_state.fitness_history) - List.first(final_state.fitness_history)
      else
        0.0
      end

    {:ok,
     %{
       best_fitness: final_state.best_fitness,
       best_traits: final_state.best_traits,
       iterations: final_state.iterations,
       converged: final_state.converged,
       fitness_improvement: fitness_improvement,
       fitness_history: final_state.fitness_history
     }}
  end

  defp evolution_loop(state, max_iterations, _convergence_threshold, _tpe_params, _job)
       when state.iterations >= max_iterations do
    Logger.debug("[EvolutionWorker] Reached max iterations: #{max_iterations}")
    state
  end

  defp evolution_loop(state, max_iterations, convergence_threshold, tpe_params, job) do
    # 1. Suggest new traits
    suggested_traits = suggest_traits(state.current_traits, tpe_params, state.iterations)

    # 2. Compute fitness for suggested traits
    # Create a mock PAC with suggested traits for fitness evaluation
    mock_pac = %{state.pac | trait_vector: Evolution.traits_to_vector(suggested_traits)}
    profile_config = Evolution.get_profile(state.profile) |> elem(1)
    fitness = Evolution.compute_fitness(state.metrics, mock_pac, profile_config)

    # 3. Update state
    {new_best_fitness, new_best_traits} =
      if fitness.total > state.best_fitness do
        {fitness.total, suggested_traits}
      else
        {state.best_fitness, state.best_traits}
      end

    new_state = %{
      state
      | best_fitness: new_best_fitness,
        best_traits: new_best_traits,
        current_traits: suggested_traits,
        iterations: state.iterations + 1,
        fitness_history: state.fitness_history ++ [fitness.total]
    }

    # 4. Record iteration in job
    Task.start(fn ->
      TraitsEvolutionJob.record_iteration(
        job,
        fitness.total,
        Evolution.traits_to_vector(suggested_traits)
      )
    end)

    # 5. Check convergence
    converged = check_convergence(new_state.fitness_history, convergence_threshold)

    if converged do
      Logger.debug(
        "[EvolutionWorker] Converged at iteration #{new_state.iterations}, fitness: #{new_best_fitness}"
      )

      %{new_state | converged: true}
    else
      # Continue iteration
      evolution_loop(new_state, max_iterations, convergence_threshold, tpe_params, job)
    end
  end

  defp suggest_traits(current_traits, tpe_params, iteration) do
    # Try to use TPE bridge if available
    case TPEBridge.suggest_params(tpe_params) do
      {:ok, suggested} ->
        Map.merge(current_traits, normalize_suggestions(suggested))

      {:error, _} ->
        # Fallback: adaptive random search
        adaptive_mutation(current_traits, iteration)
    end
  end

  defp normalize_suggestions(suggested) when is_map(suggested) do
    suggested
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, clamp(v)}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), clamp(v)}
    end)
    |> Enum.into(%{})
  rescue
    _ -> %{}
  end

  defp normalize_suggestions(_), do: %{}

  defp adaptive_mutation(traits, iteration) do
    # Decrease mutation rate over time (simulated annealing)
    base_rate = 0.3
    decay = 0.95
    mutation_rate = base_rate * :math.pow(decay, iteration)

    traits
    |> Enum.map(fn {key, value} ->
      if :rand.uniform() < mutation_rate do
        # Gaussian-like mutation
        delta = (:rand.uniform() - 0.5) * 0.2
        {key, clamp(value + delta)}
      else
        {key, value}
      end
    end)
    |> Enum.into(%{})
  end

  defp check_convergence(history, _threshold) when length(history) < 5, do: false

  defp check_convergence(history, threshold) do
    # Check if last 5 iterations have minimal improvement
    recent = Enum.take(history, -5)
    max_recent = Enum.max(recent)
    min_recent = Enum.min(recent)

    improvement = max_recent - min_recent
    improvement < threshold
  end

  defp clamp(v) when is_number(v), do: max(0.0, min(1.0, v))
  defp clamp(v), do: v

  # ═══════════════════════════════════════════════════════════════
  # Apply Evolved Traits
  # ═══════════════════════════════════════════════════════════════

  defp apply_evolved_traits(pac, result) do
    # Convert traits map to vector
    new_trait_vector = Evolution.traits_to_vector(result.best_traits)

    # Update PAC's trait_vector and persona
    updated_persona =
      Map.merge(pac.persona || %{}, %{
        "evolved" => true,
        "last_evolution" => %{
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "fitness" => result.best_fitness,
          "iterations" => result.iterations,
          "converged" => result.converged
        }
      })

    # Use Ash to update the PAC
    case Ash.update(pac, %{trait_vector: new_trait_vector, persona: updated_persona}) do
      {:ok, updated_pac} ->
        Logger.info("[EvolutionWorker] Applied evolved traits to PAC #{pac.id}")

        # Broadcast state change
        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "pac.state.changed",
          %{
            name: "pac.state.changed",
            payload: %{
              pac_id: pac.id,
              event_type: :traits_evolved,
              new_traits: new_trait_vector,
              fitness: result.best_fitness
            }
          }
        )

        {:ok, updated_pac}

      {:error, reason} ->
        Logger.warning("[EvolutionWorker] Failed to update PAC #{pac.id}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Emission
  # ═══════════════════════════════════════════════════════════════

  defp emit_worker_event(event_type, pac_id, job_id, extra) do
    event_name = "pac.evolution.worker.#{event_type}"

    payload =
      Map.merge(
        %{
          pac_id: pac_id,
          job_id: job_id,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        extra
      )

    case Event.new(name: event_name, source: :pac, payload: payload, meta: %{pipeline: :realtime}) do
      {:ok, event} ->
        EventBus.publish_event(event)

      {:error, reason} ->
        Logger.warning("[EvolutionWorker] Failed to emit event: #{inspect(reason)}")
    end
  end
end
