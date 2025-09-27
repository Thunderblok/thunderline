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
      {:ok, ctx} ->
        telemetry(:success, %{actor: ctx.actor_id, tenant: ctx.tenant})
        assign(conn, :actor_ctx, ctx)

      {:error, :missing} ->
        telemetry(:missing)
        maybe_halt(assign(conn, :actor_ctx, nil), require?)

      {:error, :expired} ->
        telemetry(:expired)
        maybe_halt(assign(conn, :actor_ctx, nil), require?)

      {:error, _} ->
        telemetry(:deny)
        maybe_halt(assign(conn, :actor_ctx, nil), require?)
    end
  end

  defp telemetry(result, meta \\ %{}) do
    :telemetry.execute(
      [:thunderline, :gate, :auth, :result],
      %{count: 1},
      Map.put(meta, :result, result)
    )
  end

  defp maybe_halt(conn, false), do: conn

  defp maybe_halt(conn, true) do
    conn |> send_resp(401, "unauthorized") |> halt()
  end

  defp extract(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case ActorContext.from_token(token) do
          {:ok, ctx} -> {:ok, ctx}
          {:error, :expired} -> {:error, :expired}
          {:error, :invalid_signature} -> {:error, :invalid}
          {:error, :decode_failed} -> {:error, :invalid}
          {:error, :bad_payload} -> {:error, :invalid}
          {:error, _} -> {:error, :invalid}
        end

      [] ->
        {:error, :missing}

      _ ->
        {:error, :invalid}
    end
  end
end
