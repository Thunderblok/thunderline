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

  alias ThunderlineWeb.Auth.Actor

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
    conn
    |> get_session()
    |> Actor.from_session(allow_demo?: true, default: :generate)
    |> maybe_assign(conn)
  end

  defp maybe_assign(nil, conn), do: conn

  defp maybe_assign(actor, conn) do
    conn
    |> assign(:current_user, actor)
    |> assign(:actor, actor)
  end
end
