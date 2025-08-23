defmodule ThunderlineWeb.UserSocket do
  use Phoenix.Socket
  require Logger

  ## Channels
  channel "voice:*", ThunderlineWeb.VoiceChannel

  # In future: channel "chat:*", ThunderlineWeb.ChatChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # TODO: tie into AshAuthentication session token -> assign current_user/principal_id
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
