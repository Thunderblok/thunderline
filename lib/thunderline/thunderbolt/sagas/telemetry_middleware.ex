defmodule Thunderline.Thunderbolt.Sagas.TelemetryMiddleware do
  @moduledoc """
  Reactor middleware for Thunderline saga telemetry integration.

  Provides comprehensive telemetry events for saga execution including:
  - Saga lifecycle (start, complete, error, halt)
  - Step execution (before, after, error)
  - Compensation tracking
  - Performance metrics

  ## Telemetry Events

  All events are prefixed with `[:thunderline, :saga]`:

  - `[:thunderline, :saga, :start]` - Saga execution started
  - `[:thunderline, :saga, :complete]` - Saga completed successfully
  - `[:thunderline, :saga, :error]` - Saga failed with error
  - `[:thunderline, :saga, :halt]` - Saga was halted
  - `[:thunderline, :saga, :step, :start]` - Step execution started
  - `[:thunderline, :saga, :step, :complete]` - Step completed
  - `[:thunderline, :saga, :step, :error]` - Step failed
  - `[:thunderline, :saga, :compensate, :start]` - Compensation started
  - `[:thunderline, :saga, :compensate, :complete]` - Compensation completed

  ## Usage

  Add to your Reactor saga:

      defmodule MySaga do
        use Reactor, extensions: [Reactor.Dsl]

        middlewares do
          middleware Thunderline.Thunderbolt.Sagas.TelemetryMiddleware
        end

        # ... steps
      end

  ## Context Integration

  The middleware expects these context keys (optional):
  - `:correlation_id` - Unique saga execution ID
  - `:causation_id` - ID of triggering event
  - `:deadline` - DateTime deadline for timeout tracking

  These are automatically populated by `SagaWorker`.
  """

  use Reactor.Middleware

  require Logger

  @telemetry_prefix [:thunderline, :saga]

  @impl true
  def init(context) do
    correlation_id = Map.get(context, :correlation_id, Thunderline.UUID.v7())

    context =
      context
      |> Map.put_new(:correlation_id, correlation_id)
      |> Map.put(:saga_start_time, System.monotonic_time())
      |> Map.put(:step_timings, %{})

    {:ok, context}
  end

  @impl true
  def complete(result, context) do
    duration_ns = System.monotonic_time() - context.saga_start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:complete],
      %{
        duration: duration_ns,
        duration_ms: System.convert_time_unit(duration_ns, :native, :millisecond),
        system_time: System.system_time()
      },
      %{
        correlation_id: context.correlation_id,
        causation_id: Map.get(context, :causation_id),
        status: :success
      }
    )

    # Emit event to ThunderFlow
    emit_completion_event(context, result)

    {:ok, result}
  end

  @impl true
  def error(errors, context) do
    duration_ns = System.monotonic_time() - context.saga_start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:error],
      %{
        duration: duration_ns,
        duration_ms: System.convert_time_unit(duration_ns, :native, :millisecond),
        system_time: System.system_time(),
        error_count: length(List.wrap(errors))
      },
      %{
        correlation_id: context.correlation_id,
        causation_id: Map.get(context, :causation_id),
        errors: summarize_errors(errors)
      }
    )

    # Emit failure event to ThunderFlow
    emit_failure_event(context, errors)

    :ok
  end

  @impl true
  def halt(context) do
    duration_ns = System.monotonic_time() - context.saga_start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:halt],
      %{
        duration: duration_ns,
        duration_ms: System.convert_time_unit(duration_ns, :native, :millisecond),
        system_time: System.system_time()
      },
      %{
        correlation_id: context.correlation_id,
        causation_id: Map.get(context, :causation_id)
      }
    )

    :ok
  end

  @impl true
  def event({:run_start, arguments}, step, context) do
    step_name = step_name(step)
    step_start_time = System.monotonic_time()

    # Store step start time
    step_timings = Map.put(context.step_timings, step_name, step_start_time)
    context = Map.put(context, :step_timings, step_timings)

    :telemetry.execute(
      @telemetry_prefix ++ [:step, :start],
      %{
        system_time: System.system_time(),
        argument_count: map_size(arguments)
      },
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step)
      }
    )

    {:ok, context}
  end

  def event({:run_complete, result}, step, context) do
    step_name = step_name(step)
    step_start_time = Map.get(context.step_timings, step_name, System.monotonic_time())
    duration_ns = System.monotonic_time() - step_start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:step, :complete],
      %{
        duration: duration_ns,
        duration_ms: System.convert_time_unit(duration_ns, :native, :millisecond),
        system_time: System.system_time()
      },
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step),
        result_type: result_type(result)
      }
    )

    {:ok, context}
  end

  def event({:run_error, errors}, step, context) do
    step_name = step_name(step)
    step_start_time = Map.get(context.step_timings, step_name, System.monotonic_time())
    duration_ns = System.monotonic_time() - step_start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:step, :error],
      %{
        duration: duration_ns,
        duration_ms: System.convert_time_unit(duration_ns, :native, :millisecond),
        system_time: System.system_time(),
        error_count: length(List.wrap(errors))
      },
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step),
        errors: summarize_errors(errors)
      }
    )

    {:ok, context}
  end

  def event({:compensate_start, _reason}, step, context) do
    step_name = step_name(step)

    :telemetry.execute(
      @telemetry_prefix ++ [:compensate, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step)
      }
    )

    {:ok, context}
  end

  def event({:compensate_complete, result}, step, context) do
    step_name = step_name(step)

    :telemetry.execute(
      @telemetry_prefix ++ [:compensate, :complete],
      %{system_time: System.system_time()},
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step),
        compensation_result: result_type(result)
      }
    )

    {:ok, context}
  end

  def event({:undo_start, _value}, step, context) do
    step_name = step_name(step)

    :telemetry.execute(
      @telemetry_prefix ++ [:undo, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step)
      }
    )

    {:ok, context}
  end

  def event({:undo_complete, result}, step, context) do
    step_name = step_name(step)

    :telemetry.execute(
      @telemetry_prefix ++ [:undo, :complete],
      %{system_time: System.system_time()},
      %{
        correlation_id: context.correlation_id,
        step_name: step_name,
        step_module: step_module(step),
        undo_result: result_type(result)
      }
    )

    {:ok, context}
  end

  def event(_event, _step, context) do
    {:ok, context}
  end

  # Private helpers

  defp step_name(%{name: name}), do: name
  defp step_name(_), do: :unknown

  defp step_module(%{impl: impl}), do: impl
  defp step_module(_), do: nil

  defp result_type({:ok, _}), do: :ok
  defp result_type(:ok), do: :ok
  defp result_type({:error, _}), do: :error
  defp result_type(:retry), do: :retry
  defp result_type({:halt, _}), do: :halt
  defp result_type(_), do: :unknown

  defp summarize_errors(errors) when is_list(errors) do
    errors
    |> Enum.take(5)
    |> Enum.map(&inspect/1)
  end

  defp summarize_errors(error), do: [inspect(error)]

  defp emit_completion_event(context, _result) do
    event_attrs = %{
      name: "saga.completed",
      type: :saga_lifecycle,
      domain: :bolt,
      source: "TelemetryMiddleware",
      correlation_id: context.correlation_id,
      causation_id: Map.get(context, :causation_id),
      payload: %{
        status: :completed,
        duration_ms:
          System.convert_time_unit(
            System.monotonic_time() - context.saga_start_time,
            :native,
            :millisecond
          )
      },
      meta: %{pipeline: :realtime}
    }

    with {:ok, event} <- Thunderline.Event.new(event_attrs) do
      Thunderline.Thunderflow.EventBus.publish_event(event)
    end
  end

  defp emit_failure_event(context, errors) do
    event_attrs = %{
      name: "saga.failed",
      type: :saga_lifecycle,
      domain: :bolt,
      source: "TelemetryMiddleware",
      correlation_id: context.correlation_id,
      causation_id: Map.get(context, :causation_id),
      payload: %{
        status: :failed,
        errors: summarize_errors(errors),
        duration_ms:
          System.convert_time_unit(
            System.monotonic_time() - context.saga_start_time,
            :native,
            :millisecond
          )
      },
      meta: %{pipeline: :realtime}
    }

    with {:ok, event} <- Thunderline.Event.new(event_attrs) do
      Thunderline.Thunderflow.EventBus.publish_event(event)
    end
  end
end
