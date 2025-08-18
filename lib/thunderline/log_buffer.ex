defmodule Thunderline.LogBuffer do
  @moduledoc """
  Lightweight in-memory ring buffer Logger backend for development.

  Stores the most recent N log events (default 500) in an ETS table so
  Mix tasks / LiveViews can surface logs without tailing files.
  """
  @behaviour :gen_event

  @table :thunderline_log_buffer
  @max (System.get_env("LOGBUFFER_SIZE") || "500") |> String.to_integer()

  # Public API
  def recent(n \\ 200) do
    case :ets.info(@table) do
      :undefined -> []
      _ ->
        :ets.tab2list(@table)
        |> Enum.sort_by(fn {ts, _lvl, _md, _msg} -> ts end, :desc)
        |> Enum.take(n)
        |> Enum.map(fn {_ts, lvl, md, msg} -> {lvl, md, msg} end)
        |> Enum.reverse()
    end
  end

  @doc """
  Clear all entries from the in‑memory buffer.

  Safe to call even if the table hasn't been created yet.
  """
  def clear do
    case :ets.info(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end
    :ok
  end

  # Logger backend callbacks
  # Logger passes the module name directly as the handler id for custom backends.
  # Support both bare module and {module, opts} tuple for robustness.
  def init(__MODULE__) do
    ensure_table()
    {:ok, %{max: @max}}
  end
  def init({__MODULE__, _opts}) do
    ensure_table()
    {:ok, %{max: @max}}
  end
  def init(_other) do
    ensure_table()
    {:ok, %{max: @max}}
  end

  def handle_call(_request, state), do: {:ok, :ok, state}

  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    store(ts, level, md, IO.iodata_to_binary(msg), state.max)
    {:ok, state}
  end
  def handle_event(:flush, state), do: {:ok, state}
  def handle_event(_, state), do: {:ok, state}

  def handle_info(_msg, state), do: {:ok, state}
  def code_change(_old, state, _extra), do: {:ok, state}
  def terminate(_reason, _state), do: :ok

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:ordered_set, :public, :named_table, read_concurrency: true])
      _ -> :ok
    end
  end

  defp store(ts, level, md, msg, max) do
    true = :ets.insert(@table, {ts, level, md, msg})
    trim(max)
  rescue
    _ -> :ok
  end

  defp trim(max) do
    size = :ets.info(@table, :size)
    if size > max do
      drop = size - max
      drop_keys = :ets.first(@table) |> collect_keys(drop, [])
      Enum.each(drop_keys, &:ets.delete(@table, &1))
    end
  end

  defp collect_keys(:"$end_of_table", _n, acc), do: acc
  defp collect_keys(_key, 0, acc), do: acc
  defp collect_keys(key, n, acc) do
    collect_keys(:ets.next(@table, key), n - 1, [key | acc])
  end
end
