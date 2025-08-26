defmodule Thunderline.Thunderbolt.Changes.RunNodeLogic do
  @moduledoc "Canonical domain version of RunNodeLogic (migrated from Thunderline.Changes.RunNodeLogic)."
  use Ash.Resource.Change
  def change(changeset, opts, ctx), do: Thunderline.Changes.RunNodeLogic.change(changeset, opts, ctx)
end
