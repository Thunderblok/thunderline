defmodule ThunderlineWeb.PageController do
  use ThunderlineWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
