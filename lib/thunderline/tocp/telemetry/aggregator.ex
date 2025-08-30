defmodule Thunderline.TOCP.Telemetry.Aggregator do
  @moduledoc """
  Aggregates selected TOCP security telemetry events into counters accessible
  to the simulator or health endpoints. Minimal in-memory (Agent) store.

  Events captured:
    [:tocp, :security_sig_fail]
    [:tocp, :security_replay_drop]

  Public API:
    snapshot/0 -> map
    reset/0 -> :ok
  """
  use GenServer

  @events [[:tocp, :security_sig_fail], [:tocp, :security_replay_drop]]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def reset, do: GenServer.cast(__MODULE__, :reset)

  @impl true
  def init(_opts) do
    attach()
    {:ok, %{sig_fail: 0, replay_drop: 0}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:reset, _state), do: {:noreply, %{sig_fail: 0, replay_drop: 0}}

  @impl true
  def handle_info({:telemetry_event, :security_sig_fail, _m, _meta}, s), do: {:noreply, %{s | sig_fail: s.sig_fail + 1}}
  def handle_info({:telemetry_event, :security_replay_drop, _m, _meta}, s), do: {:noreply, %{s | replay_drop: s.replay_drop + 1}}
  def handle_info(_, s), do: {:noreply, s}

  defp attach do
    Enum.each(@events, fn ev ->
      id = {__MODULE__, ev}
      try do
        :telemetry.attach(id, ev, &__MODULE__.dispatch/4, %{})
      rescue
        _ -> :ok
      end
    end)
    :ok
  end

  def dispatch([:tocp, :security_sig_fail], measurements, meta, _cfg) do
    send(__MODULE__, {:telemetry_event, :security_sig_fail, measurements, meta})
  end
  def dispatch([:tocp, :security_replay_drop], measurements, meta, _cfg) do
    send(__MODULE__, {:telemetry_event, :security_replay_drop, measurements, meta})
  end
end
