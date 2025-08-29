defmodule Thunderline.TOCP.Admission do
  @moduledoc """
  Admission token validation stub.

  Validates join tokens for zone entry. MVP uses simple opaque bearer token
  pattern (random base64) & optional prefix. Future: macaroon / caveat checks.
  """
  require Logger

  @spec valid?(binary() | nil, keyword()) :: boolean()
  def valid?(token, _opts) when is_binary(token) do
    min = 24
    case byte_size(token) >= min do
      true -> true
      false -> false
    end
  end
  def valid?(_nil, _opts), do: false

  @doc "Extract token from a headers or meta map (placeholder)."
  def extract(%{token: t}), do: t
  def extract(%{"token" => t}), do: t
  def extract(_), do: nil
end
