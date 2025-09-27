defmodule Thunderline.Thundercom.Voice.RoomPipeline do
  @moduledoc """
  Membrane Pipeline for a single voice room.

  MVP: We'll start with a stub that just tracks participants and relays signaling.
  Later: integrate `Membrane.WebRTC` elements for real media flow.
  """
  use GenServer
  require Logger

  def start_link(room_id), do: GenServer.start_link(__MODULE__, room_id, name: via(room_id))

  defp via(id), do: {:via, Registry, {Thunderline.Thundercom.Voice.Registry, id}}

  # API for signaling messages (offer/answer/candidate) – stub for now
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
    state = %{room_id: room_id, participants: %{}, signals: []}
    Logger.metadata(room: room_id)
    Logger.info("[VoicePipeline] init room=#{room_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:offer, principal_id, sdp}, state) do
    broadcast(state.room_id, {:webrtc_offer, principal_id, sdp})
    {:noreply, state}
  end

  def handle_cast({:answer, principal_id, sdp}, state) do
    broadcast(state.room_id, {:webrtc_answer, principal_id, sdp})
    {:noreply, state}
  end

  def handle_cast({:ice, principal_id, cand}, state) do
    broadcast(state.room_id, {:webrtc_candidate, principal_id, cand})
    {:noreply, state}
  end

  def handle_cast({:speaking, principal_id, speaking?}, state) do
    broadcast(state.room_id, {:speaking, principal_id, speaking?})
    {:noreply, state}
  end

  defp broadcast(room_id, event) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, "voice:#{room_id}", event)
  end
end
