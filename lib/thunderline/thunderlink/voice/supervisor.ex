defmodule Thunderline.Thunderlink.Voice.Supervisor do
  @moduledoc """
  Dynamic supervisor for Thunderlink voice room pipelines.
  Gated by feature flag `:enable_voice_media`.
  """
  use DynamicSupervisor
  def start_link(arg), do: DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  @impl true
  def init(_arg), do: DynamicSupervisor.init(strategy: :one_for_one)
  def ensure_room(room_id) do
    case Registry.lookup(Thunderline.Thunderlink.Voice.Registry, room_id) do
      [] ->
        spec = {Thunderline.Thunderlink.Voice.RoomPipeline, room_id}
        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
      [{pid, _}] -> {:ok, pid}
    end
  end
  def stop_room(room_id) do
    case Registry.lookup(Thunderline.Thunderlink.Voice.Registry, room_id) do
      [] -> :ok
      [{pid, _}] -> (try do GenServer.stop(pid, :normal) rescue _ -> :ok end; :ok)
    end
  end
end
