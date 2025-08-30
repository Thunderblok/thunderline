defmodule Thunderline.HTTP do
  @moduledoc "Thin Req wrapper with sensible defaults (timeouts, JSON). Prefer this client over :httpoison/:httpc."
  @default_opts [
    connect_options: [timeout: 5_000],
    receive_timeout: 15_000,
    retry: :safe_transient
  ]

  @spec request(keyword) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request(opts) when is_list(opts) do
    Req.request(Keyword.merge(@default_opts, opts))
  end

  @spec get(String.t(), keyword) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def get(url, opts \\ []), do: request([method: :get, url: url] ++ opts)

  @spec post(String.t(), any, keyword) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def post(url, body, opts \\ []), do: request([method: :post, url: url, json: body] ++ opts)
end
