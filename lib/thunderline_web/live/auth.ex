defmodule ThunderlineWeb.Live.Auth do
  @moduledoc """
  Unified LiveView on_mount hook to:
  * Pull the authenticated user (placed in the session by AshAuthentication) into assigns
  * Ensure `:current_user` assign always exists
  * Set the Ash actor for authorization/policy evaluation

  Included in `live_session :default, on_mount: [AshAuthentication.Phoenix.LiveSession, ThunderlineWeb.Live.Auth]`.
  We accept any tag (`_stage`) so it works whether passed as a bare module or with a stage tuple.
  """
  # Import assign/2|3 from Phoenix.Component (works in LiveView on_mount hooks)
  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Thunderline.Thundergate.Resources.User

  # Callback signature: on_mount(stage, params, session, socket)
  def on_mount(_stage, _params, session, socket) do
    user =
      case Map.get(session, "current_user") do
        %User{} = user -> user
        %{} = map -> map
        _ -> Map.get(socket.assigns, :current_user)
      end

    actor = ensure_actor(user, session)

    socket =
      socket
      |> assign(:current_user, actor)
      |> maybe_set_ash_actor(actor)

    {:cont, socket}
  end

  defp ensure_actor(%User{} = user, session) do
    %{
      id: user.id,
      email: user.email,
      role: session_role(session) || :owner,
      tenant_id: session_tenant(session) || "demo"
    }
  end

  defp ensure_actor(%{} = map, session) do
    %{
      id: Map.get(map, :id) || Map.get(map, "id") || UUID.uuid4(),
      email: Map.get(map, :email) || Map.get(map, "email"),
      role: Map.get(map, :role) || Map.get(map, "role") || session_role(session) || :owner,
      tenant_id: Map.get(map, :tenant_id) || Map.get(map, "tenant_id") || session_tenant(session) || "demo"
    }
  end

  defp ensure_actor(_nil, session) do
    %{
      id: UUID.uuid4(),
      name: "Thunder Operator",
      role: session_role(session) || :owner,
      tenant_id: session_tenant(session) || "demo"
    }
  end

  defp session_role(session) do
    case Map.get(session, "role") || Map.get(session, :role) do
      r when r in ["owner", :owner] -> :owner
      r when r in ["steward", :steward] -> :steward
      r when r in ["system", :system] -> :system
      _ -> nil
    end
  end

  defp session_tenant(session) do
    Map.get(session, "tenant_id") || Map.get(session, :tenant_id)
  end

  defp maybe_set_ash_actor(socket, actor) when is_map(actor) do
    Ash.set_actor(actor)
    socket
  end

  defp maybe_set_ash_actor(socket, _), do: socket
end
