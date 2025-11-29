defmodule Thunderline.Thunderbolt.Sagas.TelemetryMiddlewareTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Sagas.TelemetryMiddleware

  describe "init/1" do
    test "initializes context with correlation_id and timing data" do
      context = %{}

      assert {:ok, result} = TelemetryMiddleware.init(context)
      assert Map.has_key?(result, :correlation_id)
      assert Map.has_key?(result, :saga_start_time)
      assert Map.has_key?(result, :step_timings)
      assert result.step_timings == %{}
    end

    test "preserves existing correlation_id" do
      existing_id = "existing-corr-id"
      context = %{correlation_id: existing_id}

      assert {:ok, result} = TelemetryMiddleware.init(context)
      assert result.correlation_id == existing_id
    end
  end

  describe "complete/2" do
    test "emits telemetry event on completion" do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :complete]]
        )

      context = %{
        correlation_id: "test-corr-id",
        saga_start_time: System.monotonic_time(),
        step_timings: %{}
      }

      result = {:ok, %{some: :data}}

      assert {:ok, ^result} = TelemetryMiddleware.complete(result, context)

      assert_receive {[:thunderline, :saga, :complete], ^ref, measurements, metadata}
      assert is_integer(measurements.duration)
      assert is_integer(measurements.duration_ms)
      assert metadata.correlation_id == "test-corr-id"
      assert metadata.status == :success
    end
  end

  describe "error/2" do
    test "emits telemetry event on error" do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :error]]
        )

      context = %{
        correlation_id: "test-corr-id",
        saga_start_time: System.monotonic_time(),
        step_timings: %{}
      }

      errors = [{:error, :some_reason}]

      assert :ok = TelemetryMiddleware.error(errors, context)

      assert_receive {[:thunderline, :saga, :error], ^ref, measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.error_count == 1
      assert metadata.correlation_id == "test-corr-id"
    end
  end

  describe "halt/1" do
    test "emits telemetry event on halt" do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :halt]]
        )

      context = %{
        correlation_id: "test-corr-id",
        saga_start_time: System.monotonic_time(),
        step_timings: %{}
      }

      assert :ok = TelemetryMiddleware.halt(context)

      assert_receive {[:thunderline, :saga, :halt], ^ref, measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.correlation_id == "test-corr-id"
    end
  end

  describe "event/3 - step events" do
    setup do
      context = %{
        correlation_id: "test-corr-id",
        saga_start_time: System.monotonic_time(),
        step_timings: %{}
      }

      step = %{name: :test_step, impl: TestModule}

      {:ok, context: context, step: step}
    end

    test "tracks step start time", %{context: context, step: step} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :step, :start]]
        )

      arguments = %{arg1: "value1"}

      assert {:ok, updated_context} =
               TelemetryMiddleware.event({:run_start, arguments}, step, context)

      assert Map.has_key?(updated_context.step_timings, :test_step)

      assert_receive {[:thunderline, :saga, :step, :start], ^ref, _measurements, metadata}
      assert metadata.step_name == :test_step
      assert metadata.correlation_id == "test-corr-id"
    end

    test "emits step complete with duration", %{context: context, step: step} do
      # First simulate step start
      {:ok, context} = TelemetryMiddleware.event({:run_start, %{}}, step, context)

      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :step, :complete]]
        )

      result = {:ok, :step_result}

      assert {:ok, _updated_context} =
               TelemetryMiddleware.event({:run_complete, result}, step, context)

      assert_receive {[:thunderline, :saga, :step, :complete], ^ref, measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.step_name == :test_step
      assert metadata.result_type == :ok
    end

    test "emits step error event", %{context: context, step: step} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :step, :error]]
        )

      errors = [{:error, :some_reason}]

      assert {:ok, _updated_context} =
               TelemetryMiddleware.event({:run_error, errors}, step, context)

      assert_receive {[:thunderline, :saga, :step, :error], ^ref, measurements, metadata}
      assert measurements.error_count == 1
      assert metadata.step_name == :test_step
    end
  end

  describe "event/3 - compensation events" do
    setup do
      context = %{
        correlation_id: "test-corr-id",
        saga_start_time: System.monotonic_time(),
        step_timings: %{}
      }

      step = %{name: :compensate_step, impl: TestModule}

      {:ok, context: context, step: step}
    end

    test "emits compensate start event", %{context: context, step: step} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :compensate, :start]]
        )

      assert {:ok, _context} =
               TelemetryMiddleware.event({:compensate_start, :some_reason}, step, context)

      assert_receive {[:thunderline, :saga, :compensate, :start], ^ref, _measurements, metadata}
      assert metadata.step_name == :compensate_step
    end

    test "emits compensate complete event", %{context: context, step: step} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:thunderline, :saga, :compensate, :complete]]
        )

      result = {:ok, :compensated}

      assert {:ok, _context} =
               TelemetryMiddleware.event({:compensate_complete, result}, step, context)

      assert_receive {[:thunderline, :saga, :compensate, :complete], ^ref, _measurements, metadata}
      assert metadata.step_name == :compensate_step
      assert metadata.compensation_result == :ok
    end
  end
end
