defmodule Thunderline.Bus do
  @moduledoc """
  Compatibility shim around ThunderFlow EventBus.

  Preferred usage is `Thunderline.EventBus` (under ThunderFlow) for all
  cross-domain/evented workflows. This module keeps the legacy simple
  PubSub topics & tuple payloads for UI/processes already consuming them,
  and additionally forwards a normalized event into the ThunderFlow
  pipelines to avoid duplicating bus infrastructure.

  Status: DEPRECATED shim for migration. New code should call
  `Thunderline.EventBus` directly.
  """

  alias Thunderline.EventBus, as: FlowBus

  @token_topic  "tokens"
  @event_topic  "events"
  @output_topic "outputs"
  @status_topic "status"

  # -- Subscriptions (compat) ---------------------------------------------------
  # Delegate to EventBus.subscribe to ensure a single place manages PubSub
  def subscribe_tokens,  do: FlowBus.subscribe(@token_topic)
  def subscribe_events,  do: FlowBus.subscribe(@event_topic)
  def subscribe_outputs, do: FlowBus.subscribe(@output_topic)
  def subscribe_status,  do: FlowBus.subscribe(@status_topic)

  # -- Broadcasts (compat + forward into ThunderFlow) ---------------------------
  # Maintain legacy tuple messages for LiveView/UI consumers, while also sending
  # a normalized event through the canonical EventBus so Broadway/Mnesia pipelines
  # see the same signal.

  def broadcast_token(tok) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, @token_topic, {:token, tok})
    safe_forward(:ui_token, %{token: tok, topic: @token_topic})
    :ok
  end

  def broadcast_event(evt) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, @event_topic, {:event, evt})
    payload =
      cond do
        is_map(evt) -> Map.put_new(evt, :topic, @event_topic)
        true -> %{data: evt, topic: @event_topic}
      end

    safe_forward(:ui_event, payload)
    :ok
  end

  def broadcast_output(out) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, @output_topic, {:output, out})
    payload = if is_map(out), do: Map.put_new(out, :topic, @output_topic), else: %{data: out, topic: @output_topic}
    safe_forward(:ui_output, payload)
    :ok
  end

  def broadcast_status(map) when is_map(map) do
    Phoenix.PubSub.broadcast(Thunderline.PubSub, @status_topic, {:status, Map.put_new(map, :ts, System.system_time(:millisecond))})
    # Forward to realtime pipeline for observability/dashboards
    safe_forward(:system_alert, Map.merge(map, %{topic: @status_topic}))
    :ok
  end

  # -- Minimal ETS init kept for compatibility ----------------------------------
  def init_tables do
    for t <- [:daisy_memory, :daisy_lease] do
      case :ets.whereis(t) do
        :undefined -> :ets.new(t, [:set, :public, :named_table])
        _ -> :ok
      end
    end
  end

  # -- Internal -----------------------------------------------------------------
  defp safe_forward(event_type, payload) when is_atom(event_type) and is_map(payload) do
    try do
      FlowBus.emit_realtime(event_type, payload)
    rescue
      _ -> :ok
    end
  end
end
