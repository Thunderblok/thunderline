defmodule Thunderline.Thundergate.MigrationRunner do
  @moduledoc """
  Backwards-compatible wrapper around `Thunderline.Thunderblock.MigrationRunner`.

  Thundergate is no longer permitted to touch the Repo directly; prefer using the
  Thunderblock runner in supervision trees or boot scripts.
  """

  @deprecated "Use Thunderline.Thunderblock.MigrationRunner instead"
  def child_spec(arg), do: Thunderline.Thunderblock.MigrationRunner.child_spec(arg)

  @deprecated "Use Thunderline.Thunderblock.MigrationRunner instead"
  def start_link(arg), do: Thunderline.Thunderblock.MigrationRunner.start_link(arg)

  @deprecated "Use Thunderline.Thunderblock.MigrationRunner instead"
  def run, do: Thunderline.Thunderblock.MigrationRunner.run()
end
