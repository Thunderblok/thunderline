defmodule Thunderline.Log.RingBuffer do
  @moduledoc """
  Generic in-memory ring buffer for noisy subsystem messages (e.g. ThunderBridge, aggregator heartbeats).
  Provides a GenServer API so we can stop spamming Logger but still allow dashboards to pull history.
  """
  use GenServer
  @default_limit 300

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def push(message, server \\ __MODULE__), do: GenServer.cast(server, {:push, System.system_time(:millisecond), message})
  def recent(limit \\ 50, server \\ __MODULE__), do: GenServer.call(server, {:recent, limit})

  @impl true
  def init(opts) do
    {:ok, %{limit: Keyword.get(opts, :limit, @default_limit), entries: []}}
  end

  @impl true
  def handle_cast({:push, ts, msg}, %{entries: entries, limit: limit} = state) do
    new = [{ts, msg} | entries] |> Enum.take(limit)
    {:noreply, %{state | entries: new}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, %{entries: entries} = state) do
    {:reply, Enum.take(entries, limit), state}
  end
end
