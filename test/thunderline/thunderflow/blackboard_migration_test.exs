defmodule Thunderline.Thunderflow.BlackboardMigrationTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderflow.Blackboard

  @moduletag :blackboard

  test "facade delegates and emits telemetry" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:thunderline, :blackboard, :legacy_use]])
    try do
      assert :ok == Blackboard.put({:automata, :test_key}, 42)
      assert 42 == Blackboard.get({:automata, :test_key})

      assert_receive {:telemetry_event, [:thunderline, :blackboard, :legacy_use], %{count: 1}, %{fun: :put}}, 500
    after
      :telemetry.detach(ref)
    end
  end

  test "tripwire passes (no direct legacy usage beyond allowed)" do
    assert :ok == Thunderline.Thunderflow.BlackboardTripwire.assert_migrated!()
  end
end
