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
    require? = Application.get_env(:thunderline, :require_actor_ctx, false)
    case extract(conn) do
      {:ok, ctx} -> assign(conn, :actor_ctx, ctx)
      {:error, reason} ->
        conn = assign(conn, :actor_ctx, nil)
        if require? do
          conn
          |> send_resp(401, "unauthorized")
          |> halt()
        else
          conn
        end
    end
  end

  defp extract(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, ctx} <- ActorContext.from_token(token) do
      {:ok, ctx}
    else
      _ -> {:error, :missing_or_invalid}
    end
  end
end
