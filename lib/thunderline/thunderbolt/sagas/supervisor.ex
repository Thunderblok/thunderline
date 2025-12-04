defmodule Thunderline.Thunderbolt.Sagas.Supervisor do
  @moduledoc """
  Dynamic supervisor for Reactor sagas in Thunderline.

  This supervisor manages the lifecycle of saga executions, providing:
  - Dynamic saga instantiation
  - Fault tolerance with supervision strategies
  - Saga registry for tracking active executions
  - Telemetry for saga monitoring

  ## Usage

      # Start a saga dynamically
      Thunderline.Thunderbolt.Sagas.Supervisor.run_saga(
        UserProvisioningSaga,
        %{email: "user@example.com", correlation_id: correlation_id}
      )

      # List active sagas
      Thunderline.Thunderbolt.Sagas.Supervisor.list_active_sagas()
  """

  use DynamicSupervisor
  require Logger
  require Thunderline.Thunderflow.Telemetry.OtelTrace

  @registry Thunderline.Thunderbolt.Sagas.Registry

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Reactor Saga Supervisor...")
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 5, max_seconds: 60)
  end

  @doc """
  Runs a saga asynchronously under supervision.

  Returns `{:ok, pid}` where pid is the Task process running the saga.

  Instrumented with OpenTelemetry for T-72h telemetry heartbeat.
  """
  def run_saga(saga_module, inputs) do
    alias Thunderline.Thunderflow.Telemetry.OtelTrace

    OtelTrace.with_span "bolt.run_saga", %{
      saga_module: inspect(saga_module),
      correlation_id: Map.get(inputs, :correlation_id)
    } do
      Process.put(:current_domain, :bolt)

      OtelTrace.set_attributes(%{
        "thunderline.domain" => "bolt",
        "thunderline.component" => "sagas_supervisor",
        "saga.module" => inspect(saga_module)
      })

      # Continue trace from event if trace context present in inputs
      if Map.has_key?(inputs, :meta) do
        OtelTrace.continue_trace_from_event(inputs)
      end

      correlation_id = Map.get(inputs, :correlation_id, Thunderline.UUID.v7())

      OtelTrace.set_attributes(%{"saga.correlation_id" => correlation_id})

      # Create a Task spec for the saga execution
      task_fun = fn ->
        # Inherit trace context in saga task
        OtelTrace.with_span "bolt.saga_execution", %{
          saga_module: inspect(saga_module),
          correlation_id: correlation_id
        } do
          Logger.info("Starting saga: #{inspect(saga_module)} [#{correlation_id}]")
          OtelTrace.add_event("bolt.saga_started")

          result = Reactor.run(saga_module, inputs)

          Logger.info("Saga completed: #{inspect(saga_module)} [#{correlation_id}]")
          OtelTrace.add_event("bolt.saga_completed", %{result: inspect(result)})

          # Emit telemetry for saga completion
          emit_saga_telemetry(saga_module, result, correlation_id)

          result
        end
      end

      task_spec = %{
        id: Task,
        start: {Task, :start_link, [task_fun]},
        restart: :temporary
      }

      result =
        case DynamicSupervisor.start_child(__MODULE__, task_spec) do
          {:ok, pid} ->
            register_saga(correlation_id, saga_module, pid)
            OtelTrace.add_event("bolt.saga_registered", %{pid: inspect(pid)})
            {:ok, pid}

          {:error, reason} ->
            Logger.error("Failed to start saga: #{inspect(reason)}")
            OtelTrace.set_status(:error, "Failed to start saga: #{inspect(reason)}")
            {:error, reason}
        end

      result
    end
  end

  @doc """
  Lists all currently active sagas tracked in the registry.
  """
  def list_active_sagas do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  @doc """
  Stops a saga by correlation ID.
  """
  def stop_saga(correlation_id) do
    case Registry.lookup(@registry, correlation_id) do
      [{pid, _saga_module}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  # Private helpers

  defp register_saga(correlation_id, saga_module, pid) do
    Registry.register(@registry, correlation_id, saga_module)

    Logger.debug(
      "Registered saga: #{correlation_id} -> #{inspect(saga_module)} (#{inspect(pid)})"
    )
  end

  defp emit_saga_telemetry(saga_module, result, correlation_id) do
    status = if match?({:ok, _}, result), do: :success, else: :failure

    :telemetry.execute(
      [:thunderline, :saga, :complete],
      %{count: 1},
      %{
        saga: saga_module,
        correlation_id: correlation_id,
        status: status
      }
    )
  end
end
