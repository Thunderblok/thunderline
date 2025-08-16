defmodule Thunderline.Thunderflow.MetricSources do
  @moduledoc """
  Centralized metric source helpers to eliminate fake random telemetry values.

  Provides safe readers that fall back to 0 if tables aren't initialized yet.
  """

  @doc "Count active agents via Mnesia table size (ThunderMemory AgentTable)."
  def active_agents do
    table_size(Thunderline.ThunderMemory.AgentTable)
  end

  @doc "Count stored chunks via Mnesia table size (ThunderMemory ChunkTable)."
  def chunk_total do
    table_size(Thunderline.ThunderMemory.ChunkTable)
  end

  @doc "Aggregate queue stats across event tables (general + real-time + cross-domain)."
  def queue_depths do
    tables = [Thunderflow.MnesiaProducer, Thunderflow.RealTimeEvents, Thunderflow.CrossDomainEvents]

    Enum.reduce(tables, %{pending: 0, processing: 0, failed: 0, dead_letter: 0, total: 0}, fn table, acc ->
      stats = Thunderflow.MnesiaProducer.queue_stats(table)
      Map.merge(acc, stats, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

  defp table_size(table) do
    case :mnesia.system_info(:is_running) do
      :yes ->
        try do
          case :mnesia.table_info(table, :size) do
            size when is_integer(size) -> size
            _ -> 0
          end
        rescue
          _ -> 0
        end
      _ -> 0
    end
  end
end
