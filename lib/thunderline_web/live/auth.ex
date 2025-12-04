defmodule ThunderlineWeb.Live.Auth do
  @moduledoc """
  Unified LiveView on_mount hook to:
  * Pull the authenticated user (placed in the session by AshAuthentication) into assigns
  * Ensure `:current_user` assign always exists
  * Set the Ash actor for authorization/policy evaluation

  Included in `live_session :default, on_mount: [AshAuthentication.Phoenix.LiveSession, ThunderlineWeb.Live.Auth]`.
  We accept any tag (`_stage`) so it works whether passed as a bare module or with a stage tuple.
  """
  # Import assign/3 from Phoenix.Component (works in LiveView on_mount hooks)
  import Phoenix.Component, only: [assign: 3]

  alias ThunderlineWeb.Auth.Actor

  # Callback signature: on_mount(stage, params, session, socket)
  def on_mount(_stage, _params, session, socket) do
    actor =
      session
      |> Map.put_new_lazy("current_user", fn -> Map.get(socket.assigns, :current_user) end)
      |> Actor.from_session(allow_demo?: true, default: :generate)

    socket =
      socket
      |> assign(:session, session)
      |> assign(:current_user, actor)
      # NOTE: Previously attempted to globally set an Ash actor with Ash.set_actor/1.
      # Ash 3.x no longer exposes that function (or it may be intentionally private),
      # and LiveView processes should instead pass actors explicitly when invoking
      # Ash actions/queries. We keep a hook point here for future per-process context
      # injection if needed.
      |> maybe_set_ash_actor(actor)

    {:cont, socket}
  end

  defp maybe_set_ash_actor(socket, _actor), do: socket
end
