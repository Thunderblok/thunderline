defmodule Thunderline.Thunderlink.Voice.RoomPipeline do
  @moduledoc """
  Per-room pipeline (GenServer) placeholder – Thunderlink namespace.
  """
  use GenServer
  require Logger
  def start_link(room_id), do: GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  defp via(id), do: {:via, Registry, {Thunderline.Thunderlink.Voice.Registry, id}}

  def handle_offer(room_id, principal_id, sdp),
    do: GenServer.cast(via(room_id), {:offer, principal_id, sdp})

  def handle_answer(room_id, principal_id, sdp),
    do: GenServer.cast(via(room_id), {:answer, principal_id, sdp})

  def add_ice(room_id, principal_id, cand),
    do: GenServer.cast(via(room_id), {:ice, principal_id, cand})

  def update_speaking(room_id, principal_id, speaking?),
    do: GenServer.cast(via(room_id), {:speaking, principal_id, speaking?})

  @impl true
  def init(room_id) do
    Logger.metadata(room: room_id)
    Logger.info("[VoicePipeline] init room=#{room_id}")
    {:ok, %{room_id: room_id}}
  end

  @impl true
  def handle_cast({:offer, principal_id, sdp}, state),
    do:
      (
        broadcast(state.room_id, {:webrtc_offer, principal_id, sdp})
        {:noreply, state}
      )

  def handle_cast({:answer, principal_id, sdp}, state),
    do:
      (
        broadcast(state.room_id, {:webrtc_answer, principal_id, sdp})
        {:noreply, state}
      )

  def handle_cast({:ice, principal_id, cand}, state),
    do:
      (
        broadcast(state.room_id, {:webrtc_candidate, principal_id, cand})
        {:noreply, state}
      )

  def handle_cast({:speaking, principal_id, speaking?}, state),
    do:
      (
        broadcast(state.room_id, {:speaking, principal_id, speaking?})
        {:noreply, state}
      )

  defp broadcast(room_id, event),
    do: Phoenix.PubSub.broadcast(Thunderline.PubSub, "voice:#{room_id}", event)
end
