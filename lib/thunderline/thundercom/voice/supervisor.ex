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
end
