defmodule ThunderlineWeb.Plugs.LoadCurrentUser do
  @moduledoc """
  Populate `conn.assigns.current_user` from the session for regular (non-LiveView)
  HTTP requests. LiveViews use `ThunderlineWeb.Live.Auth` on_mount; plain forwarded
  routes like `/admin` (AshAdmin) only run the `:browser` + custom pipelines, so
  without this plug `current_user` is nil and `RequireRoles` immediately 403s.

  Strategy:
  1. Read the session key placed by AshAuthentication (`"current_user"`).
  2. Normalize into the minimal actor map used elsewhere (id/email/role/tenant_id).
  3. Default to a demo operator ONLY if no session user and DEMO_MODE is enabled.
  4. Do not create a demo user in production silently.

  This keeps concerns separate: assignment here, authorization decision remains in
  `ThunderlineWeb.Plugs.RequireRoles`.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # If already assigned (e.g. LiveView request upgrade), do nothing
    if conn.assigns[:current_user] do
      conn
    else
      maybe_assign_from_session(conn)
    end
  end

  defp maybe_assign_from_session(conn) do
    case get_session(conn, "current_user") do
      %{} = user_map -> assign(conn, :current_user, normalize(user_map, conn))
      _ -> maybe_demo(conn)
    end
  end

  defp maybe_demo(conn) do
    if System.get_env("DEMO_MODE") in ["1","true","TRUE"] do
      demo = %{id: UUID.uuid4(), role: :owner, tenant_id: "demo", email: "demo@local"}
      assign(conn, :current_user, demo)
    else
      conn
    end
  end

  defp normalize(map, conn) do
    role = map_role(map["role"] || map[:role]) || fallback_role(conn)
    %{
      id: map["id"] || map[:id] || UUID.uuid4(),
      email: map["email"] || map[:email],
      role: role,
      tenant_id: map["tenant_id"] || map[:tenant_id] || "default"
    }
  end

  defp map_role(r) when r in ["owner", :owner], do: :owner
  defp map_role(r) when r in ["steward", :steward], do: :steward
  defp map_role(r) when r in ["system", :system], do: :system
  defp map_role(_), do: nil

  defp fallback_role(_conn), do: :owner
end
