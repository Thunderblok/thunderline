defmodule Thunderline.TOCP.Security.Pruner do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Security.Pruner`.
  Shim delegating to Thunderlink implementation.
  """
  defdelegate start_link(opts), to: Thunderline.Thunderlink.Transport.Security.Pruner
end
