defmodule Thunderline.Thundergate.Authentication.MagicLinkSender do
  @moduledoc """
  Simple magic link sender for AshAuthentication.

  Currently logs the generated link token. Plug in a Swoosh-based delivery
  mechanism when SMTP or another channel is available.
  """

  use AshAuthentication.Sender

  require Logger

  @impl true
  def send(recipient, token, _opts) do
    Logger.info("[magic_link] sending token to #{inspect(recipient)}: #{inspect(token)}")
    :ok
  end
end
