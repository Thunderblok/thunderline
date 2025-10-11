defmodule Thunderflow.EventBusTelemetryTest do
  use ExUnit.Case, async: false

  alias Thunderline.{Event, EventBus}

  @telemetry_events [
    [:thunderline, :eventbus, :publish, :start],
    [:thunderline, :eventbus, :publish, :stop],
    [:thunderline, :eventbus, :publish, :exception],
    [:thunderline, :event, :enqueue],
    [:thunderline, :event, :publish],
    [:thunderline, :event, :dropped]
  ]

  setup do
    parent = self()
    handler_id = "eventbus-telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      @telemetry_events,
      fn event, measurements, metadata, _cfg ->
        send(parent, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

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
    event_name = event.name

    event_source = event.source
    event_priority = event.priority

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :start],
                     %{system_time: _} = meas,
                     %{
                       event_name: ^event_name,
                       category: category,
                       source: ^event_source,
                       priority: ^event_priority
                     }
                   },
                   200

    assert is_integer(meas.system_time)
    assert category == "system"

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :enqueue],
                     %{count: 1} = meas,
                     %{name: ^event_name, pipeline: pipeline, priority: ^event_priority}
                   },
                   200

    assert meas.count == 1
    assert pipeline in [:general, :realtime, :cross_domain]

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :stop],
                     %{duration: duration, system_time: _},
                     %{status: :ok, pipeline: ^pipeline, event_name: ^event_name}
                   },
                   200

    assert is_integer(duration) and duration >= 0

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :publish],
                     %{duration: pub_duration},
                     %{status: :ok, name: ^event_name, pipeline: ^pipeline}
                   },
                   200

    assert is_integer(pub_duration) and pub_duration >= 0
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
    invalid_source = invalid_event.source

    assert {:error, reason} = EventBus.publish_event(invalid_event)
    assert reason == :reserved_violation

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :start],
                     %{system_time: _},
                     %{event_name: ^invalid_name, source: ^invalid_source}
                   },
                   200

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
                     [:thunderline, :eventbus, :publish, :exception],
                     %{duration: _},
                     %{event_name: ^invalid_name, kind: :validation_failed, pipeline: :invalid}
                   },
                   200

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :stop],
                     %{duration: duration, system_time: _},
                     %{status: :error, pipeline: :invalid, event_name: ^invalid_name}
                   },
                   200

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :publish],
                     %{duration: pub_duration},
                     %{status: :error, name: ^invalid_name, pipeline: :invalid}
                   },
                   200

    assert is_integer(duration) and duration >= 0
    assert is_integer(pub_duration) and pub_duration >= 0

    refute_receive {:telemetry_event, [:thunderline, :event, :enqueue], _m, _meta}, 50
  end

  test "rejects events whose domain/category pairing is invalid" do
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
        name: "ml.run.started",
        source: :bolt,
        payload: %{run_id: "run-1"}
      )

    invalid_event = %{event | source: :gate}
    invalid_name = invalid_event.name

    assert {:error, :forbidden_category} = EventBus.publish_event(invalid_event)

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :start],
                     _measurements,
                     %{event_name: ^invalid_name}
                   },
                   200

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :exception],
                     %{duration: _},
                     %{
                       event_name: ^invalid_name,
                       kind: :validation_failed,
                       pipeline: :invalid
                     }
                   },
                   200

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :eventbus, :publish, :stop],
                     %{duration: duration, system_time: _},
                     %{status: :error, pipeline: :invalid, event_name: ^invalid_name}
                   },
                   200

    assert is_integer(duration) and duration >= 0

    assert_receive {
                     :telemetry_event,
                     [:thunderline, :event, :publish],
                     %{duration: pub_duration},
                     %{status: :error, name: ^invalid_name, pipeline: :invalid}
                   },
                   200

    assert is_integer(pub_duration) and pub_duration >= 0

    refute_receive {:telemetry_event, [:thunderline, :event, :enqueue], _m, _meta}, 50
  end
end
