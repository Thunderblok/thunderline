defmodule Thunderline.Thunderflow.DLQ do
  @moduledoc """
  Observability helpers for the ThunderFlow dead letter queues.

  * Provides aggregated DLQ sizing across all Mnesia-backed Broadway tables.
  * Emits telemetry on size changes so metrics backends can alert on depth.
  * Broadcasts Phoenix PubSub alerts when thresholds are crossed.
  * Exposes convenience helpers for rendering recent failures in the operator UI.
  """

  require Logger

  alias Phoenix.PubSub
  alias Thunderline.PubSub, as: AppPubSub
  alias Thunderline.Thunderflow.MnesiaProducer

  @telemetry_event [:thunderline, :event, :dlq, :size]
  @alert_topic "thunderline:dlq:alerts"
  @persistent_key {:thunderline, :dlq, :last_size}
  @default_threshold 100
  @default_tables [
    Thunderline.Thunderflow.MnesiaProducer,
    Thunderline.Thunderflow.CrossDomainEvents,
    Thunderline.Thunderflow.RealTimeEvents
  ]

  @doc """
  Returns the list of Mnesia tables that hold Broadway events and can accumulate DLQ entries.
  """
  @spec tables() :: [atom()]
  def tables do
    @default_tables
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.filter(&table_defined?/1)
  end

  @doc """
  Returns the configured DLQ threshold for alerting.
  """
  @spec threshold() :: pos_integer()
  def threshold do
    Application.get_env(:thunderline, __MODULE__, [])
    |> Keyword.get(:threshold, @default_threshold)
  end

  @doc """
  Computes the total number of DLQ entries across all tracked tables.
  """
  @spec size() :: non_neg_integer()
  def size do
    tables()
    |> Enum.reduce(0, fn table, acc ->
      stats = MnesiaProducer.queue_stats(table)
      acc + Map.get(stats, :dead_letter, 0)
    end)
  end

  @doc """
  Returns a map with the current count, configured threshold, and recent failures.
  """
  @spec stats(non_neg_integer()) :: %{
          count: non_neg_integer(),
          threshold: pos_integer(),
          recent: list()
        }
  def stats(limit \\ 5) do
    %{
      count: size(),
      threshold: threshold(),
      recent: recent(limit)
    }
  end

  @doc """
  Reads the most recent DLQ entries (across all tables) up to the provided limit.
  """
  @spec recent(non_neg_integer()) :: list()
  def recent(limit \\ 5) do
    tables()
    |> Enum.flat_map(&table_recent(&1, limit))
    |> Enum.sort_by(&(&1.failed_at || &1.created_at || DateTime.utc_now()), {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Emits telemetry and publishes alerts for the current DLQ size.
  """
  @spec emit_size(map()) :: non_neg_integer()
  def emit_size(meta \\ %{}) when is_map(meta) do
    emit_size(size(), meta)
  end

  @doc """
  Emits telemetry and publishes alerts for a provided DLQ size.

  Useful for tests that want deterministic control over the emitted count.
  """
  @spec emit_size(non_neg_integer(), map()) :: non_neg_integer()
  def emit_size(count, meta) when is_integer(count) and count >= 0 and is_map(meta) do
    previous = update_last_size(count)

    metadata =
      meta
      |> Map.new()
      |> Map.put(:threshold, threshold())
      |> Map.put(:previous_count, previous)

    :telemetry.execute(@telemetry_event, %{count: count}, metadata)
    maybe_broadcast_alert(previous, count, metadata)
    count
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  defp table_defined?(table) do
    try do
      :mnesia.table_info(table, :attributes)
      true
    catch
      # Mnesia uses exit/throw, not exceptions
      :exit, {:aborted, {:no_exists, _, _}} -> false
      :exit, _ -> false
    rescue
      _ -> false
    end
  end

  defp table_recent(table, limit) do
    try do
      attrs = :mnesia.table_info(table, :attributes)
      status_index = Enum.find_index(attrs, &(&1 == :status))
      created_at_index = Enum.find_index(attrs, &(&1 == :created_at))
      attempts_index = Enum.find_index(attrs, &(&1 == :attempts))

      vars = for i <- 1..length(attrs), do: String.to_atom("$#{i}")
      pattern = List.to_tuple([table | vars])
      status_var = Enum.at(vars, status_index)

      spec = [{pattern, [{:==, status_var, :dead_letter}], [:"$_"]}]

      case :mnesia.transaction(fn -> :mnesia.select(table, spec) end) do
        {:atomic, records} ->
          records
          |> Enum.map(&record_to_entry(&1, attrs, attempts_index, created_at_index, table))
          |> Enum.sort_by(
            &(&1.failed_at || &1.created_at || DateTime.utc_now()),
            {:desc, DateTime}
          )
          |> Enum.take(limit)

        {:aborted, _} ->
          []
      end
    rescue
      _ -> []
    end
  end

  defp record_to_entry(record, attrs, _attempts_index, _created_at_index, table) do
    values = Tuple.to_list(record) |> tl()
    attr_map = Enum.zip(attrs, values) |> Map.new()

    data = normalize_data(Map.get(attr_map, :data))
    dlq_meta = Map.get(data, "_dlq") || Map.get(data, :_dlq) || %{}

    %{
      id: attr_map[:id],
      table: table,
      attempts:
        attr_map[:attempts] || Map.get(dlq_meta, "attempt") || Map.get(dlq_meta, :attempt),
      created_at: attr_map |> Map.get(:created_at),
      failed_at: dlq_failed_at(dlq_meta) || attr_map |> Map.get(:updated_at),
      reason: dlq_reason(dlq_meta),
      pipeline_type: attr_map[:pipeline_type],
      priority: attr_map[:priority],
      meta: dlq_meta
    }
  end

  defp dlq_reason(dlq_meta) do
    dlq_meta["reason"] || dlq_meta[:reason] || "unknown"
  end

  defp dlq_failed_at(dlq_meta) do
    case dlq_meta["failed_at"] || dlq_meta[:failed_at] do
      %DateTime{} = dt ->
        dt

      %NaiveDateTime{} = ndt ->
        DateTime.from_naive!(ndt, "Etc/UTC")

      binary when is_binary(binary) ->
        case DateTime.from_iso8601(binary) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp normalize_data(nil), do: %{}
  defp normalize_data(%{} = data), do: data
  defp normalize_data(struct) when is_struct(struct), do: Map.from_struct(struct)
  defp normalize_data(other), do: %{"value" => other}

  defp update_last_size(count) do
    previous = :persistent_term.get(@persistent_key, 0)
    :persistent_term.put(@persistent_key, count)
    previous
  end

  defp maybe_broadcast_alert(previous, count, metadata) do
    threshold = metadata[:threshold] || threshold()

    cond do
      previous < threshold and count >= threshold ->
        payload = build_alert_payload(:dlq_threshold_exceeded, count, threshold, metadata)
        Logger.warning("[DLQ] threshold exceeded (count=#{count} threshold=#{threshold})")
        PubSub.broadcast(AppPubSub, @alert_topic, {:dlq_threshold_exceeded, payload})

      previous >= threshold and count < threshold ->
        payload = build_alert_payload(:dlq_threshold_cleared, count, threshold, metadata)
        Logger.info("[DLQ] threshold cleared (count=#{count} threshold=#{threshold})")
        PubSub.broadcast(AppPubSub, @alert_topic, {:dlq_threshold_cleared, payload})

      true ->
        :ok
    end
  end

  defp build_alert_payload(event, count, threshold, metadata) do
    %{
      event: event,
      count: count,
      threshold: threshold,
      previous_count: metadata[:previous_count],
      source: metadata[:source],
      timestamp: DateTime.utc_now()
    }
  end
end
