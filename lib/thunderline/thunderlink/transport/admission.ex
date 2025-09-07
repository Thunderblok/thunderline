defmodule Thunderline.Thunderlink.Transport.Admission do
  @moduledoc """
  Admission token validation under Thunderlink Transport.
  """
  @spec valid?(binary() | nil, keyword()) :: boolean()
  def valid?(token, _opts) when is_binary(token), do: byte_size(token) >= 24
  def valid?(_nil, _opts), do: false

  @doc "Extract token from common maps."
  def extract(%{token: t}), do: t
  def extract(%{"token" => t}), do: t
  def extract(_), do: nil
end
