defmodule Thunderline.Thunderbolt.AutoMLDriver do
  @moduledoc """
  Auto-ML Driver for Phase I HPO orchestration.

  Receives HTTP orders to create HPO studies, uses Optuna ask/tell API
  to coordinate with hpo-executor workers, logs to MLflow.

  API Endpoints:
  - POST /api/hpo/studies - Create new HPO study
  - POST /api/hpo/trials/tell - Report trial results
  - GET /api/hpo/studies/:id/status - Get study status
  """

  use GenServer
  require Logger
  alias Thunderline.Thunderbolt.HPOExecutor
  alias Thunderline.Thunderflow.EventBus

  @default_study_params %{
    "embedding_dim" => [256, 512],
    "n_layers" => [4, 8],
    "n_heads" => [4, 8],
    "lr" => [0.0001, 0.0005],
    "weight_decay" => [0.0, 0.1],
    "warmup_steps" => [100, 1000],
    "max_seq_len" => 196
  }

  # GenServer API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_study(params) do
    GenServer.call(__MODULE__, {:create_study, params})
  end

  def tell_result(study_id, trial_id, objective, artifact \\ nil) do
    GenServer.call(__MODULE__, {:tell_result, study_id, trial_id, objective, artifact})
  end

  def get_study_status(study_id) do
    GenServer.call(__MODULE__, {:get_study_status, study_id})
  end

  # GenServer Implementation
  @impl true
  def init(_opts) do
    state = %{
      studies: %{},
      active_trials: %{},
      python_ready?: false
    }

    Logger.info("[AutoMLDriver] Started")

    # Initialize Python runtime based on configured invoker - but don't crash on failure
    state =
      try do
        case cerebros_bridge_invoker() do
          :snex ->
            Logger.info("[AutoMLDriver] Initializing Snex runtime (GIL-free)...")

            case Thunderline.Thunderbolt.CerebrosBridge.SnexInvoker.init() do
              {:ok, {_interpreter, _env}} ->
                Logger.info("[AutoMLDriver] Snex runtime initialized successfully")
                %{state | python_ready?: true}

              {:error, reason} ->
                Logger.warning("[AutoMLDriver] Snex init failed (non-fatal): #{inspect(reason)}")
                state
            end

          :pythonx ->
            Logger.info("[AutoMLDriver] Initializing Pythonx runtime...")

            case Thunderline.Thunderbolt.CerebrosBridge.PythonxInvoker.init() do
              :ok ->
                Logger.info("[AutoMLDriver] Pythonx runtime initialized successfully")
                %{state | python_ready?: true}

              {:error, reason} ->
                Logger.warning(
                  "[AutoMLDriver] Pythonx init failed (non-fatal): #{inspect(reason)}"
                )

                state
            end

          other ->
            Logger.info("[AutoMLDriver] Using #{other} invoker (no initialization needed)")
            state
        end
      rescue
        error ->
          Logger.warning(
            "[AutoMLDriver] Python init raised (non-fatal): #{Exception.message(error)}"
          )

          state
      catch
        kind, reason ->
          Logger.warning(
            "[AutoMLDriver] Python init caught #{kind} (non-fatal): #{inspect(reason)}"
          )

          state
      end

    {:ok, state}
  end

  defp cerebros_bridge_invoker do
    Application.get_env(:thunderline, :cerebros_bridge, [])
    |> Keyword.get(:invoker, :subprocess)
  end

  @impl true
  def handle_call({:create_study, params}, _from, state) do
    study_id = generate_study_id(params["name"])

    study = %{
      id: study_id,
      name: params["name"],
      params: Map.merge(@default_study_params, params["params"] || %{}),
      n_trials: params["n_trials"] || 24,
      dataset_id: params["dataset_id"],
      status: :created,
      trials_completed: 0,
      trials_running: 0,
      best_trial: nil,
      created_at: DateTime.utc_now()
    }

    # Log study creation event
    EventBus.publish_event(%{
      event_type: "hpo_study_created",
      data: %{study_id: study_id, n_trials: study["n_trials"]},
      timestamp: DateTime.utc_now()
    })

    # Start initial trial batch
    # Start with 4 concurrent trials
    {:ok, study} = start_trial_batch(study, 4)

    new_state = put_in(state, [:studies, study_id], study)
    {:reply, {:ok, study_id}, new_state}
  end

  @impl true
  def handle_call({:tell_result, study_id, trial_id, objective, artifact}, _from, state) do
    case get_in(state, [:studies, study_id]) do
      nil ->
        {:reply, {:error, :study_not_found}, state}

      study ->
        # Update study with trial result
        updated_study =
          study
          |> Map.update!(:trials_completed, &(&1 + 1))
          |> Map.update!(:trials_running, &(&1 - 1))
          |> update_best_trial(trial_id, objective)

        # Log to MLflow if artifact provided
        if artifact && artifact["mlflow_run_id"] do
          log_trial_to_mlflow(study_id, trial_id, objective, artifact)
        end

        # Start next trial if study not complete
        updated_study =
          if updated_study.trials_completed < updated_study.n_trials do
            case start_next_trial(updated_study) do
              {:ok, study_with_trial} -> study_with_trial
              {:error, _reason} -> updated_study
            end
          else
            Map.put(updated_study, :status, :completed)
          end

        new_state = put_in(state, [:studies, study_id], updated_study)

        # Publish completion event
        EventBus.publish_event(%{
          event_type: "hpo_trial_completed",
          data: %{
            study_id: study_id,
            trial_id: trial_id,
            objective: objective,
            progress: "#{updated_study.trials_completed}/#{updated_study.n_trials}"
          },
          timestamp: DateTime.utc_now()
        })

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_study_status, study_id}, _from, state) do
    study = get_in(state, [:studies, study_id])
    {:reply, study, state}
  end

  # Private Functions
  defp generate_study_id(name) do
    timestamp = System.os_time(:second)
    "#{name}-#{timestamp}-#{:rand.uniform(1000)}"
  end

  defp start_trial_batch(study, batch_size) do
    # TODO: Implement Optuna ask() integration
    # For now, generate random suggestions within param bounds
    _trials =
      Enum.map(1..batch_size, fn _ ->
        suggestion = generate_suggestion(study.params)
        trial_id = "trial-#{System.unique_integer([:positive])}"

        # Enqueue trial execution
        HPOExecutor.execute_trial(study.id, trial_id, suggestion)

        trial_id
      end)

    updated_study =
      study
      |> Map.put(:trials_running, batch_size)
      |> Map.put(:status, :running)

    {:ok, updated_study}
  end

  defp start_next_trial(study) do
    suggestion = generate_suggestion(study.params)
    trial_id = "trial-#{System.unique_integer([:positive])}"

    case HPOExecutor.execute_trial(study.id, trial_id, suggestion) do
      :ok ->
        updated_study = Map.update!(study, :trials_running, &(&1 + 1))
        {:ok, updated_study}

      error ->
        error
    end
  end

  defp generate_suggestion(params) do
    # Simple random sampling within bounds (replace with Optuna later)
    Enum.into(params, %{}, fn {key, bounds} ->
      case bounds do
        [min, max] when is_number(min) and is_number(max) ->
          if is_float(min) or is_float(max) do
            {key, min + :rand.uniform() * (max - min)}
          else
            {key, Enum.random(min..max)}
          end

        [min, max] when is_integer(min) and is_integer(max) ->
          {key, Enum.random(min..max)}

        value when is_number(value) ->
          {key, value}

        _ ->
          {key, bounds}
      end
    end)
  end

  defp update_best_trial(study, trial_id, objective) do
    current_best = study.best_trial

    # Assume we're minimizing perplexity
    perplexity = objective["perplexity"] || objective[:perplexity] || 999.0

    if is_nil(current_best) or perplexity < current_best.objective["perplexity"] do
      Map.put(study, :best_trial, %{
        trial_id: trial_id,
        objective: objective,
        updated_at: DateTime.utc_now()
      })
    else
      study
    end
  end

  defp log_trial_to_mlflow(_study_id, trial_id, objective, _artifact) do
    # TODO: Implement MLflow logging
    Logger.info("[AutoMLDriver] Logging trial #{trial_id} to MLflow: #{inspect(objective)}")
  end
end
