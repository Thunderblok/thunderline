defmodule Thunderline.PubSub do
  @moduledoc false

  # Adapter wrapper used by Ash.Notifier.PubSub when resources configure
  # `pub_sub do
  #    module Thunderline.PubSub
  #    prefix "..."
  #    publish ...
  #  end`
  #
  # Ash will call `Thunderline.PubSub.broadcast(topic, event, payload)`.
  # This adapter forwards to Phoenix.PubSub while normalizing the payload
  # to the `{:published, topic, payload}` tuple shape that tests in this
  # codebase expect when subscribing directly to topics.

  @doc """
  Broadcast a notification to a given topic.

  - If called as `broadcast(topic, event, payload)` we forward to the
    Phoenix.PubSub process started under the name `Thunderline.PubSub`.
  - If called as `broadcast(pubsub_name, topic, payload)` (some callers)
    we forward using the provided pubsub name.
  In both cases we also publish an additional message to the base topic
  (topic without final ":id" component) to support subscribers that
  listen for the general event (e.g. "thunderbolt:chunk:created").
  """
  def broadcast(topic, _event, payload) when is_binary(topic) do
    # Broadcast to any active PubSub instances used by the application.
    # This is defensive: historically some modules use `Thunderline.PubSub`
    # while tests or other modules may subscribe to `Thunderline.PubSub`.
    for pubsub <- active_pubsubs() do
      safe_broadcast(pubsub, topic, payload)
      base = base_topic(topic)

      if base != topic do
        safe_broadcast(pubsub, base, payload)
      end
    end

    :ok
  end

  def broadcast(pubsub_name, topic, payload) when is_atom(pubsub_name) and is_binary(topic) do
    if Process.whereis(pubsub_name) do
      safe_broadcast(pubsub_name, topic, payload)

      base = base_topic(topic)

      if base != topic do
        safe_broadcast(pubsub_name, base, payload)
      end
    end

    :ok
  end

  defp safe_broadcast(pubsub, topic, payload) do
    try do
      Phoenix.PubSub.broadcast(pubsub, topic, {:published, topic, payload})
    rescue
      _ -> :ok
    end
  end

  def active_pubsubs do
    # Candidate names (support both legacy and current spellings)
    candidates = [Thunderline.PubSub, Thunderline.PubSub]

    candidates
    |> Enum.filter(&Process.whereis/1)
  end

  defp base_topic(topic) when is_binary(topic) do
    parts = String.split(topic, ":")

    case parts do
      [single] -> single
      parts ->
        # Reconstruct the topic without the final segment (the id)
        parts
        |> Enum.slice(0, length(parts) - 1)
        |> Enum.join(":")
    end
  end
end
