defmodule Thunderline.Thunderbolt.Changes.ApplyTickResult do
  @moduledoc "Canonical domain version of ApplyTickResult (migrated from Thunderline.Changes.ApplyTickResult)."
  use Ash.Resource.Change

  def change(changeset, opts, ctx),
    do: Thunderline.Changes.ApplyTickResult.change(changeset, opts, ctx)
end
