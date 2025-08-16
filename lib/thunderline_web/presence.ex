defmodule ThunderlineWeb.Presence do
  @moduledoc """
  Phoenix Presence for tracking realtime user/session state.

  Topics:
    - #{Thunderline.Thunderlink.Topics.presence_global()} (all users)
    - #{Thunderline.Thunderlink.Topics.channel_presence("<channel_id>")} (per-channel)

  Meta kept intentionally lightweight. For richer data perform follow-up fetches.
  """
  use Phoenix.Presence,
    otp_app: :thunderline,
    pubsub_server: Thunderline.PubSub

  alias Thunderline.Thunderlink.Topics

  @spec track_channel(pid, term, term, map) :: {:ok, term} | {:error, term}
  def track_channel(pid, channel_id, user_id, meta \\ %{}) do
    Phoenix.Presence.track(
      pid,
      Topics.channel_presence(channel_id),
      user_id,
      Map.merge(%{online_at: System.system_time(:second)}, meta)
    )
  end

  @spec track_global(pid, term, map) :: {:ok, term} | {:error, term}
  def track_global(pid, user_id, meta \\ %{}) do
    Phoenix.Presence.track(
      pid,
      Topics.presence_global(),
      user_id,
      Map.merge(%{online_at: System.system_time(:second)}, meta)
    )
  end
end
