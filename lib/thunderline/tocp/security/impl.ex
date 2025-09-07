defmodule Thunderline.TOCP.Security.Impl do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Security.Impl`.
  Shim delegating to Thunderlink implementation.
  """
  defdelegate sign(key_id, payload), to: Thunderline.Thunderlink.Transport.Security.Impl
  defdelegate verify(key_id, payload, sig), to: Thunderline.Thunderlink.Transport.Security.Impl
  defdelegate replay_seen?(key_id, mid, ts_ms), to: Thunderline.Thunderlink.Transport.Security.Impl
  defdelegate ensure_table(), to: Thunderline.Thunderlink.Transport.Security.Impl
  defdelegate prune_expired(), to: Thunderline.Thunderlink.Transport.Security.Impl
  defdelegate system_time_ms(), to: Thunderline.Thunderlink.Transport.Security.Impl
end
