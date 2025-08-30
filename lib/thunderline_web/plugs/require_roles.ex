defmodule ThunderlineWeb.Plugs.RequireRoles do
  @moduledoc "Plug that ensures the current user has one of the required roles. Integrate with ThunderGate policies."
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: Keyword.get(opts, :roles, [])

  @impl true
  def call(conn, roles) when is_list(roles) do
    case conn.assigns[:current_user] do
      %{role: role} ->
        if Enum.member?(roles, role) do
          conn
        else
          conn |> send_resp(403, "forbidden") |> halt()
        end

      _ ->
        conn |> send_resp(403, "forbidden") |> halt()
    end
  end
end
