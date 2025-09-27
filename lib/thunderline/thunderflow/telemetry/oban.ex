defmodule Thunderline.Thunderflow.Telemetry.Oban do
  @moduledoc """
  Telemetry wiring for Oban job & queue events.

  This module is intentionally lightweight so the application boot does
  not crash if Oban isn't fully migrated yet (e.g. during bootstrap or
  SKIP_ASH_SETUP test runs). It exposes a single public function
  `attach/0` which is invoked from `Thunderline.Application` to
  subscribe to core Oban telemetry events. Additional aggregation or
  export (Prometheus, OpenTelemetry, custom dashboards) can be layered
  on later without changing the application supervisor.

  Currently handled events:
    * [:oban, :job, :start]
    * [:oban, :job, :stop]
    * [:oban, :job, :exception]
    * [:oban, :plugin, :stop] (lightweight visibility for plugins like Pruner & Cron)

  For each event we emit a compact map to the Thunderflow observability
  ring buffer (if present) and log at :debug (can be tuned via Logger
  level). This avoids introducing a hard dependency cycle into
  DashboardMetrics; consumers can subscribe to the PubSub topic
  "oban:events" if real-time UI integration is needed later.
  """

  require Logger

  @job_events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  @plugin_events [
    [:oban, :plugin, :stop]
  ]

  @handler_id "thunderline-oban-jobs"
  @plugin_handler_id "thunderline-oban-plugins"

  # In-memory ring buffer (ETS) for simple recent/aggregate queries used in tests & dashboard.
  @table __MODULE__.Table
  @max_events 500

  @doc """
  Attach telemetry handlers for Oban events (idempotent).
  Safe to call multiple times; subsequent calls become no-ops.
  """
  @spec attach() :: :ok
  def attach do
    attach_jobs()
    attach_plugins()
    ensure_table()
    :ok
  end

  defp attach_jobs do
    case :telemetry.attach_many(@handler_id, @job_events, &__MODULE__.handle_job_event/4, %{}) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Oban.Telemetry] failed to attach job handlers: #{inspect(reason)}")
    end
  end

  defp attach_plugins do
    case :telemetry.attach_many(
           @plugin_handler_id,
           @plugin_events,
           &__MODULE__.handle_plugin_event/4,
           %{}
         ) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Oban.Telemetry] failed to attach plugin handlers: #{inspect(reason)}")
    end
  end

  @doc """
  Detach handlers (mainly for tests / hot reload scenarios).
  """
  def detach do
    :telemetry.detach(@handler_id)
    :telemetry.detach(@plugin_handler_id)
    :ok
  end

  ## Telemetry Handlers --------------------------------------------------

  # measurements examples:
  #   start: %{system_time: integer}
  #   stop: %{duration: native_time}
  #   exception: %{duration: native_time}
  # metadata common keys: %{id: ..., args: ..., attempt: ..., queue: ..., worker: ..., state: ...}
  def handle_job_event([:oban, :job, event_type] = event, measurements, metadata, _config) do
    simplified = %{
      ev: event_type,
      queue: metadata[:queue],
      worker: metadata[:worker],
      attempt: metadata[:attempt],
      state: metadata[:state],
      duration_us: native_duration_to_us(measurements[:duration]),
      at: System.system_time(:millisecond)
    }

    log_event(event, simplified)
    publish_event("oban:events", simplified)
    push_ring_buffer(:oban, simplified)
  rescue
    error -> Logger.debug("[Oban.Telemetry] handler error: #{inspect(error)}")
  end

  def handle_plugin_event([:oban, :plugin, :stop] = event, measurements, metadata, _config) do
    simplified = %{
      ev: :plugin_stop,
      plugin: metadata[:plugin],
      duration_us: native_duration_to_us(measurements[:duration]),
      at: System.system_time(:millisecond)
    }

    log_event(event, simplified)
    publish_event("oban:plugins", simplified)
    push_ring_buffer(:oban_plugin, simplified)
  rescue
    error -> Logger.debug("[Oban.Telemetry] plugin handler error: #{inspect(error)}")
  end

  @doc "Return aggregated stats used by tests (shape kept minimal)."
  def stats do
    ensure_table()
    events = :ets.tab2list(@table)

    by_type =
      Enum.reduce(events, %{}, fn {_k, %{ev: ev}}, acc ->
        Map.update(acc, ev, 1, &(&1 + 1))
      end)

    %{total: length(events), by_type: by_type}
  end

  @doc "Return last N events (newest first)."
  def recent(n \\ 10) do
    ensure_table()

    :ets.foldl(fn {_k, v}, acc -> [v | acc] end, [], @table)
    |> Enum.sort_by(& &1.at, :desc)
    |> Enum.take(n)
    |> Enum.map(fn map -> Map.put(map, :type, map.ev) end)
  end

  ## Internal helpers ----------------------------------------------------

  defp native_duration_to_us(nil), do: nil

  defp native_duration_to_us(native) when is_integer(native),
    do: System.convert_time_unit(native, :native, :microsecond)

  defp log_event(_event, simplified) do
    Logger.debug(fn -> "[Oban.Telemetry] #{inspect(simplified)}" end)
  end

  # Publish through Phoenix.PubSub if available; ignore if not loaded yet
  defp publish_event(topic, payload) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      try do
        Phoenix.PubSub.broadcast(Thunderline.PubSub, topic, {:oban_telemetry, payload})
      rescue
        _ -> :noop
      end
    end
  end

  # Push into the observability ring buffer if it’s running (best effort)
  defp push_ring_buffer(_type, payload) do
    if Process.whereis(Thunderline.NoiseBuffer) do
      # Expecting a GenServer interface like put/2 or push/1; using :put fallback semantics
      try do
        GenServer.cast(Thunderline.NoiseBuffer, {:telemetry_event, payload})
      rescue
        _ -> :noop
      end
    end

    # Also persist into ETS for stats/recent queries
    ensure_table()
    true = :ets.insert(@table, {System.unique_integer([:monotonic]), payload})
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
      # Drop oldest ~10% in one pass for amortized O(1)
      drop = div(@max_events, 10)
      keys = :ets.first(@table) |> collect_keys(drop, [])
      Enum.each(keys, &:ets.delete(@table, &1))
    end
  end

  defp collect_keys(:"$end_of_table", _n, acc), do: acc
  defp collect_keys(_key, 0, acc), do: acc

  defp collect_keys(key, n, acc) do
    collect_keys(:ets.next(@table, key), n - 1, [key | acc])
  end
end
