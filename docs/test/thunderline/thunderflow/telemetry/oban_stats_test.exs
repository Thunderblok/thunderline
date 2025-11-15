defmodule Thunderline.Thunderflow.Telemetry.ObanStatsTest do
  use ExUnit.Case, async: false

  @moduletag :telemetry
  alias Thunderline.Thunderflow.Telemetry.Oban, as: ObanTelemetry

  setup do
    ObanTelemetry.attach()
    :ok
  end

  test "stats returns structure before events (may be empty or contain startup noise)" do
    stats = ObanTelemetry.stats()
    assert is_map(stats.by_type)
    assert stats.total >= 0
  end

  test "recent reflects inserted telemetry events" do
    # Simulate minimal meta for handler
    meta = %{queue: :default, worker: "TestWorker", state: :available}
    ObanTelemetry.handle_job_event([:oban, :job, :start], %{}, meta, %{})
    Process.sleep(5)
    events = ObanTelemetry.recent(5)
    assert length(events) == 1
    [evt] = events
    assert evt.type == :start
    stats = ObanTelemetry.stats()
    assert stats.total >= 1
  end
end
