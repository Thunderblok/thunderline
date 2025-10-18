defmodule Thunderline.Thunderbolt.Sagas.Base do
  @moduledoc """
  Base utilities and shared patterns for Reactor sagas in Thunderline.

  All sagas should emit telemetry events through this module and follow
  the canonical event taxonomy for saga orchestration.

  ## Telemetry Events

  Sagas emit the following events:
    * `[:reactor, :saga, :start]` - Saga execution begins
    * `[:reactor, :saga, :step, :start]` - Individual step starts
    * `[:reactor, :saga, :step, :stop]` - Individual step completes
    * `[:reactor, :saga, :step, :exception]` - Step fails
    * `[:reactor, :saga, :compensate]` - Compensation triggered
    * `[:reactor, :saga, :complete]` - Saga completes successfully
    * `[:reactor, :saga, :fail]` - Saga fails after compensation

  All events include metadata: `%{saga: module, correlation_id: uuid}`

  ## Compensation Patterns

  When a saga step fails, compensation steps run in reverse order.
  Each step should define a `compensate/3` callback that undoes its effects.

  ## Example

      defmodule MyApp.Sagas.UserProvisioning do
        use Reactor, extensions: [Reactor.Dsl]
        alias Thunderline.Thunderbolt.Sagas.Base

        input :user_params
        input :correlation_id

        around Base.telemetry_wrapper()

        step :create_user do
          argument :params, input(:user_params)
          run &MyApp.create_user/1
          compensate &MyApp.delete_user/1
        end

        step :provision_vault do
          argument :user_id, result(:create_user)
          run &MyApp.provision_vault/1
          compensate &MyApp.deprovision_vault/1
        end
      end
  """

  require Logger

  @telemetry_prefix [:reactor, :saga]

  @doc """
  Returns a Reactor around hook that wraps saga execution with telemetry.
  """
  def telemetry_wrapper do
    %{
      before: &before_saga/2,
      after_all: &after_saga/2
    }
  end

  @doc """
  Emits saga start telemetry and logs the beginning of orchestration.
  """
  def before_saga(reactor, context) do
    saga_name = reactor.id || inspect(reactor.__struct__)
    correlation_id = Map.get(context, :correlation_id, Thunderline.UUID.v7())

    metadata = %{
      saga: saga_name,
      correlation_id: correlation_id,
      inputs: Map.keys(context)
    }

    :telemetry.execute(@telemetry_prefix ++ [:start], %{count: 1}, metadata)

    Logger.info("Saga started: #{saga_name} [#{correlation_id}]")

    {:ok, Map.put(context, :_saga_start_time, System.monotonic_time())}
  end

  @doc """
  Emits saga completion telemetry and logs the final state.
  """
  def after_saga(reactor, {status, context}) do
    saga_name = reactor.id || inspect(reactor.__struct__)
    correlation_id = Map.get(context, :correlation_id, "unknown")
    start_time = Map.get(context, :_saga_start_time, System.monotonic_time())
    duration = System.monotonic_time() - start_time

    event = if status == :ok, do: :complete, else: :fail
    metadata = %{saga: saga_name, correlation_id: correlation_id, status: status}

    :telemetry.execute(@telemetry_prefix ++ [event], %{duration: duration}, metadata)

    log_level = if status == :ok, do: :info, else: :warning
    Logger.log(log_level, "Saga #{event}: #{saga_name} [#{correlation_id}]")

    maybe_emit_event(event, saga_name, correlation_id, status)

    {:ok, {status, context}}
  end

  @doc """
  Wraps a saga step to emit telemetry on start/stop/exception.
  Use this to instrument custom step functions.
  """
  def instrument_step(step_name, fun) when is_function(fun, 1) do
    fn arg ->
      start = System.monotonic_time()
      metadata = %{step: step_name}

      :telemetry.execute(@telemetry_prefix ++ [:step, :start], %{count: 1}, metadata)

      try do
        result = fun.(arg)
        duration = System.monotonic_time() - start

        :telemetry.execute(@telemetry_prefix ++ [:step, :stop], %{duration: duration}, metadata)

        result
      rescue
        error ->
          duration = System.monotonic_time() - start

          :telemetry.execute(@telemetry_prefix ++ [:step, :exception], %{duration: duration},
            error: error,
            stacktrace: __STACKTRACE__
          )

          reraise error, __STACKTRACE__
      end
    end
  end

  @doc """
  Standard compensation wrapper that logs and emits telemetry.
  """
  def compensate_step(step_name, fun) when is_function(fun, 1) do
    fn arg ->
      metadata = %{step: step_name}
      :telemetry.execute(@telemetry_prefix ++ [:compensate], %{count: 1}, metadata)

      Logger.warning("Compensating step: #{step_name}")

      result = fun.(arg)

      Logger.info("Compensation complete: #{step_name}")

      result
    end
  end

  # Emit canonical event to ThunderFlow EventBus for saga lifecycle
  defp maybe_emit_event(event, saga_name, correlation_id, status) do
    if feature?(:reactor_events) do
      event_name = "reactor.saga.#{event}"

      event_attrs = %{
        name: event_name,
        type: :saga_lifecycle,
        domain: :bolt,
        source: saga_name,
        correlation_id: correlation_id,
        payload: %{
          saga: saga_name,
          status: status,
          event: event
        },
        meta: %{
          pipeline: :realtime
        }
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, ev} -> Thunderline.Thunderflow.EventBus.publish_event(ev)
        {:error, _reason} -> :ok
      end
    end
  end

  defp feature?(flag), do: flag in Application.get_env(:thunderline, :features, [])
end
