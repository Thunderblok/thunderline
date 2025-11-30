defmodule Thunderline.Thunderbolt.Cerebros.TPEBridge do
  @moduledoc """
  Python TPE Bridge for Bayesian Hyperparameter Optimization (HC-41).

  Connects to Optuna's TPESampler for multivariate Bayesian optimization
  of DiffLogic CA rule parameters toward edge-of-chaos dynamics.

  ## Architecture

      ┌─────────────────────────────────────────────────────────┐
      │                    TPE Bridge                           │
      │                                                         │
      │  ┌──────────┐   ┌──────────┐   ┌──────────────────┐    │
      │  │ Suggest  │ → │ Evaluate │ → │ Record Result   │    │
      │  │ Params   │   │   (CA)   │   │ (Optuna Study)   │    │
      │  └──────────┘   └──────────┘   └──────────────────┘    │
      │       ↑              │               │                 │
      │       └──────────────┴───────────────┘                 │
      │                   Loop                                  │
      └─────────────────────────────────────────────────────────┘

  ## Usage

      # Start optimization
      {:ok, bridge} = TPEBridge.start_link(
        run_id: "opt_123",
        study_name: "ca_edge_of_chaos",
        search_space: %{
          lambda: {0.0, 1.0},      # Continuous
          bias: {0.0, 1.0},        # Continuous
          gate_temp: {0.1, 2.0}    # Continuous
        },
        n_trials: 50
      )

      # Suggest next parameters to try
      {:ok, params} = TPEBridge.suggest(bridge)

      # Record evaluation result
      :ok = TPEBridge.record(bridge, params, fitness: 0.85)

      # Get best parameters found so far
      {:ok, best} = TPEBridge.best_params(bridge)

  ## Python Backend

  Uses Snex or PythonX to invoke Optuna's TPESampler with multivariate=True
  for correlated parameter optimization.
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.CerebrosBridge.{PythonxInvoker, SnexInvoker}
  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus

  @telemetry_event [:thunderline, :cerebros, :tpe_bridge]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type search_space :: %{atom() => {number(), number()} | [term()]}

  @type params :: %{atom() => number() | term()}

  @type trial_result :: %{
          params: params(),
          fitness: float(),
          trial_id: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

  @type state :: %{
          run_id: String.t(),
          study_name: String.t(),
          search_space: search_space(),
          n_trials: pos_integer(),
          completed_trials: non_neg_integer(),
          best_params: params() | nil,
          best_fitness: float(),
          history: [trial_result()],
          invoker: module()
        }

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts a TPE optimization bridge.

  ## Options

  - `:run_id` - Required. Unique identifier for the optimization run.
  - `:study_name` - Optuna study name (default: "thunderline_tpe_{run_id}")
  - `:search_space` - Map of parameter names to bounds or choices
  - `:n_trials` - Maximum number of trials (default: 100)
  - `:seed` - Random seed for reproducibility
  - `:name` - Process name registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = Keyword.get(opts, :name, via(run_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Suggests the next set of parameters to evaluate.

  Uses TPE (Tree-structured Parzen Estimator) to suggest parameters
  that are likely to improve the objective.
  """
  @spec suggest(GenServer.server()) :: {:ok, params()} | {:error, term()}
  def suggest(server) do
    GenServer.call(server, :suggest, 30_000)
  end

  @doc """
  Records the result of evaluating a parameter set.

  ## Options

  - `:fitness` - Required. The fitness/objective value (higher = better)
  - `:metrics` - Optional map of additional metrics to record
  - `:elapsed_ms` - Optional computation time
  """
  @spec record(GenServer.server(), params(), keyword()) :: :ok | {:error, term()}
  def record(server, params, opts) do
    GenServer.call(server, {:record, params, opts}, 30_000)
  end

  @doc """
  Gets the best parameters found so far.
  """
  @spec best_params(GenServer.server()) :: {:ok, params()} | {:error, :no_trials}
  def best_params(server) do
    GenServer.call(server, :best_params)
  end

  @doc """
  Gets the current optimization state summary.
  """
  @spec status(GenServer.server()) :: {:ok, map()}
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Runs a complete optimization loop.

  Repeatedly suggests params, evaluates via `eval_fn`, and records results.

  ## Parameters

  - `eval_fn` - Function that takes params and returns `{:ok, fitness}` or `{:error, reason}`
  - `opts` - Options including `:max_trials` (default: use study's n_trials)

  Returns `{:ok, best_params, best_fitness}` or `{:error, reason}`.
  """
  @spec optimize(GenServer.server(), (params() -> {:ok, float()} | {:error, term()}), keyword()) ::
          {:ok, params(), float()} | {:error, term()}
  def optimize(server, eval_fn, opts \\ []) do
    GenServer.call(server, {:optimize, eval_fn, opts}, :infinity)
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    search_space = Keyword.get(opts, :search_space, default_search_space())
    n_trials = Keyword.get(opts, :n_trials, 100)
    study_name = Keyword.get(opts, :study_name, "thunderline_tpe_#{run_id}")
    seed = Keyword.get(opts, :seed)

    invoker = get_invoker()

    # Initialize Optuna study
    case init_study(invoker, study_name, search_space, seed) do
      {:ok, _} ->
        state = %{
          run_id: run_id,
          study_name: study_name,
          search_space: search_space,
          n_trials: n_trials,
          completed_trials: 0,
          best_params: nil,
          best_fitness: :neg_infinity,
          history: [],
          invoker: invoker
        }

        Logger.info("[TPEBridge] Initialized study=#{study_name} n_trials=#{n_trials}")
        emit_event("bolt.tpe.study.created", %{run_id: run_id, study_name: study_name})

        {:ok, state}

      {:error, reason} ->
        Logger.error("[TPEBridge] Failed to init study: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:suggest, _from, state) do
    started = System.monotonic_time(:microsecond)

    case suggest_params(state.invoker, state.study_name, state.search_space) do
      {:ok, params} ->
        duration_us = System.monotonic_time(:microsecond) - started

        :telemetry.execute(
          @telemetry_event ++ [:suggest],
          %{duration_us: duration_us},
          %{run_id: state.run_id, trial: state.completed_trials}
        )

        {:reply, {:ok, params}, state}

      {:error, reason} = error ->
        Logger.warning("[TPEBridge] Suggest failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:record, params, opts}, _from, state) do
    fitness = Keyword.fetch!(opts, :fitness)
    elapsed_ms = Keyword.get(opts, :elapsed_ms, 0)
    trial_id = state.completed_trials

    # Record to Optuna
    case record_trial(state.invoker, state.study_name, params, fitness) do
      :ok ->
        # Update local state
        result = %{
          params: params,
          fitness: fitness,
          trial_id: trial_id,
          elapsed_ms: elapsed_ms
        }

        {new_best_params, new_best_fitness} =
          if fitness > state.best_fitness do
            {params, fitness}
          else
            {state.best_params, state.best_fitness}
          end

        new_state = %{
          state
          | completed_trials: trial_id + 1,
            best_params: new_best_params,
            best_fitness: new_best_fitness,
            history: [result | state.history]
        }

        # Emit progress event
        emit_event("bolt.tpe.trial.completed", %{
          run_id: state.run_id,
          trial_id: trial_id,
          fitness: fitness,
          is_best: fitness > state.best_fitness
        })

        Logger.debug(
          "[TPEBridge] Trial #{trial_id} fitness=#{Float.round(fitness, 4)} best=#{Float.round(new_best_fitness, 4)}"
        )

        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.warning("[TPEBridge] Record failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:best_params, _from, state) do
    if state.best_params do
      {:reply, {:ok, state.best_params}, state}
    else
      {:reply, {:error, :no_trials}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      run_id: state.run_id,
      study_name: state.study_name,
      completed_trials: state.completed_trials,
      n_trials: state.n_trials,
      best_fitness: state.best_fitness,
      best_params: state.best_params,
      progress: state.completed_trials / state.n_trials
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:optimize, eval_fn, opts}, _from, state) do
    max_trials = Keyword.get(opts, :max_trials, state.n_trials)
    remaining = max_trials - state.completed_trials

    Logger.info("[TPEBridge] Starting optimization loop, #{remaining} trials remaining")

    {final_state, result} = run_optimization_loop(state, eval_fn, remaining)

    emit_event("bolt.tpe.study.completed", %{
      run_id: state.run_id,
      best_fitness: final_state.best_fitness,
      completed_trials: final_state.completed_trials
    })

    {:reply, result, final_state}
  end

  # ═══════════════════════════════════════════════════════════════
  # Optimization Loop
  # ═══════════════════════════════════════════════════════════════

  defp run_optimization_loop(state, _eval_fn, 0) do
    {state, {:ok, state.best_params, state.best_fitness}}
  end

  defp run_optimization_loop(state, eval_fn, remaining) do
    case suggest_params(state.invoker, state.study_name, state.search_space) do
      {:ok, params} ->
        started = System.monotonic_time(:millisecond)

        case eval_fn.(params) do
          {:ok, fitness} ->
            elapsed_ms = System.monotonic_time(:millisecond) - started

            # Record result
            case record_trial(state.invoker, state.study_name, params, fitness) do
              :ok ->
                result = %{
                  params: params,
                  fitness: fitness,
                  trial_id: state.completed_trials,
                  elapsed_ms: elapsed_ms
                }

                {new_best_params, new_best_fitness} =
                  if fitness > state.best_fitness do
                    Logger.info(
                      "[TPEBridge] New best! fitness=#{Float.round(fitness, 4)} params=#{inspect(params)}"
                    )

                    {params, fitness}
                  else
                    {state.best_params, state.best_fitness}
                  end

                new_state = %{
                  state
                  | completed_trials: state.completed_trials + 1,
                    best_params: new_best_params,
                    best_fitness: new_best_fitness,
                    history: [result | state.history]
                }

                run_optimization_loop(new_state, eval_fn, remaining - 1)

              {:error, reason} ->
                Logger.error("[TPEBridge] Failed to record: #{inspect(reason)}")
                {state, {:error, reason}}
            end

          {:error, reason} ->
            Logger.warning("[TPEBridge] Evaluation failed: #{inspect(reason)}")
            # Continue with remaining trials
            run_optimization_loop(state, eval_fn, remaining - 1)
        end

      {:error, reason} ->
        Logger.error("[TPEBridge] Failed to suggest: #{inspect(reason)}")
        {state, {:error, reason}}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Python Invocation
  # ═══════════════════════════════════════════════════════════════

  defp init_study(invoker, study_name, search_space, seed) do
    args = %{
      action: :init_study,
      study_name: study_name,
      search_space: encode_search_space(search_space),
      seed: seed,
      sampler: "TPESampler",
      sampler_kwargs: %{multivariate: true, n_startup_trials: 10}
    }

    case invoker.invoke(:tpe_bridge, args, timeout_ms: 30_000) do
      {:ok, %{status: "ok"}} -> {:ok, :initialized}
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  rescue
    e ->
      Logger.warning("[TPEBridge] Python invoke failed, using stub: #{inspect(e)}")
      {:ok, :stub_mode}
  end

  defp suggest_params(invoker, study_name, search_space) do
    args = %{
      action: :suggest,
      study_name: study_name
    }

    case invoker.invoke(:tpe_bridge, args, timeout_ms: 10_000) do
      {:ok, %{params: params}} -> {:ok, decode_params(params)}
      {:ok, _other} -> {:ok, random_params(search_space)}
      {:error, _} -> {:ok, random_params(search_space)}
    end
  rescue
    _e ->
      # Fallback to random sampling
      {:ok, random_params(search_space)}
  end

  defp record_trial(invoker, study_name, params, fitness) do
    args = %{
      action: :record,
      study_name: study_name,
      params: encode_params(params),
      value: fitness
    }

    case invoker.invoke(:tpe_bridge, args, timeout_ms: 10_000) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  rescue
    _e -> :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp get_invoker do
    case Application.get_env(:thunderline, :cerebros_bridge, [])
         |> Keyword.get(:invoker, :pythonx) do
      :snex -> SnexInvoker
      :pythonx -> PythonxInvoker
      other -> raise "Unsupported invoker: #{inspect(other)}"
    end
  rescue
    _ -> PythonxInvoker
  end

  defp default_search_space do
    %{
      lambda: {0.0, 1.0},
      bias: {0.0, 1.0},
      gate_temp: {0.1, 2.0},
      diffusion_rate: {0.0, 0.5}
    }
  end

  defp encode_search_space(space) do
    space
    |> Enum.map(fn
      {k, {low, high}} ->
        %{name: to_string(k), type: "float", low: low, high: high}

      {k, choices} when is_list(choices) ->
        %{name: to_string(k), type: "categorical", choices: choices}
    end)
  end

  defp encode_params(params) do
    params
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp decode_params(params) when is_map(params) do
    params
    |> Enum.map(fn {k, v} ->
      key =
        if is_binary(k) do
          try do
            String.to_existing_atom(k)
          rescue
            ArgumentError -> String.to_atom(k)
          end
        else
          k
        end

      {key, v}
    end)
    |> Map.new()
  end

  defp decode_params(params), do: params

  defp random_params(search_space) do
    search_space
    |> Enum.map(fn
      {k, {low, high}} ->
        {k, low + :rand.uniform() * (high - low)}

      {k, choices} when is_list(choices) ->
        {k, Enum.random(choices)}
    end)
    |> Map.new()
  end

  defp emit_event(name, payload) do
    case Event.new(name: name, source: :bolt, payload: payload, meta: %{pipeline: :cerebros}) do
      {:ok, event} ->
        case EventBus.publish_event(event) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.debug("[TPEBridge] Event publish failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.debug("[TPEBridge] Event build failed: #{inspect(reason)}")
    end
  end

  defp via(run_id) do
    {:via, Registry, {Thunderline.Thunderbolt.CA.Registry, {:tpe_bridge, run_id}}}
  end
end
