defmodule Thunderline.Thunderwatch.Manager do
  @moduledoc """
  Backwards-compatibility shim for the legacy Thunderwatch namespace.

  Thunderwatch moved into the Thundergate domain to align with our security and
  external-integration responsibilities. New code should reference
  `Thundergate.Thunderwatch.Manager` directly; existing callers may continue to
  use this module while migration completes.
  """

  @doc """
  Deprecated shim. Prefer `Thundergate.Thunderwatch.Manager.child_spec/1`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.child_spec/1"
  def child_spec(opts) do
    Thundergate.Thunderwatch.Manager.child_spec(opts)
  end

  @doc """
  See `Thundergate.Thunderwatch.Manager.start_link/1`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.start_link/1"
  def start_link(opts \\ []) do
    Thundergate.Thunderwatch.Manager.start_link(opts)
  end

  @doc """
  See `Thundergate.Thunderwatch.Manager.subscribe/0`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.subscribe/0"
  def subscribe do
    Thundergate.Thunderwatch.Manager.subscribe()
  end

  @doc """
  See `Thundergate.Thunderwatch.Manager.current_seq/0`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.current_seq/0"
  def current_seq do
    Thundergate.Thunderwatch.Manager.current_seq()
  end

  @doc """
  See `Thundergate.Thunderwatch.Manager.snapshot/0`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.snapshot/0"
  def snapshot do
    Thundergate.Thunderwatch.Manager.snapshot()
  end

  @doc """
  See `Thundergate.Thunderwatch.Manager.changes_since/1`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.changes_since/1"
  def changes_since(seq) do
    Thundergate.Thunderwatch.Manager.changes_since(seq)
  end

  @doc """
  See `Thundergate.Thunderwatch.Manager.rescan/0`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager.rescan/0"
  def rescan do
    Thundergate.Thunderwatch.Manager.rescan()
  end
end
