defmodule Thunderline.TOCP.Transport.UDP do
  @moduledoc """
  UDP transport scaffold (no socket bind yet).

  Week-1: Bind port, receive loop, pass frames to Router.
  Config: `:tocp_port` or `:tocp` -> :port (5088 default).
  """

  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    port = Application.get_env(:thunderline, :tocp)[:port] || 5088
    Logger.info("[TOCP][UDP] Scaffold init – would bind port #{port}")
    {:ok, %{port: port, socket: nil}}
  end
end
