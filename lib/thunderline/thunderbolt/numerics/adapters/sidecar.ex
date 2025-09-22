defmodule Thunderline.Thunderbolt.Numerics.Adapters.Sidecar do
  @behaviour Thunderline.Thunderbolt.Numerics
  @moduledoc """
  HTTP sidecar adapter calling a Python FastAPI service.
  Configure :thunderline, :numerics_sidecar_url.

  Expects FP16 row-major binaries for A (m×k) and B (k×n), and returns FP16 row-major binary C (m×n).
  """

  @endpoint Application.compile_env(:thunderline, :numerics_sidecar_url, "http://localhost:8089")

  @impl true
  def gemm_fp16_acc32(a_bin, b_bin, opts) when is_binary(a_bin) and is_binary(b_bin) do
    m = Keyword.fetch!(opts, :m)
    n = Keyword.fetch!(opts, :n)
    k = Keyword.fetch!(opts, :k)

    payload = %{
      "m" => m,
      "n" => n,
      "k" => k,
      "a_base64" => Base.encode64(a_bin),
      "b_base64" => Base.encode64(b_bin)
    }

    with {:ok, resp} <- http_post("/gemm_fp16_acc32_bytes", payload),
         %{"ok" => true, "c_base64" => c_b64} <- resp do
      {:ok, Base.decode64!(c_b64)}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, {:sidecar_error, err}}
      {:error, reason} -> {:error, {:sidecar_request_failed, reason}}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  defp http_post(path, body) do
    url = @endpoint <> path
    headers = [{"content-type", "application/json"}]
    json = Jason.encode!(body)

    case :httpc.request(:post, {to_charlist(url), headers, ~c"application/json", json}, [], []) do
      {:ok, {{_http, 200, _}, _resp_headers, resp_body}} ->
        {:ok, Jason.decode!(to_string(resp_body))}

      {:ok, {{_http, status, _}, _resp_headers, resp_body}} ->
        {:error, {:http_error, status, to_string(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
