defmodule Thunderline.Thunderbolt.Training.TPEClient do
  @moduledoc """
  Elixir client for Python TPE (Tree-structured Parzen Estimator) optimization.

  Communicates with `python/cerebros/service/tpe_bridge.py` via subprocess + JSON
  to perform Bayesian hyperparameter optimization using Optuna's TPESampler.

  ## Architecture

  ```
  TPEClient (GenServer)
        │
        ▼
  Python Port ◀─JSON─▶ tpe_bridge.py
        │
        ▼
    Optuna TPESampler
  ```

  ## Usage

      # Start the client
      {:ok, pid} = TPEClient.start_link([])

      # Initialize a study
      {:ok, study} = TPEClient.init_study("bit_scoring",
        search_space: [
          %{name: "learning_rate", type: "float", low: 1.0e-4, high: 1.0e-2, log: true},
          %{name: "hidden_dim", type: "int", low: 32, high: 256},
          %{name: "activation", type: "categorical", choices: ["relu", "gelu", "silu"]}
        ],
        direction: "maximize",
        seed: 42
      )

      # Suggest next parameters
      {:ok, suggestion} = TPEClient.suggest("bit_scoring")
      # => %{params: %{"learning_rate" => 0.001, ...}, trial_id: 0}

      # Run evaluation, then record result
      score = evaluate_model(suggestion.params)
      {:ok, result} = TPEClient.record("bit_scoring", suggestion.params, score, suggestion.trial_id)

      # Get best parameters found
      {:ok, best} = TPEClient.best_params("bit_scoring")

  ## Integration with Training Pipeline

  The TPEClient is used by the TrainingOrchestrator to:
  1. Optimize BitChief scoring model hyperparameters
  2. Tune Cerebros evaluation thresholds
  3. Find optimal CA (Cellular Automata) criticality parameters

  ## Event Integration

  Publishes telemetry events:
  - `[:thunderline, :training, :tpe, :suggest]`
  - `[:thunderline, :training, :tpe, :record]`
  - `[:thunderline, :training, :tpe, :best]`
  """

  use GenServer
  require Logger

  @python_path "python3.13"
  @script_path "python/cerebros/service/tpe_cli.py"
  @default_timeout 30_000

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts the TPEClient GenServer.

  ## Options

  - `:python_path` - Path to Python executable (default: "python3.13")
  - `:script_path` - Path to tpe_cli.py script (default: "python/cerebros/service/tpe_cli.py")
  - `:name` - GenServer name (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initializes a new TPE optimization study.

  ## Parameters

  - `study_name` - Unique name for this study
  - `opts` - Keyword options:
    - `:search_space` - List of parameter specifications (required)
    - `:direction` - "maximize" or "minimize" (default: "maximize")
    - `:seed` - Random seed for reproducibility
    - `:sampler` - Sampler type (default: "TPESampler")
    - `:sampler_kwargs` - Additional sampler options

  ## Search Space Format

      [
        %{name: "param1", type: "float", low: 0.0, high: 1.0},
        %{name: "param2", type: "int", low: 10, high: 100, step: 10},
        %{name: "param3", type: "categorical", choices: ["a", "b", "c"]},
        %{name: "param4", type: "float", low: 1e-4, high: 1e-1, log: true}
      ]

  ## Returns

      {:ok, %{study_name: "...", n_params: 4, direction: "maximize"}}
  """
  @spec init_study(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def init_study(study_name, opts \\ []) do
    call(:init_study, [study_name, opts])
  end

  @doc """
  Suggests the next set of parameters to evaluate.

  Uses TPE to intelligently suggest parameters that are likely to
  improve the objective based on past trials.

  ## Returns

      {:ok, %{params: %{"learning_rate" => 0.001, ...}, trial_id: 5}}
  """
  @spec suggest(String.t()) :: {:ok, map()} | {:error, term()}
  def suggest(study_name) do
    call(:suggest, [study_name])
  end

  @doc """
  Suggests multiple parameter sets for parallel evaluation.

  ## Returns

      {:ok, %{trials: [%{params: ..., trial_id: 5}, %{params: ..., trial_id: 6}]}}
  """
  @spec suggest_batch(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def suggest_batch(study_name, n) do
    call(:suggest_batch, [study_name, n])
  end

  @doc """
  Records the result of evaluating a parameter set.

  ## Parameters

  - `study_name` - Name of the study
  - `params` - The parameter values that were evaluated
  - `value` - The objective value (higher is better if maximizing)
  - `trial_id` - The trial ID from suggest/1 (optional)
  - `opts` - Additional options:
    - `:state` - "complete", "pruned", or "fail"

  ## Returns

      {:ok, %{trial_id: 5, is_best: true, n_complete: 10}}
  """
  @spec record(String.t(), map(), float(), integer() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def record(study_name, params, value, trial_id \\ nil, opts \\ []) do
    call(:record, [study_name, params, value, trial_id, opts])
  end

  @doc """
  Gets the best parameters found so far.

  ## Returns

      {:ok, %{params: %{"learning_rate" => 0.001, ...}, value: 0.95, trial_id: 7}}
  """
  @spec best_params(String.t()) :: {:ok, map()} | {:error, term()}
  def best_params(study_name) do
    call(:best_params, [study_name])
  end

  @doc """
  Gets current study status.

  ## Returns

      {:ok, %{study_name: "...", n_trials: 20, n_complete: 18, best_value: 0.95, ...}}
  """
  @spec get_status(String.t()) :: {:ok, map()} | {:error, term()}
  def get_status(study_name) do
    call(:get_status, [study_name])
  end

  @doc """
  Deletes a study from memory.
  """
  @spec delete_study(String.t()) :: {:ok, map()} | {:error, term()}
  def delete_study(study_name) do
    call(:delete_study, [study_name])
  end

  @doc """
  Lists all active studies.
  """
  @spec list_studies() :: {:ok, map()} | {:error, term()}
  def list_studies do
    call(:list_studies, [])
  end

  @doc """
  Checks if the TPE bridge is available (Python + Optuna installed).
  """
  @spec available?() :: boolean()
  def available? do
    case call(:ping, []) do
      {:ok, %{"status" => "ok"}} -> true
      _ -> false
    end
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    python_path = opts[:python_path] || @python_path
    script_path = opts[:script_path] || @script_path

    state = %{
      python_path: python_path,
      script_path: script_path,
      studies: MapSet.new()
    }

    Logger.info("[TPEClient] Started with python=#{python_path}")
    {:ok, state}
  end

  @impl true
  def handle_call({:call, function, args}, _from, state) do
    result = call_python(state, function, args)

    # Track studies
    state =
      case {function, result} do
        {:init_study, {:ok, %{"study_name" => name}}} ->
          %{state | studies: MapSet.put(state.studies, name)}

        {:delete_study, {:ok, _}} ->
          study_name = List.first(args)
          %{state | studies: MapSet.delete(state.studies, study_name)}

        _ ->
          state
      end

    # Emit telemetry
    emit_telemetry(function, args, result)

    {:reply, result, state}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp call(function, args, server \\ __MODULE__) do
    GenServer.call(server, {:call, function, args}, @default_timeout)
  end

  defp call_python(state, function, args) do
    request =
      Jason.encode!(%{
        function: to_string(function),
        args: format_args(function, args)
      })

    Logger.debug("[TPEClient] Request: #{function} #{inspect(args)}")

    python_cmd = System.find_executable(state.python_path)

    if is_nil(python_cmd) do
      {:error, {:python_not_found, state.python_path}}
    else
      port =
        Port.open({:spawn_executable, python_cmd}, [
          :binary,
          :exit_status,
          {:args, [state.script_path]},
          {:cd, File.cwd!()},
          :stderr_to_stdout
        ])

      Port.command(port, request <> "\n")
      receive_output(port, "", nil)
    end
  rescue
    e ->
      Logger.error("[TPEClient] Error calling Python: #{inspect(e)}")
      {:error, {:python_error, e}}
  end

  defp format_args(:init_study, [study_name, opts]) do
    %{
      study_name: study_name,
      search_space: opts[:search_space] || [],
      direction: opts[:direction] || "maximize",
      seed: opts[:seed],
      sampler: opts[:sampler] || "TPESampler",
      sampler_kwargs: opts[:sampler_kwargs]
    }
  end

  defp format_args(:suggest, [study_name]) do
    %{study_name: study_name}
  end

  defp format_args(:suggest_batch, [study_name, n]) do
    %{study_name: study_name, n: n}
  end

  defp format_args(:record, [study_name, params, value, trial_id, opts]) do
    %{
      study_name: study_name,
      params: params,
      value: value,
      trial_id: trial_id,
      state: opts[:state] || "complete"
    }
  end

  defp format_args(:best_params, [study_name]) do
    %{study_name: study_name}
  end

  defp format_args(:get_status, [study_name]) do
    %{study_name: study_name}
  end

  defp format_args(:delete_study, [study_name]) do
    %{study_name: study_name}
  end

  defp format_args(:list_studies, []) do
    %{}
  end

  defp format_args(:ping, []) do
    %{}
  end

  defp format_args(_, args) do
    args
  end

  defp receive_output(port, output, exit_code) do
    receive do
      {^port, {:data, data}} ->
        receive_output(port, output <> data, exit_code)

      {^port, {:exit_status, code}} ->
        if output != "" do
          process_result(output, code)
        else
          receive_output(port, output, code)
        end
    after
      @default_timeout ->
        if exit_code != nil do
          process_result(output, exit_code)
        else
          Port.close(port)
          {:error, {:timeout, output}}
        end
    end
  end

  defp process_result(output, exit_code) do
    case exit_code do
      0 ->
        # Extract JSON from output (last line starting with '{')
        json_line =
          output
          |> String.split("\n")
          |> Enum.reverse()
          |> Enum.find("", fn line ->
            String.starts_with?(String.trim(line), "{")
          end)

        if json_line == "" do
          {:error, {:no_json_found, output}}
        else
          case Jason.decode(json_line) do
            {:ok, %{"status" => "error", "reason" => reason}} ->
              {:error, reason}

            {:ok, %{"status" => "ok"} = result} ->
              {:ok, result}

            {:ok, result} ->
              {:ok, result}

            {:error, reason} ->
              {:error, {:json_decode_failed, reason, output}}
          end
        end

      code ->
        Logger.error("[TPEClient] Python failed (exit #{code}): #{output}")
        {:error, {:python_failed, code, output}}
    end
  end

  defp emit_telemetry(function, args, result) do
    status =
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end

    :telemetry.execute(
      [:thunderline, :training, :tpe, function],
      %{count: 1},
      %{
        function: function,
        args: args,
        status: status
      }
    )
  end
end
