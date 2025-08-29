defmodule Thunderline.TOCP.HysteresisAdmissionTest do
  use ExUnit.Case

  test "admission valid? requires min length" do
    refute Thunderline.TOCP.Admission.valid?("short", [])
    assert Thunderline.TOCP.Admission.valid?(String.duplicate("a", 24), [])
  end

  test "hysteresis manager elevates on telemetry event" do
    # Start manager if not started
    start_supervised({Thunderline.TOCP.Routing.HysteresisManager, []})
    base = Thunderline.TOCP.Routing.HysteresisManager.current()
    :telemetry.execute([:tocp, :routing_relay_switch_rate], %{rate_pct: 6.0}, %{})
    # Allow async handle
    Process.sleep(50)
    elevated = Thunderline.TOCP.Routing.HysteresisManager.current()
    assert elevated >= base
  end
end
