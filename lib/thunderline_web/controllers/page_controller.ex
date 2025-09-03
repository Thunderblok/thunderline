defmodule ThunderlineWeb.PageController do
  use ThunderlineWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def probe(conn, _params) do
    send_resp(conn, 200, "OK probe")
  end
end
