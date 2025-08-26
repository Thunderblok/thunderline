defmodule Thunderline.DeprecatedModulesTelemetryTest do
  use ExUnit.Case, async: false

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
      # Invoke one public function to trigger emit/0. Use best-effort per module.
      invoke_once(mod)
      assert_receive {:deprecated_fired, %{count: 1}, %{module: ^mod}}, 200,
        "Expected telemetry for #{inspect(mod)}"
    end)
  end

  # Use the explicit test emit helpers to avoid side effects and supervision dependencies.
  defp invoke_once(Thunderchief.ObanHealth), do: Thunderchief.ObanHealth.__deprecated_test_emit__()
  defp invoke_once(Thunderchief.ObanDiagnostics), do: Thunderchief.ObanDiagnostics.__deprecated_test_emit__()
  defp invoke_once(Thunderline.EventProcessor), do: Thunderline.EventProcessor.__deprecated_test_emit__()
  defp invoke_once(Thunderline.Current.CircStats), do: Thunderline.Current.CircStats.__deprecated_test_emit__()
  defp invoke_once(Thunderline.Current.Hilbert), do: Thunderline.Current.Hilbert.__deprecated_test_emit__()
  defp invoke_once(Thunderline.Current.Lease), do: Thunderline.Current.Lease.__deprecated_test_emit__()
  defp invoke_once(Thunderline.Current.PLL), do: Thunderline.Current.PLL.__deprecated_test_emit__()
  defp invoke_once(Thunderline.Current.PLV), do: Thunderline.Current.PLV.__deprecated_test_emit__()
  defp invoke_once(Thunderline.Current.SafeClose), do: Thunderline.Current.SafeClose.__deprecated_test_emit__()

  defp safe_call(fun) do
    try do
      fun.()
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end
end
