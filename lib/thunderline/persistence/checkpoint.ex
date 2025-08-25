defmodule Thunderline.Persistence.Checkpoint do
  @moduledoc "DETS-backed checkpoint store for gate snapshots and resurrection markers."
  use GenServer
  @table :thunderline_checkpoint
  # Use @filepath instead of @file (reserved) for DETS filename
  @filepath ~c"thunderline_chk.dets"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(_), do: (:dets.open_file(@table, file: @filepath, type: :set); {:ok, %{}})
  def terminate(_reason, _s), do: (:dets.close(@table); :ok)

  def write(map) when is_map(map) do
    :dets.insert(@table, {:last, map})
    :ok
  end

  def read do
    case :dets.lookup(@table, :last) do
      [{:last, map}] -> {:ok, map}
      _ -> :error
    end
  end

  def mark_pending(flag, reason \\ "unknown") do
    case read() do
      {:ok, m} -> write(Map.merge(m, %{pending: flag, reason: reason}))
      _ -> :ok
    end
  end

  def clear do
    :dets.delete(@table, :last)
  end
end
