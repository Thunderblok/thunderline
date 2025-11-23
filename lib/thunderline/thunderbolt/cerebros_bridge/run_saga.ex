defmodule Thunderline.Thunderbolt.CerebrosBridge.RunSaga do
  @moduledoc """
  Reactor saga for executing Cerebros NAS runs with proper lifecycle management,
  error handling, and compensation.

  This saga handles:
  - Pre-run validation and setup
  - Python environment initialization
  - NAS run execution via PythonX
  - Result processing and storage
  - Cleanup and compensation on failures
  - Event publishing for observability

  ## Usage

      # Start a NAS run
      {:ok, result} = RunSaga.run(spec, opts)

      # Async via Oban
      {:ok, job} = RunSaga.enqueue(spec, opts)
  """

  use Reactor, extensions: [Reactor.Dsl]
  require Logger

  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, PythonxInvoker, SnexInvoker}
  alias Thunderline.Thunderflow.EventBus

  @doc """
  Execute the NAS run saga synchronously.
  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def run(spec, opts \\ []) do
    Reactor.run(__MODULE__, build_inputs(spec, opts), %{})
  end

  @doc """
  Enqueue the NAS run saga for async execution via Oban.
  """
  def enqueue(spec, opts \\ []) do
    Thunderline.Thunderbolt.CerebrosBridge.RunWorker.new(
      build_args(spec, opts),
      schedule_in: 0
    )
    |> Oban.insert()
  end

  # ============================================================================
  # Reactor DSL - Define the saga steps
  # ============================================================================

  input :spec
  input :run_id
  input :budget
  input :parameters
  input :meta

  # Step 1: Validate bridge is enabled
  step :check_enabled do
    run fn _input, _context ->
      if Client.enabled?() do
        {:ok, true}
      else
        {:error, :bridge_disabled}
      end
    end
  end

  # Step 2: Generate run ID if not provided
  step :ensure_run_id do
    argument :run_id, input(:run_id)

    run fn %{run_id: run_id}, _context ->
      final_id = run_id || "nas_#{:os.system_time(:second)}_#{:rand.uniform(9999)}"
      {:ok, final_id}
    end
  end

  # Step 3: Publish run.started event
  step :publish_start_event do
    argument :run_id, result(:ensure_run_id)
    argument :spec, input(:spec)

    run fn %{run_id: run_id, spec: spec}, _context ->
      event_attrs = %{
        name: "ml.run.started",
        source: :bolt,
        payload: %{
          run_id: run_id,
          dataset_id: spec[:dataset_id] || spec["dataset_id"],
          objective: spec[:objective] || spec["objective"]
        }
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, event} ->
          case EventBus.publish_event(event) do
            {:ok, published} ->
              {:ok, published}

            {:error, reason} ->
              Logger.warning("[RunSaga] Could not publish start event: #{inspect(reason)}")
              {:ok, :event_skipped}
          end

        {:error, reason} ->
          Logger.warning("[RunSaga] Could not build start event: #{inspect(reason)}")
          {:ok, :event_skipped}
      end
    end

    compensate fn _value, %{run_id: run_id}, _context ->
      Logger.warning("[RunSaga] Compensating: publishing run.cancelled for #{run_id}")

      event_attrs = %{
        name: "ml.run.cancelled",
        source: :bolt,
        payload: %{run_id: run_id, reason: "saga_compensation"}
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, event} ->
          case EventBus.publish_event(event) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning("[RunSaga] Could not publish cancel event: #{inspect(reason)}")
              :ok
          end

        {:error, reason} ->
          Logger.warning("[RunSaga] Could not build cancel event: #{inspect(reason)}")
          :ok
      end
    end
  end

  # Step 4: Execute the NAS run via PythonX
  step :execute_nas_run do
    argument :run_id, result(:ensure_run_id)
    argument :spec, input(:spec)
    argument :budget, input(:budget)
    argument :parameters, input(:parameters)

    run fn args, _context ->
      run_id = args.run_id
      spec = args.spec
      budget = args.budget || %{}
      parameters = args.parameters || %{}

      Logger.info("[RunSaga] Starting NAS run: #{run_id}")

      # Build the full Python args with atom keys
      python_args = %{
        spec: spec,
        opts: %{
          run_id: run_id,
          budget: budget,
          parameters: parameters
        }
      }

      # Call Python via configured invoker (Snex or Pythonx)
      invoker = get_invoker()
      Logger.info("[RunSaga] Using #{inspect(invoker)} for NAS run #{run_id}")

      case invoker.invoke(:start_run, python_args, timeout_ms: 30_000) do
        {:ok, result} ->
          Logger.info("[RunSaga] NAS run completed: #{run_id}")
          # Extract the parsed Python result from the wrapper
          parsed_result = Map.get(result, :parsed, result)
          {:ok, parsed_result}

        {:error, reason} = err ->
          Logger.error("[RunSaga] NAS run failed: #{run_id} - #{inspect(reason)}")
          err
      end
    end

    compensate fn _value, %{run_id: run_id}, _context ->
      Logger.warning("[RunSaga] Compensating: cleaning up run artifacts for #{run_id}")

      # Clean up any partial artifacts
      artifact_dir = "/tmp/cerebros/#{run_id}"

      if File.exists?(artifact_dir) do
        File.rm_rf(artifact_dir)
        Logger.info("[RunSaga] Removed artifact directory: #{artifact_dir}")
      end

      :ok
    end
  end

  # Step 5: Process and validate results
  step :process_results do
    argument :run_id, result(:ensure_run_id)
    argument :nas_result, result(:execute_nas_run)

    run fn %{run_id: run_id, nas_result: result}, _context ->
      Logger.debug("[RunSaga] Processing results for #{run_id}")

      # Validate result structure
      case validate_result(result) do
        :ok ->
          {:ok, result}

        {:error, reason} ->
          Logger.error("[RunSaga] Invalid result structure: #{inspect(reason)}")
          {:error, {:invalid_result, reason}}
      end
    end
  end

  # Step 6: Publish run.completed event
  step :publish_complete_event do
    argument :run_id, result(:ensure_run_id)
    argument :result, result(:process_results)

    run fn %{run_id: run_id, result: result}, _context ->
      event_attrs = %{
        name: "ml.run.completed",
        source: :bolt,
        payload: %{
          run_id: run_id,
          status: result["status"],
          trials_completed: result["completed_trials"],
          best_fitness: get_in(result, ["best_architecture", "fitness"])
        }
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, event} ->
          case EventBus.publish_event(event) do
            {:ok, published} ->
              {:ok, published}

            {:error, reason} ->
              Logger.warning("[RunSaga] Could not publish complete event: #{inspect(reason)}")
              {:ok, :event_skipped}
          end

        {:error, reason} ->
          Logger.warning("[RunSaga] Could not build complete event: #{inspect(reason)}")
          {:ok, :event_skipped}
      end
    end
  end

  # Step 7: Return final result
  return :process_results

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp build_inputs(spec, opts) do
    %{
      spec: spec,
      run_id: Keyword.get(opts, :run_id),
      budget: Keyword.get(opts, :budget, %{}),
      parameters: Keyword.get(opts, :parameters, %{}),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  defp build_args(spec, opts) do
    %{
      "spec" => spec,
      "run_id" => Keyword.get(opts, :run_id),
      "budget" => Keyword.get(opts, :budget, %{}),
      "parameters" => Keyword.get(opts, :parameters, %{}),
      "meta" => Keyword.get(opts, :meta, %{})
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp validate_result(result) when is_map(result) do
    required_keys = ["status", "completed_trials", "best_architecture"]

    missing = Enum.filter(required_keys, &(not Map.has_key?(result, &1)))

    case missing do
      [] -> :ok
      keys -> {:error, {:missing_keys, keys}}
    end
  end

  defp validate_result(_), do: {:error, :invalid_result_format}

  # Get the configured Python invoker module
  defp get_invoker do
    case Application.get_env(:thunderline, :cerebros_bridge, []) |> Keyword.get(:invoker, :pythonx) do
      :snex -> SnexInvoker
      :pythonx -> PythonxInvoker
      other -> raise "Unsupported invoker: #{inspect(other)}"
    end
  end
end
