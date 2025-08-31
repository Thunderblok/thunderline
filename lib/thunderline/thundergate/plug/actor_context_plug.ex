defmodule Thunderline.Thundergate.Plug.ActorContextPlug do
  @moduledoc """
  Phoenix Plug that extracts and verifies a Gate-issued capability token (ActorContext).

  Expects header: Authorization: Bearer <token>

  On success assigns:
    conn.assigns.actor_ctx

  On failure assigns :actor_ctx => nil and continues (Phase 1: soft enforcement).
  Future WARHORSE phase: configurable hard fail with 401.
  """
  import Plug.Conn
  alias Thunderline.Thundergate.ActorContext
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, ctx} <- ActorContext.from_token(token) do
      assign(conn, :actor_ctx, ctx)
    else
      _ ->
        # Soft path: still assign nil so downstream can branch.
        assign(conn, :actor_ctx, nil)
    end
  end
end
