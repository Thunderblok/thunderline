defmodule Thunderline.Thunderlink.Voice.RoomPipeline do
  @moduledoc """
  Per-room voice pipeline GenServer.

  HC-13: Enhanced with taxonomy-compliant event emission and intent detection pathway.

  ## Responsibilities
  - Relay WebRTC signaling (offer/answer/ICE) between participants
  - Track speaking state and emit `voice.room.speaking.*` events
  - Prepare future hooks for:
    - Transcription segments (`voice.intent.transcription.segment`)
    - Intent detection (`voice.intent.detected`)
    - Media recording

  ## Event Flow
  ```
  VoiceChannel --> RoomPipeline --> PubSub (broadcast)
                       |
                       v
                  EventBus (voice.room.*, voice.intent.*)
  ```
  """
  use GenServer

  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus

  require Logger

  @registry Thunderline.Thunderlink.Voice.Registry

  # --- Public API ---

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def child_spec(room_id) do
    %{
      id: {__MODULE__, room_id},
      start: {__MODULE__, :start_link, [room_id]},
      restart: :temporary
    }
  end

  defp via(id), do: {:via, Registry, {@registry, id}}

  @doc "Forward WebRTC offer to room participants"
  def handle_offer(room_id, principal_id, sdp) do
    GenServer.cast(via(room_id), {:offer, principal_id, sdp})
  end

  @doc "Forward WebRTC answer to room participants"
  def handle_answer(room_id, principal_id, sdp) do
    GenServer.cast(via(room_id), {:answer, principal_id, sdp})
  end

  @doc "Forward ICE candidate to room participants"
  def add_ice(room_id, principal_id, candidate) do
    GenServer.cast(via(room_id), {:ice, principal_id, candidate})
  end

  @doc "Update participant speaking state"
  def update_speaking(room_id, principal_id, speaking?) do
    GenServer.cast(via(room_id), {:speaking, principal_id, speaking?})
  end

  @doc "Submit audio transcript segment for intent processing"
  def submit_transcript(room_id, principal_id, text, opts \\ []) do
    GenServer.cast(via(room_id), {:transcript, principal_id, text, opts})
  end

  @doc "Get current room state"
  def get_state(room_id) do
    GenServer.call(via(room_id), :get_state)
  end

  # --- Callbacks ---

  @impl true
  def init(room_id) do
    Logger.metadata(room: room_id)
    Logger.info("[VoicePipeline] Started room=#{room_id}")

    :telemetry.execute(
      [:thunderline, :link, :voice, :room_started],
      %{count: 1},
      %{room_id: room_id}
    )

    emit_room_event("voice.room.created", room_id, %{})

    {:ok,
     %{
       room_id: room_id,
       participants: %{},
       speaking: MapSet.new(),
       created_at: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_cast({:offer, principal_id, sdp}, state) do
    broadcast(state.room_id, {:webrtc_offer, principal_id, sdp})

    state = track_participant(state, principal_id)
    {:noreply, state}
  end

  def handle_cast({:answer, principal_id, sdp}, state) do
    broadcast(state.room_id, {:webrtc_answer, principal_id, sdp})

    state = track_participant(state, principal_id)
    {:noreply, state}
  end

  def handle_cast({:ice, principal_id, candidate}, state) do
    broadcast(state.room_id, {:webrtc_candidate, principal_id, candidate})
    {:noreply, state}
  end

  def handle_cast({:speaking, principal_id, true}, state) do
    broadcast(state.room_id, {:speaking, principal_id, true})

    new_speaking = MapSet.put(state.speaking, principal_id)

    emit_room_event("voice.room.speaking.started", state.room_id, %{
      principal_id: principal_id,
      concurrent_speakers: MapSet.size(new_speaking)
    })

    {:noreply, %{state | speaking: new_speaking}}
  end

  def handle_cast({:speaking, principal_id, false}, state) do
    broadcast(state.room_id, {:speaking, principal_id, false})

    new_speaking = MapSet.delete(state.speaking, principal_id)

    emit_room_event("voice.room.speaking.stopped", state.room_id, %{
      principal_id: principal_id,
      concurrent_speakers: MapSet.size(new_speaking)
    })

    {:noreply, %{state | speaking: new_speaking}}
  end

  def handle_cast({:transcript, principal_id, text, opts}, state) do
    # Emit transcription segment event
    emit_intent_event("voice.intent.transcription.segment", state.room_id, %{
      principal_id: principal_id,
      text: text,
      language: Keyword.get(opts, :language, "en"),
      confidence: Keyword.get(opts, :confidence, 1.0),
      timestamp: DateTime.utc_now()
    })

    # Process for intent detection (MVP: simple keyword matching)
    maybe_detect_intent(state.room_id, principal_id, text)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply,
     %{
       room_id: state.room_id,
       participant_count: map_size(state.participants),
       speaking_count: MapSet.size(state.speaking),
       speaking: MapSet.to_list(state.speaking),
       uptime_seconds: DateTime.diff(DateTime.utc_now(), state.created_at)
     }, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[VoicePipeline] Stopping room=#{state.room_id} reason=#{inspect(reason)}")

    emit_room_event("voice.room.closed", state.room_id, %{
      reason: inspect(reason),
      final_participant_count: map_size(state.participants)
    })

    :telemetry.execute(
      [:thunderline, :link, :voice, :room_stopped],
      %{count: 1},
      %{room_id: state.room_id, reason: reason}
    )

    :ok
  end

  # --- Private Helpers ---

  defp broadcast(room_id, event) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, "voice:#{room_id}", event)
  end

  defp track_participant(state, principal_id) do
    if Map.has_key?(state.participants, principal_id) do
      state
    else
      %{state | participants: Map.put(state.participants, principal_id, DateTime.utc_now())}
    end
  end

  defp emit_room_event(name, room_id, payload) do
    emit_event(name, :link, Map.put(payload, :room_id, room_id))
  end

  defp emit_intent_event(name, room_id, payload) do
    emit_event(name, :flow, Map.put(payload, :room_id, room_id))
  end

  defp emit_event(name, source, payload) do
    case Event.new(%{
           name: name,
           type: String.to_atom(String.replace(name, ".", "_")),
           source: source,
           payload: payload,
           meta: %{reliability: :transient}
         }) do
      {:ok, event} ->
        Task.start(fn ->
          case EventBus.publish_event(event) do
            {:ok, _} -> :ok
            {:error, reason} -> Logger.debug("[VoicePipeline] Event publish failed: #{inspect(reason)}")
          end
        end)

      {:error, reason} ->
        Logger.warning("[VoicePipeline] Failed to create event #{name}: #{inspect(reason)}")
    end
  end

  @doc """
  MVP intent detection from transcript text.

  Looks for simple command patterns and emits `voice.intent.detected` events.
  Future: Integrate with ThunderCrown AI for richer NLU.
  """
  defp maybe_detect_intent(room_id, principal_id, text) do
    text_lower = String.downcase(text)

    intent =
      cond do
        String.contains?(text_lower, ["hey thunderline", "ok thunderline", "thunderline"]) ->
          {:wake_word, extract_command(text_lower)}

        String.contains?(text_lower, ["mute", "unmute"]) ->
          {:audio_control, if(String.contains?(text_lower, "unmute"), do: :unmute, else: :mute)}

        String.contains?(text_lower, ["start recording", "stop recording"]) ->
          {:recording, if(String.contains?(text_lower, "stop"), do: :stop, else: :start)}

        String.contains?(text_lower, ["leave", "disconnect", "hang up"]) ->
          {:navigation, :leave}

        true ->
          nil
      end

    if intent do
      {intent_type, intent_action} = intent

      emit_event("voice.intent.detected", :flow, %{
        room_id: room_id,
        principal_id: principal_id,
        intent_type: intent_type,
        intent_action: intent_action,
        raw_text: text,
        confidence: 0.8,
        detected_at: DateTime.utc_now()
      })

      :telemetry.execute(
        [:thunderline, :link, :voice, :intent_detected],
        %{count: 1},
        %{room_id: room_id, intent_type: intent_type}
      )
    end
  end

  defp extract_command(text) do
    # Remove wake word and get the rest
    text
    |> String.replace(~r/(hey |ok )?thunderline\s*/, "")
    |> String.trim()
  end
end
