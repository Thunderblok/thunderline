defmodule Thunderline.Current.SafeClose do
  @moduledoc "Traps exits, requests a boundary close, writes resurrection marker, broadcasts HUD state."
  use GenServer
  alias Thunderline.Bus
  alias Thunderline.Persistence.Checkpoint
  alias Thunderline.Log.NDJSON

  @timeout_ms 200

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(s) do
    Process.flag(:trap_exit, true)
    {:ok, s}
  end

  def terminate(reason, _s) do
    Bus.broadcast_status(%{stage: "paused", reason: inspect(reason), source: "terminate"})
    res = Thunderline.Current.Sensor.boundary_close(@timeout_ms)
    marker = Map.merge(res, %{reason: inspect(reason), message: "I will return."})
    NDJSON.write(Map.put(marker, :event, "resurrection_marker"))
    Checkpoint.mark_pending(true, "shutdown")
    :ok
  end
end
