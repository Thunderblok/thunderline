defmodule Thunderline.Thundercom.Voice.Supervisor do
  @moduledoc """
  Dynamic supervisor for per-room Membrane pipelines.

  Responsible for starting a pipeline process for each active voice room.
  """
  use DynamicSupervisor
  require Logger

  def start_link(arg), do: DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
def init(_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def ensure_room(room_id) do
  case Registry.lookup(Thunderline.Thundercom.Voice.Registry, room_id) do
      [] ->
  spec = {Thunderline.Thundercom.Voice.RoomPipeline, room_id}
        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
      [{pid, _}] -> {:ok, pid}
    end
  end

  @doc """
  Stop a room pipeline if it exists. Returns :ok whether or not the room was running.

  We use GenServer.stop/2 directly because the child is registered via :via and managed
  by the DynamicSupervisor; normal termination will allow restart if mistakenly invoked,
  but callers generally only use this when the underlying room resource has been closed.
  """
  def stop_room(room_id) do
    case Registry.lookup(Thunderline.Thundercom.Voice.Registry, room_id) do
      [] -> :ok
      [{pid, _}] ->
        try do
          GenServer.stop(pid, :normal)
        catch
          _, _ -> :ok
        end
        :ok
    end
  end
end
