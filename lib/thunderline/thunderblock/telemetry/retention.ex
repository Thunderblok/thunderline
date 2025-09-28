defmodule Thunderline.Thunderblock.Telemetry.Retention do
  @moduledoc """
  Observability utilities for the retention sweep pipeline.

  This module attaches to `[:thunderline, :retention, :sweep]` telemetry events,
  captures the key measurements in ETS for ad-hoc introspection, and republishes
  a condensed payload on the `"retention:sweeps"` PubSub topic for dashboard
  subscribers.

  The handler is intentionally lightweight so it can be started at application
  boot without introducing additional supervision dependencies. Attachments are
  idempotent and may be toggled during tests via `attach/0` and `detach/0`.
  """

  require Logger

  @event [:thunderline, :retention, :sweep]
  @handler_id "thunderline-retention-sweeps"
  @table __MODULE__.Table
  @max_events 200
  @pubsub_topic "retention:sweeps"

  @doc """
  Attach the retention telemetry handler (idempotent).
  """
  @spec attach() :: :ok
  def attach do
    ensure_table()

    case :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, %{}) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Retention.Telemetry] failed to attach handler: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Detach the retention telemetry handler (primarily for tests and hot reload).
  """
  @spec detach() :: :ok
  def detach do
    :telemetry.detach(@handler_id)
    :ok
  end

  @doc """
  Aggregate statistics derived from captured telemetry events.

  Returns a map with totals, dry-run frequency, resource breakdowns, and the
  most recent event (if any).
  """
  @spec stats() :: map()
  def stats do
    ensure_table()

    aggregate =
      :ets.foldl(
        fn {_key, entry}, acc ->
          expired = (entry.expired || 0) + acc.expired
          deleted = (entry.deleted || 0) + acc.deleted
          kept = (entry.kept || 0) + acc.kept
          runs = acc.runs + 1
          dry_runs = acc.dry_runs + if(entry.dry_run?, do: 1, else: 0)

          resources =
            Map.update(
              acc.resources,
              entry.resource || :unknown,
              entry_totals(entry),
              fn totals ->
                totals
                |> Map.update!(:runs, &(&1 + 1))
                |> Map.update!(:expired, &(&1 + (entry.expired || 0)))
                |> Map.update!(:deleted, &(&1 + (entry.deleted || 0)))
                |> Map.update!(:kept, &(&1 + (entry.kept || 0)))
              end
            )

          %{
            acc
            | runs: runs,
              dry_runs: dry_runs,
              expired: expired,
              deleted: deleted,
              kept: kept,
              resources: resources
          }
        end,
        %{runs: 0, dry_runs: 0, expired: 0, deleted: 0, kept: 0, resources: %{}},
        @table
      )

    Map.put(aggregate, :last_event, recent(1) |> List.first())
  end

  defp entry_totals(entry) do
    %{
      runs: 1,
      expired: entry.expired || 0,
      deleted: entry.deleted || 0,
      kept: entry.kept || 0
    }
  end

  @doc false
  def reset do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      table ->
        :ets.delete_all_objects(table)
        :ok
    end
  end

  @doc """
  Return the most recent N captured events (newest first).
  """
  @spec recent(pos_integer()) :: [map()]
  def recent(n \\ 10) when is_integer(n) and n > 0 do
    ensure_table()

    :ets.foldl(fn {_key, entry}, acc -> [entry | acc] end, [], @table)
    |> Enum.sort_by(& &1.at, :desc)
    |> Enum.take(n)
  end

  ## Telemetry handler ---------------------------------------------------

  @doc false
  def handle_event(_event, measurements, metadata, _config) do
    entry = build_entry(measurements, metadata)

    log_entry(entry)
    publish(entry)
    persist(entry)
  rescue
    error -> Logger.debug("[Retention.Telemetry] handler error: #{inspect(error)}")
  end

  defp build_entry(measurements, metadata) do
    %{
      at: System.system_time(:millisecond),
      duration_ms: Map.get(measurements, :duration_ms),
      expired: Map.get(measurements, :expired, 0),
      deleted: Map.get(measurements, :deleted),
      kept: Map.get(measurements, :kept, 0),
      resource: Map.get(metadata, :resource, :unknown),
      dry_run?: Map.get(metadata, :dry_run?, true),
      batch_size: Map.get(metadata, :batch_size),
      metadata: Map.drop(metadata, [:resource, :dry_run?, :batch_size])
    }
  end

  defp log_entry(entry) do
    Logger.debug(fn -> "[Retention.Telemetry] #{inspect(entry)}" end)
  end

  defp publish(entry) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      try do
        Phoenix.PubSub.broadcast(Thunderline.PubSub, @pubsub_topic, {:retention_sweep, entry})
      rescue
        _ -> :ok
      end
    end
  end

  defp persist(entry) do
    ensure_table()
    true = :ets.insert(@table, {System.unique_integer([:monotonic]), entry})
    trim_table()
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :ordered_set,
          write_concurrency: true,
          read_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp trim_table do
    size = :ets.info(@table, :size)

    if size > @max_events do
      drop = max(div(@max_events, 10), 5)
      keys = @table |> :ets.first() |> collect_keys(drop, [])
      Enum.each(keys, &:ets.delete(@table, &1))
    end
  end

  defp collect_keys(:"$end_of_table", _n, acc), do: acc
  defp collect_keys(_key, 0, acc), do: acc

  defp collect_keys(key, n, acc) do
    collect_keys(:ets.next(@table, key), n - 1, [key | acc])
  end
end
