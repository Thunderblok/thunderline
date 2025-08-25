defmodule Thunderline.Daisy.Base do
  @moduledoc "Common GenServer for Daisy swarms with hot memory and snapshot/restore. Provides a __using__/1 macro so shard modules can `use` this base."
  use GenServer

  # Public API for using the base module directly (optional)
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  def init(opts), do: {:ok, %{mem: [], max_mem: opts[:max_mem] || 8, decay: opts[:decay] || 0.85}}

  def preview(name), do: GenServer.call(name, :preview)
  def commit(name, inj, del), do: GenServer.cast(name, {:commit, inj, del})
  def update(name, shard, score), do: GenServer.cast(name, {:update, shard, score})
  def snapshot(name), do: GenServer.call(name, :snapshot)
  def restore(name, mem), do: GenServer.cast(name, {:restore, mem})

  def handle_call(:snapshot, _from, %{mem: mem} = s), do: {:reply, mem, s}
  def handle_cast({:restore, mem}, s) when is_list(mem), do: {:noreply, %{s | mem: mem}}
  def handle_cast({:update, shard, score}, %{mem: mem, max_mem: k} = s) do
    m1 = (mem ++ [%{shard: shard, score: score, ts: System.monotonic_time()}]) |> Enum.take(-k)
    {:noreply, %{s | mem: m1}}
  end
  def handle_call(:preview, _from, %{mem: mem, decay: d} = s) do
    dec = Enum.with_index(mem) |> Enum.map(fn {m, i} -> %{m | score: m.score * :math.pow(d, length(mem)-1-i)} end)
    inj = dec |> Enum.max_by(& &1.score, fn -> nil end)
    del = dec |> Enum.min_by(& &1.score, fn -> nil end)
    {:reply, {inj, del}, s}
  end
  def handle_cast({:commit, _inj, _del}, s), do: {:noreply, s}

  @doc """
  Use macro to inject GenServer + memory logic into a shard module.

  You may override init/1 to customize initial state (remember to include :mem, :max_mem, :decay keys).
  """
  defmacro __using__(_opts) do
    quote do
      use GenServer

      def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
      def init(opts), do: {:ok, %{mem: [], max_mem: opts[:max_mem] || 8, decay: opts[:decay] || 0.85}}

      def preview(name \\ __MODULE__), do: GenServer.call(name, :preview)
      def commit(name \\ __MODULE__, inj, del), do: GenServer.cast(name, {:commit, inj, del})
      def update(name \\ __MODULE__, shard, score), do: GenServer.cast(name, {:update, shard, score})
      def snapshot(name \\ __MODULE__), do: GenServer.call(name, :snapshot)
      def restore(name \\ __MODULE__, mem), do: GenServer.cast(name, {:restore, mem})

      def handle_call(:snapshot, _from, %{mem: mem} = s), do: {:reply, mem, s}
      def handle_cast({:restore, mem}, s) when is_list(mem), do: {:noreply, %{s | mem: mem}}
      def handle_cast({:update, shard, score}, %{mem: mem, max_mem: k} = s) do
        m1 = (mem ++ [%{shard: shard, score: score, ts: System.monotonic_time()}]) |> Enum.take(-k)
        {:noreply, %{s | mem: m1}}
      end
      def handle_call(:preview, _from, %{mem: mem, decay: d} = s) do
        dec = Enum.with_index(mem) |> Enum.map(fn {m, i} -> %{m | score: m.score * :math.pow(d, length(mem)-1-i)} end)
        inj = dec |> Enum.max_by(& &1.score, fn -> nil end)
        del = dec |> Enum.min_by(& &1.score, fn -> nil end)
        {:reply, {inj, del}, s}
      end
      def handle_cast({:commit, _inj, _del}, s), do: {:noreply, s}

      defoverridable init: 1
    end
  end
end
