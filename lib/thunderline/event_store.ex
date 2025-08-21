defmodule Thunderline.Thunderflow.EventStore do
  @moduledoc """
  Minimal persistent event log used by `Thunderline.EventBus` (ThunderFlow domain).

  Day-one implementation uses a plain Mnesia `:events` table (ordered_set)
  with disc copies on the local node. This gives us:
  - Fast append & read for dashboards / replay
  - Durability on node restart (disc_copies)
  - Simple idempotency guard via primary key (id)

  Future enhancements (tracked separately):
  - Ash resource + Postgres sink for long-term retention
  - Compaction / TTL pruning
  - Secondary indices for querying by type / domain
  - Cursor based pagination API
  """

  require Logger
  @table :events

  @typedoc "Internal event record"
  @type event :: %{
          id: String.t(),
          type: String.t() | atom(),
          payload: map(),
          timestamp: DateTime.t(),
          domain: String.t() | atom(),
          correlation_id: String.t() | nil
        }

  @spec append(map()) :: :ok | {:error, term()}
  def append(%{type: type} = evt) when (is_binary(type) or is_atom(type)) and is_map(evt) do
    ensure_table()

    record = normalize(evt)

    :mnesia.transaction(fn ->
      case :mnesia.read(@table, record.id) do
        [] -> :mnesia.write({@table, record.id, record})
        _ -> :already_exists
      end
    end)
    |> case do
      {:atomic, :ok} -> :ok
      {:atomic, :already_exists} -> :ok
      {:aborted, reason} ->
        Logger.warning("EventStore append aborted: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def append(_bad), do: {:error, :invalid_event}

  @spec list(non_neg_integer()) :: [event()]
  def list(limit \\ 100) do
    ensure_table()
    {:atomic, res} = :mnesia.transaction(fn -> :mnesia.select(@table, match_all(limit)) end)
    Enum.map(res, fn {_table, _id, record} -> record end)
  rescue
    _ -> []
  end

  @spec get(String.t()) :: event() | nil
  def get(id) do
    ensure_table()
    {:atomic, res} = :mnesia.transaction(fn -> :mnesia.read(@table, id) end)
    case res do
      [{@table, ^id, record}] -> record
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp normalize(evt) do
    %{
      id: Map.get(evt, :id) || Map.get(evt, "id") || gen_id(),
      type: evt |> Map.get(:type) |> to_string(),
      payload: Map.get(evt, :payload) || Map.get(evt, :data) || %{},
      timestamp: Map.get(evt, :timestamp) || DateTime.utc_now(),
      domain: Map.get(evt, :domain) || Map.get(evt, :source) || "unknown",
      correlation_id: Map.get(evt, :correlation_id)
    }
  end

  defp gen_id, do: Base.encode64(:crypto.strong_rand_bytes(12), padding: false)

  defp match_all(limit) do
    # {table, id, record_map}
    [{{@table, :'$1', :'$2'}, [], [:'$_']}]
    |> :mnesia.select(@table, limit, :read)
  end

  defp ensure_table do
    try do
      case :mnesia.table_info(@table, :attributes) do
        [_ | _] -> :ok
      end
    catch
      :exit, _ -> create_table()
      :throw, _ -> create_table()
      :error, _ -> create_table()
    end
  end

  defp create_table do
    :mnesia.create_table(@table,
      attributes: [:id, :record],
      type: :ordered_set,
      disc_copies: [node()]
    )
    :ok
  end
end
