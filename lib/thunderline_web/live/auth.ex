defmodule ThunderlineWeb.Live.Auth do
  @moduledoc """
  Unified LiveView on_mount hook to:
  * Pull the authenticated user (placed in the session by AshAuthentication) into assigns
  * Ensure `:current_user` assign always exists
  * Set the Ash actor for authorization/policy evaluation

  Included in `live_session :default, on_mount: [AshAuthentication.Phoenix.LiveSession, ThunderlineWeb.Live.Auth]`.
  We accept any tag (`_stage`) so it works whether passed as a bare module or with a stage tuple.
  """
  # We use Phoenix.Component.assign/2|3 (re-exported by Phoenix.Component)
  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Thunderline.Thundergate.Resources.User

  # Callback signature: on_mount(stage, params, session, socket)
  def on_mount(_stage, _params, session, socket) do
    user =
      case Map.get(session, "current_user") do
        %User{} = user -> user
        _ -> Map.get(socket.assigns, :current_user)
      end

    socket =
      socket
      |> assign(:current_user, user)
      |> maybe_set_ash_actor(user)

    {:cont, socket}
  end

  defp maybe_set_ash_actor(socket, %User{} = user) do
    Ash.set_actor(user)
    socket
  end

  defp maybe_set_ash_actor(socket, _), do: socket
end
