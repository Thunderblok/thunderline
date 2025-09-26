defmodule ThunderlineWeb.UserSocket do
  @moduledoc """
  Phoenix socket authenticated via AshAuthentication session tokens.

  The session payload is resolved from the connect params or the transport
  connect info and converted into a lightweight actor map for downstream
  channels.
  """

  use Phoenix.Socket
  require Logger

  alias AshAuthentication.Token
  alias ThunderlineWeb.Auth.Actor

  ## Channels
  channel "voice:*", ThunderlineWeb.VoiceChannel

  # In future: channel "chat:*", ThunderlineWeb.ChatChannel

  @impl true
  def connect(params, socket, connect_info) do
    with {:session, %{} = session} <- {:session, session_from_connect(params, connect_info)},
         {:actor, %{} = actor} <- {:actor, Actor.from_session(session, allow_demo?: true, default: :generate)} do
      {:ok,
       socket
       |> assign(:session, session)
       |> assign(:actor, actor)
       |> assign(:current_user, Map.get(session, "current_user") || Map.get(session, :current_user))}
    else
      {:session, _} -> :error
      {:actor, _} -> :error
    end
  end

  @impl true
  def id(%{assigns: %{actor: %{id: actor_id}}}) when is_binary(actor_id), do: "actors:#{actor_id}"
  def id(_socket), do: nil

  defp session_from_connect(params, connect_info) do
    token =
      params["token"] ||
        (connect_info
         |> Map.get(:x_headers, [])
         |> Enum.find_value(fn {k, v} -> if String.downcase(k) == "authorization", do: v end)
         |> maybe_strip_bearer())

    case {token, Map.get(connect_info, :session)} do
      {token, _} when is_binary(token) ->
        case verify_token(token) do
          {:ok, session} -> session
          _ -> Map.get(connect_info, :session, %{})
        end

      {_, session} when is_map(session) -> session
      _ -> %{}
    end
  end

  defp verify_token(token), do: Token.verify(Thunderline.Thundergate, token)

  defp maybe_strip_bearer("Bearer " <> token), do: token
  defp maybe_strip_bearer("bearer " <> token), do: token
  defp maybe_strip_bearer(token), do: token
end
