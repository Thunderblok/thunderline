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
    actor_ctx = socket.assigns[:actor_ctx]
    resource = {:voice_room, room_id}
    case Thunderline.Thunderlink.Presence.Policy.decide(:join, resource, actor_ctx) do
      {:deny, reason} ->
        :telemetry.execute([:thunderline, :link, :presence, :blocked_channel_join], %{count: 1}, %{room_id: room_id, reason: reason, actor: actor_ctx && actor_ctx.actor_id})
        {:error, %{reason: "presence_denied"}}
      {:allow, _} ->
        with {:ok, _pid} <- VoiceSupervisor.ensure_room(room_id) do
          {:ok, assign(socket, :room_id, room_id)}
        else
          {:error, reason} -> {:error, %{reason: inspect(reason)}}
        end
    end
  end

  @impl true
  def handle_in(event, payload, socket) when event in ["webrtc:offer", "webrtc:answer", "webrtc:candidate", "participant:speaking"] do
    actor_ctx = socket.assigns[:actor_ctx]
    case Thunderline.Thunderlink.Presence.Policy.decide(:send, {:voice_room, socket.assigns.room_id}, actor_ctx) do
      {:deny, reason} ->
        :telemetry.execute([:thunderline, :link, :presence, :blocked_channel_send], %{count: 1}, %{room_id: socket.assigns.room_id, reason: reason, actor: actor_ctx && actor_ctx.actor_id, event: event})
        {:noreply, socket}
      {:allow, _} ->
        dispatch_voice(event, payload, socket)
        {:noreply, socket}
    end
  end

  defp dispatch_voice("webrtc:offer", %{"sdp" => sdp, "principal_id" => pid}, socket), do: Thunderline.Thunderlink.Voice.RoomPipeline.handle_offer(socket.assigns.room_id, pid, sdp)
  defp dispatch_voice("webrtc:answer", %{"sdp" => sdp, "principal_id" => pid}, socket), do: Thunderline.Thunderlink.Voice.RoomPipeline.handle_answer(socket.assigns.room_id, pid, sdp)
  defp dispatch_voice("webrtc:candidate", %{"candidate" => cand, "principal_id" => pid}, socket), do: Thunderline.Thunderlink.Voice.RoomPipeline.add_ice(socket.assigns.room_id, pid, cand)
  defp dispatch_voice("participant:speaking", %{"principal_id" => pid, "speaking" => speaking?}, socket), do: Thunderline.Thunderlink.Voice.RoomPipeline.update_speaking(socket.assigns.room_id, pid, speaking?)
end
