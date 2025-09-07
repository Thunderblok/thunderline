defmodule Thunderline.TOCP.Admission do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Admission`.
  Shim delegating to Thunderlink implementation.
  """
  @spec valid?(binary() | nil, keyword()) :: boolean()
  defdelegate valid?(token, opts), to: Thunderline.Thunderlink.Transport.Admission
  defdelegate extract(map), to: Thunderline.Thunderlink.Transport.Admission
end
