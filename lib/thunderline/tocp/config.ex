defmodule Thunderline.TOCP.Config do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Config`.
  This module remains as a shim to avoid breaking existing code during migration.
  """

  defdelegate get, to: Thunderline.Thunderlink.Transport.Config
  defdelegate reload, to: Thunderline.Thunderlink.Transport.Config
  defdelegate get_in_path(path), to: Thunderline.Thunderlink.Transport.Config
end
