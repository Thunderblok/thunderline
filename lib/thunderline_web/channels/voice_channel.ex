defmodule ThunderlineWeb.VoiceChannel do
  @moduledoc """
  Phoenix Channel for WebRTC signaling & presence in a voice room.

  Topic: "voice:" <> room_id

  HC-13: Emits taxonomy-compliant `voice.signal.*` and `voice.room.*` events
  to EventBus for downstream processing and telemetry.
  """
  use ThunderlineWeb, :channel

  alias Thunderline.Thunderlink.Voice.Supervisor, as: VoiceSupervisor
  alias Thunderline.Thunderlink.Voice.RoomPipeline
  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus

  require Logger

  @impl true
  def join("voice:" <> room_id, _payload, socket) do
    actor_ctx = socket.assigns[:actor_ctx]
    principal_id = get_principal_id(socket)

    # Emit join attempt telemetry
    :telemetry.execute(
      [:thunderline, :link, :voice, :join_attempt],
      %{count: 1},
      %{room_id: room_id, principal_id: principal_id}
    )

    with {:ok, _pid} <- VoiceSupervisor.ensure_room(room_id) do
      # Emit successful join event
      emit_voice_event("voice.room.participant.joined", %{
        room_id: room_id,
        principal_id: principal_id,
        actor_ctx: actor_ctx && Map.take(actor_ctx, [:actor_id, :actor_type])
      })

      :telemetry.execute(
        [:thunderline, :link, :voice, :join_success],
        %{count: 1},
        %{room_id: room_id}
      )

      {:ok, assign(socket, room_id: room_id, principal_id: principal_id)}
    else
      {:error, reason} ->
        Logger.warning("[VoiceChannel] Join failed room=#{room_id} reason=#{inspect(reason)}")

        :telemetry.execute(
          [:thunderline, :link, :voice, :join_error],
          %{count: 1},
          %{room_id: room_id, reason: reason}
        )

        {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def handle_in("webrtc:offer", %{"sdp" => sdp} = payload, socket) do
    room_id = socket.assigns.room_id
    principal_id = payload["principal_id"] || socket.assigns.principal_id

    # Emit signaling event
    emit_voice_event("voice.signal.offer", %{
      room_id: room_id,
      from: principal_id,
      sdp_type: "offer",
      size: byte_size(sdp)
    })

    :telemetry.execute(
      [:thunderline, :link, :voice, :signal],
      %{count: 1, size: byte_size(sdp)},
      %{room_id: room_id, type: :offer}
    )

    RoomPipeline.handle_offer(room_id, principal_id, sdp)
    {:noreply, socket}
  end

  def handle_in("webrtc:answer", %{"sdp" => sdp} = payload, socket) do
    room_id = socket.assigns.room_id
    principal_id = payload["principal_id"] || socket.assigns.principal_id

    emit_voice_event("voice.signal.answer", %{
      room_id: room_id,
      from: principal_id,
      sdp_type: "answer",
      size: byte_size(sdp)
    })

    :telemetry.execute(
      [:thunderline, :link, :voice, :signal],
      %{count: 1, size: byte_size(sdp)},
      %{room_id: room_id, type: :answer}
    )

    RoomPipeline.handle_answer(room_id, principal_id, sdp)
    {:noreply, socket}
  end

  def handle_in("webrtc:candidate", %{"candidate" => candidate} = payload, socket) do
    room_id = socket.assigns.room_id
    principal_id = payload["principal_id"] || socket.assigns.principal_id

    emit_voice_event("voice.signal.ice", %{
      room_id: room_id,
      from: principal_id,
      candidate: candidate
    })

    :telemetry.execute(
      [:thunderline, :link, :voice, :signal],
      %{count: 1},
      %{room_id: room_id, type: :ice}
    )

    RoomPipeline.add_ice(room_id, principal_id, candidate)
    {:noreply, socket}
  end

  def handle_in("participant:speaking", %{"speaking" => speaking?} = payload, socket) do
    room_id = socket.assigns.room_id
    principal_id = payload["principal_id"] || socket.assigns.principal_id

    emit_voice_event("voice.room.speaking", %{
      room_id: room_id,
      principal_id: principal_id,
      speaking: speaking?
    })

    :telemetry.execute(
      [:thunderline, :link, :voice, :speaking],
      %{count: 1},
      %{room_id: room_id, speaking: speaking?}
    )

    RoomPipeline.update_speaking(room_id, principal_id, speaking?)
    {:noreply, socket}
  end

  # Catch-all for unrecognized events
  def handle_in(event, _payload, socket) do
    Logger.warning("[VoiceChannel] Unhandled event: #{event}")
    {:noreply, socket}
  end

  @impl true
  def terminate(reason, socket) do
    room_id = socket.assigns[:room_id]
    principal_id = socket.assigns[:principal_id]

    if room_id do
      emit_voice_event("voice.room.participant.left", %{
        room_id: room_id,
        principal_id: principal_id,
        reason: inspect(reason)
      })

      :telemetry.execute(
        [:thunderline, :link, :voice, :leave],
        %{count: 1},
        %{room_id: room_id, reason: reason}
      )
    end

    :ok
  end

  # --- Private Helpers ---

  defp get_principal_id(socket) do
    cond do
      socket.assigns[:current_scope] -> socket.assigns.current_scope.user.id
      socket.assigns[:actor_ctx] -> socket.assigns.actor_ctx.actor_id
      socket.assigns[:user_id] -> socket.assigns.user_id
      true -> UUID.uuid4()
    end
  end

  defp emit_voice_event(name, payload) do
    case Event.new(%{
           name: name,
           type: String.to_atom(String.replace(name, ".", "_")),
           source: :link,
           payload: payload,
           meta: %{reliability: :transient}
         }) do
      {:ok, event} ->
        # Fire and forget - voice events are transient
        Task.start(fn ->
          case EventBus.publish_event(event) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.debug("[VoiceChannel] Event publish failed: #{inspect(reason)}")
          end
        end)

      {:error, reason} ->
        Logger.warning("[VoiceChannel] Failed to create event #{name}: #{inspect(reason)}")
    end
  end
end
