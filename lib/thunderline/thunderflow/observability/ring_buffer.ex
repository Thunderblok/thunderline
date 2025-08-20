defmodule Thunderline.Thunderflow.Observability.RingBuffer do
  @moduledoc """
  Generic in-memory ring buffer for noisy subsystem messages (e.g. ThunderBridge, aggregator heartbeats).
  Provides a GenServer API so we can avoid spamming Logger but still allow dashboards to pull history.

  Starts under the main supervision tree with a configurable :limit.
  """
  use GenServer

  @default_limit 300

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Push a message (any term) into the ring buffer
  """
  def push(message, server \\ __MODULE__), do: GenServer.cast(server, {:push, System.system_time(:millisecond), message})

  @doc """
  Return most recent N entries (timestamp, message) newest-first
  """
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

  # Accept direct telemetry events forwarded as raw casts (e.g. from telemetry handlers)
  def handle_cast({:telemetry_event, payload}, %{entries: entries, limit: limit} = state) do
    ts = System.system_time(:millisecond)
    new = [{ts, {:telemetry, payload}} | entries] |> Enum.take(limit)
    {:noreply, %{state | entries: new}}
  end

  # Catch-all so unexpected messages never crash the buffer (acts as a noise sink)
  def handle_cast(msg, %{entries: entries, limit: limit} = state) do
    ts = System.system_time(:millisecond)
    new = [{ts, {:unknown, msg}} | entries] |> Enum.take(limit)
    {:noreply, %{state | entries: new}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, %{entries: entries} = state) do
    {:reply, Enum.take(entries, limit), state}
  end
end
