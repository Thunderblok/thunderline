defmodule ThunderlineWeb.VoiceChannel do
  @moduledoc """
  Phoenix Channel for WebRTC signaling & presence in a voice room.

  Topic: "voice:" <> room_id
  """
  use ThunderlineWeb, :channel
  # Phase A: migrated to Thunderlink voice namespace
  alias Thunderline.Thunderlink.Voice.Supervisor, as: VoiceSupervisor
  alias Thunderline.Thunderlink.Voice.{Participant, Room}

  @impl true
  def join("voice:" <> room_id, _payload, socket) do
    with {:ok, _pid} <- VoiceSupervisor.ensure_room(room_id) do
      {:ok, assign(socket, :room_id, room_id)}
    else
      {:error, reason} -> {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def handle_in("webrtc:offer", %{"sdp" => sdp, "principal_id" => pid}, socket) do
  Thunderline.Thunderlink.Voice.RoomPipeline.handle_offer(socket.assigns.room_id, pid, sdp)
    {:noreply, socket}
  end
  def handle_in("webrtc:answer", %{"sdp" => sdp, "principal_id" => pid}, socket) do
  Thunderline.Thunderlink.Voice.RoomPipeline.handle_answer(socket.assigns.room_id, pid, sdp)
    {:noreply, socket}
  end
  def handle_in("webrtc:candidate", %{"candidate" => cand, "principal_id" => pid}, socket) do
  Thunderline.Thunderlink.Voice.RoomPipeline.add_ice(socket.assigns.room_id, pid, cand)
    {:noreply, socket}
  end
  def handle_in("participant:speaking", %{"principal_id" => pid, "speaking" => speaking?}, socket) do
  Thunderline.Thunderlink.Voice.RoomPipeline.update_speaking(socket.assigns.room_id, pid, speaking?)
    {:noreply, socket}
  end
end
