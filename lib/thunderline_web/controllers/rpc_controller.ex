defmodule ThunderlineWeb.RpcController do
  use ThunderlineWeb, :controller

  @otp_app :thunderline

  # Ensure actor/tenant are set on the connection when available.
  # Current user is assigned by ThunderlineWeb.Plugs.LoadCurrentUser in the :browser pipeline.
  def run(conn, params) do
    conn = maybe_set_actor_and_tenant(conn)
    result = AshTypescript.Rpc.run_action(@otp_app, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    conn = maybe_set_actor_and_tenant(conn)
    result = AshTypescript.Rpc.validate_action(@otp_app, conn, params)
    json(conn, result)
  end

  defp maybe_set_actor_and_tenant(conn) do
    conn
    |> maybe_set_actor()
    |> maybe_set_tenant()
  end

  defp maybe_set_actor(conn) do
    actor = conn.assigns[:current_user]

    if actor do
      Ash.PlugHelpers.set_actor(conn, actor)
    else
      conn
    end
  end

  defp maybe_set_tenant(conn) do
    case conn.assigns[:current_tenant] do
      nil -> conn
      tenant -> Ash.PlugHelpers.set_tenant(conn, tenant)
    end
  end
end
