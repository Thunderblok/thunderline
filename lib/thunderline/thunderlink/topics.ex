defmodule Thunderline.Thunderlink.Topics do
  @moduledoc """
  Central PubSub topic helpers for Thunderlink (communications) domain.

  Replaces scattered literal topic strings. Future changes (tenant scoping,
  versioning, deprecation of legacy prefixes) concentrate here.

  Legacy prefix found in code: "thunderblock:".
  Canonical new prefix:      "thunderline".
  """

  @base "thunderline"

  # Channel topics
  def channel_base(channel_id), do: base(["channels", channel_id])
  def channel_messages(channel_id), do: channel_base(channel_id) <> ":messages"
  def channel_reactions(channel_id), do: channel_base(channel_id) <> ":reactions"
  def channel_presence(channel_id), do: channel_base(channel_id) <> ":presence"

  # Community topics
  def community_base(community_id), do: base(["communities", community_id])
  def community_messages(community_id), do: community_base(community_id) <> ":messages"
  def community_channels(community_id), do: community_base(community_id) <> ":channels"

  # Global presence aggregation
  def presence_global, do: base(["presence", "global"])

  # Internal helper
  defp base(segments) do
    Enum.join([@base | Enum.map(List.wrap(segments), &to_string/1)], ":")
  end
end
