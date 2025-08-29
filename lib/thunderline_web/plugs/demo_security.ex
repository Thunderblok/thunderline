defmodule ThunderlineWeb.Plugs.DemoSecurity do
  @moduledoc """
  Demo environment security hardening:

  * Optional Basic Auth (DEMO_BASIC_AUTH_USER/PASS)
  * Simple in-memory IP rate limiting (ETS bucket)
  * Security headers (CSP, X-Robots-Tag, Referrer-Policy)
  * Disallow indexing (noindex) unless DEMO_ALLOW_INDEX=1

  NOTE: This is intentionally lightweight. Replace with a more
  robust solution (Hammer/Redis) if demo traffic increases.
  """
  import Plug.Conn

  @behaviour Plug
  @table :thunderline_demo_rl

  @impl true
  def init(opts) do
    limit = Keyword.get(opts, :limit, 120)          # requests
    interval = Keyword.get(opts, :interval, 60_000) # ms window
    ensure_table()
    %{limit: limit, interval: interval}
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
      _ -> :ok
    end
  end

  @impl true
  def call(conn, %{limit: limit, interval: interval} = _opts) do
    conn
    |> basic_auth()
    |> rate_limit(limit, interval)
    |> put_resp_header("content-security-policy", csp())
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-robots-tag", robots())
  end

  defp basic_auth(conn) do
    user = System.get_env("DEMO_BASIC_AUTH_USER")
    pass = System.get_env("DEMO_BASIC_AUTH_PASS")
    if user && pass do
      with [auth] <- get_req_header(conn, "authorization"),
           true <- valid_basic?(auth, user, pass) do
        conn
      else
        _ ->
          conn
          |> put_resp_header("www-authenticate", "Basic realm=\"Thunderline Demo\"")
          |> send_resp(:unauthorized, "Authentication required")
          |> halt()
      end
    else
      conn
    end
  end

  defp valid_basic?("Basic " <> encoded, user, pass) do
    case Base.decode64(encoded) do
      {:ok, creds} -> creds == "#{user}:#{pass}"
      _ -> false
    end
  end
  defp valid_basic?(_, _, _), do: false

  defp rate_limit(conn, limit, interval) do
    {ip, _port} = conn.peer
    key = {ip, bucket(interval)}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})
    if count > limit do
      send_resp(conn, 429, "Rate limit exceeded") |> halt()
    else
      conn
    end
  end

  defp bucket(interval), do: System.system_time(:millisecond) |> div(interval)

  defp csp do
    "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "<>
      "style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss:;"
  end

  defp robots do
    if System.get_env("DEMO_ALLOW_INDEX") in ["1","true","TRUE"], do: "index,follow", else: "noindex,nofollow"
  end
end
