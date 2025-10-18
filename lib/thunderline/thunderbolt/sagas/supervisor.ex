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
  """
  def run_saga(saga_module, inputs) do
    correlation_id = Map.get(inputs, :correlation_id, Thunderline.UUID.v7())

    task_spec =
      Task.Supervisor.child_spec(
        fn ->
          Logger.info("Starting saga: #{inspect(saga_module)} [#{correlation_id}]")

          result = Reactor.run(saga_module, inputs)

          Logger.info("Saga completed: #{inspect(saga_module)} [#{correlation_id}]")

          # Emit telemetry for saga completion
          emit_saga_telemetry(saga_module, result, correlation_id)

          result
        end,
        restart: :temporary
      )

    case DynamicSupervisor.start_child(__MODULE__, task_spec) do
      {:ok, pid} ->
        register_saga(correlation_id, saga_module, pid)
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start saga: #{inspect(reason)}")
        {:error, reason}
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
