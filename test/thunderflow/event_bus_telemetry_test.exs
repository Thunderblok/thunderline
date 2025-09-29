defmodule Thunderflow.EventBusTelemetryTest do
  use ExUnit.Case, async: false

  alias Thunderline.{Event, EventBus}

  @telemetry_events [
    [:thunderline, :event, :enqueue],
    [:thunderline, :event, :publish],
    [:thunderline, :event, :dropped]
  ]

  setup do
    parent = self()
    handler_id = "eventbus-telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(handler_id, @telemetry_events, fn event, measurements, metadata, _cfg ->
      send(parent, {:telemetry_event, event, measurements, metadata})
    end, nil)

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  test "emits telemetry on successful publish" do
    {:ok, event} =
      Event.new(
        name: "system.flow.telemetry_success",
        source: :flow,
        payload: %{ok?: true}
      )

    assert {:ok, _} = EventBus.publish_event(event)

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :enqueue],
                     %{count: 1} = meas,
                     %{name: name, pipeline: pipeline, priority: priority}
                   },
                   200

    assert meas.count == 1
    assert name == event.name
    assert pipeline in [:general, :realtime, :cross_domain]
    assert priority in [:low, :normal, :high, :critical]

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :publish],
                     %{duration: duration},
                     %{status: :ok, name: ^name, pipeline: ^pipeline}
                   },
                   200

    assert is_integer(duration) and duration >= 0
    refute_receive {:telemetry_event, [:thunderline, :event, :dropped], _m, _meta}, 50
  end

  test "emits dropped telemetry when validation fails" do
    prev_mode = Application.get_env(:thunderline, :event_validator_mode)
    on_exit(fn ->
      if prev_mode do
        Application.put_env(:thunderline, :event_validator_mode, prev_mode)
      else
        Application.delete_env(:thunderline, :event_validator_mode)
      end
    end)

    Application.put_env(:thunderline, :event_validator_mode, :drop)

    {:ok, event} =
      Event.new(
        name: "system.flow.telemetry_invalid",
        source: :flow,
        payload: %{ok?: false}
      )

    invalid_event = %{event | name: "invalidprefix.event"}
    invalid_name = invalid_event.name

    assert {:error, reason} = EventBus.publish_event(invalid_event)
    assert reason == :reserved_violation

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :dropped],
                     %{count: 1} = meas,
                     %{name: ^invalid_name, reason: ^reason}
                   },
                   200

    assert meas.count == 1

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :publish],
                     %{duration: duration},
                     %{status: :error, name: ^invalid_name, pipeline: :invalid}
                   },
                   200

    assert is_integer(duration) and duration >= 0
    refute_receive {:telemetry_event, [:thunderline, :event, :enqueue], _m, _meta}, 50
  end
end
