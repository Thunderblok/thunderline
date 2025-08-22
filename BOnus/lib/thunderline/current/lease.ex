defmodule Thunderline.Current.Lease do
  @moduledoc """TTL lease for prewindow → commit handoff."""
  def make(inj, del, ttl_ms), do: %{inj: inj, del: del, ts: System.monotonic_time(:millisecond), ttl: ttl_ms}
  def expired?(%{ts: ts, ttl: ttl}), do: System.monotonic_time(:millisecond) - ts > ttl
end
