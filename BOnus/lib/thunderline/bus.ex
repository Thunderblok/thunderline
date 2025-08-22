defmodule Thunderline.Bus do
  @moduledoc """
  PubSub helpers for tokens/events/outputs/status + ETS init.
  """
  @token_topic  "tokens"
  @event_topic  "events"
  @output_topic "outputs"
  @status_topic "status"

  def subscribe_tokens,  do: Phoenix.PubSub.subscribe(Thunderline.PubSub, @token_topic)
  def subscribe_events,  do: Phoenix.PubSub.subscribe(Thunderline.PubSub, @event_topic)
  def subscribe_outputs, do: Phoenix.PubSub.subscribe(Thunderline.PubSub, @output_topic)
  def subscribe_status,  do: Phoenix.PubSub.subscribe(Thunderline.PubSub, @status_topic)

  def broadcast_token(tok),   do: Phoenix.PubSub.broadcast(Thunderline.PubSub, @token_topic, {:token, tok})
  def broadcast_event(evt),   do: Phoenix.PubSub.broadcast(Thunderline.PubSub, @event_topic, {:event, evt})
  def broadcast_output(out),  do: Phoenix.PubSub.broadcast(Thunderline.PubSub, @output_topic, {:output, out})
  def broadcast_status(map) when is_map(map),
    do: Phoenix.PubSub.broadcast(Thunderline.PubSub, @status_topic, {:status, Map.put_new(map, :ts, System.system_time(:millisecond))})

  def init_tables do
    for t <- [:daisy_memory, :daisy_lease] do
      case :ets.whereis(t) do
        :undefined -> :ets.new(t, [:set, :public, :named_table])
        _ -> :ok
      end
    end
  end
end
