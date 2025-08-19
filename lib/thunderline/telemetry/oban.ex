defmodule Thunderline.Thunderflow.Telemetry.Oban do
  @moduledoc """
  Telemetry handlers for Oban + AshOban metrics.

  Captures job lifecycle events and routes summarized statistics into
  an internal ring buffer plus an optional Phoenix PubSub topic.
  """
  require Logger
  @events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  @buffer_name :oban_event_buffer
  @buffer_limit 200

  def attach do
    # Create ETS ring buffer table if missing
    unless :ets.whereis(@buffer_name) != :undefined do
      :ets.new(@buffer_name, [:ordered_set, :public, :named_table])
    end

    Enum.each(@events, fn ev -> :telemetry.attach({__MODULE__, ev}, ev, &__MODULE__.handle_event/4, %{}) end)
  end

  def handle_event([:oban, :job, :start], _measure, meta, _config) do
    put(:start, meta)
  end

  def handle_event([:oban, :job, :stop], measure, meta, _config) do
    put(:stop, Map.merge(meta, %{duration: measure.duration}))
  end

  def handle_event([:oban, :job, :exception], measure, meta, _config) do
    put(:exception, Map.merge(meta, %{duration: measure.duration}))
  end

  def recent(limit \\ 50) do
    :ets.tab2list(@buffer_name)
    |> Enum.sort_by(fn {k, _v} -> k end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_k, v} -> v end)
  rescue
    _ -> []
  end

  @doc """
  Return basic aggregated statistics for recent Oban job events currently in the in-memory ETS buffer.
  """
  def stats do
    try do
      events = recent(200)
      total = length(events)
      by_type = Enum.frequencies_by(events, & &1.type)
      by_queue = Enum.frequencies_by(events, & &1.queue)
      by_worker = Enum.frequencies_by(events, & &1.worker)
      %{
        total: total,
        by_type: by_type,
        queues: by_queue,
        workers: by_worker
      }
    rescue
      _ -> %{total: 0, by_type: %{}, queues: %{}, workers: %{}}
    end
  end

  defp put(type, meta) do
    ts = System.system_time(:microsecond)
    :ets.insert(@buffer_name, {ts, %{type: type, at: ts, queue: meta.queue, worker: meta.worker, state: meta.state}})
    trim()
  Phoenix.PubSub.broadcast(Thunderline.PubSub, "telemetry:oban", {:oban_event, type, meta})
  rescue
    _ -> :ok
  end

  defp trim do
    size = :ets.info(@buffer_name, :size)
    if size > @buffer_limit do
      # drop oldest entries
      drop = size - @buffer_limit
      :ets.first(@buffer_name)
      |> drop_old(drop)
    end
  end

  defp drop_old(_key, 0), do: :ok
  defp drop_old(:"$end_of_table", _), do: :ok
  defp drop_old(key, n) do
    :ets.delete(@buffer_name, key)
    drop_old(:ets.next(@buffer_name, key), n - 1)
  end
end
