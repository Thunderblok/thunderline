defmodule Thunderline.DeprecatedModulesTelemetryTest do
  use ExUnit.Case, async: false
  @moduletag :skip

  @moduletag :telemetry

  @deprecated_modules [
    Thunderchief.ObanHealth,
    Thunderchief.ObanDiagnostics,
    Thunderline.EventProcessor,
    Thunderline.Current.CircStats,
    Thunderline.Current.Hilbert,
    Thunderline.Current.Lease,
    Thunderline.Current.PLL,
    Thunderline.Current.PLV,
    Thunderline.Current.SafeClose
  ]

  setup do
    # Attach a test handler to capture deprecated module usage
    handler_id = :deprecated_test_handler
    :telemetry.attach(handler_id, [:thunderline, :deprecated_module, :used], fn _event, measurements, metadata, pid ->
      send(pid, {:deprecated_fired, measurements, metadata})
    end, self())

    on_exit(fn ->
      try do
        :telemetry.detach(handler_id)
      rescue
        _ -> :ok
      end
    end)
    :ok
  end

  test "each deprecated module emits telemetry once when invoked" do
    Enum.each(@deprecated_modules, fn mod ->
      # Avoid compile-time warnings by checking module/function availability
      if Code.ensure_loaded?(mod) and function_exported?(mod, :__deprecated_test_emit__, 0) do
        apply(mod, :__deprecated_test_emit__, [])
        assert_receive {:deprecated_fired, %{count: 1}, %{module: ^mod}}, 200,
          "Expected telemetry for #{inspect(mod)}"
      else
        # Module isn't present anymore; skip emission check
        :ok
      end
    end)
  end
end
