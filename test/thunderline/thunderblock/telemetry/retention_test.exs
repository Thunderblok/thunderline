defmodule Thunderline.Thunderblock.Telemetry.RetentionTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderblock.Telemetry.Retention, as: RetentionTelemetry

  @event [:thunderline, :retention, :sweep]

  setup do
    RetentionTelemetry.detach()
    RetentionTelemetry.reset()
    RetentionTelemetry.attach()

    on_exit(fn ->
      RetentionTelemetry.detach()
      RetentionTelemetry.reset()
    end)

    :ok
  end

  test "aggregates retention sweep telemetry" do
    :telemetry.execute(@event, %{expired: 3, deleted: 2, kept: 1, duration_ms: 12}, %{
      resource: :event_log,
      dry_run?: false,
      batch_size: 50
    })

    :telemetry.execute(@event, %{expired: 5, kept: 2, duration_ms: 20}, %{
      resource: :event_log,
      dry_run?: true,
      batch_size: 50
    })

    :telemetry.execute(@event, %{expired: 1, deleted: 1, kept: 9, duration_ms: 5}, %{
      resource: :artifact,
      dry_run?: false,
      batch_size: 25
    })

    stats = RetentionTelemetry.stats()
    assert stats.runs == 3
    assert stats.dry_runs == 1
    assert stats.expired == 9
    assert stats.deleted == 3
    assert stats.kept == 12

    assert %{runs: 2, expired: 8} = stats.resources[:event_log]
    assert %{runs: 1, deleted: 1} = stats.resources[:artifact]

    [latest | _] = RetentionTelemetry.recent(1)
    assert latest.resource == :artifact
    refute latest.dry_run?
  end
end
