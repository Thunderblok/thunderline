defmodule Thunderline.Thunderflow.Telemetry.LegacyBlackboardWatch do
  @moduledoc """
  IRONWOLF telemetry watcher counting legacy blackboard calls.

  Attaches a handler to `[:thunderline, :blackboard, :legacy_call]` and stores
  counts in an ETS table for a sliding window observation period. Removal of the
  legacy delegator proceeds once counts remain zero for the full window.
  """
  @table :legacy_blackboard_watch

  def start_link(opts) do
    ensure_table()
    handler_id = {:legacy_blackboard_watch, self()}
    :telemetry.attach(handler_id, [:thunderline, :blackboard, :legacy_call], &__MODULE__.handle_event/4, %{})
    {:ok, handler_id}
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    ensure_table()
    :ets.update_counter(@table, :count, 1, {:count, 0})
    :ok
  end

  def count do
    ensure_table()
    case :ets.lookup(@table, :count) do
      [{:count, c}] -> c
      _ -> 0
    end
  end

  def reset do
    ensure_table(); :ets.insert(@table, {:count, 0}); :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true]); :ok
      _ -> :ok
    end
  end
end
