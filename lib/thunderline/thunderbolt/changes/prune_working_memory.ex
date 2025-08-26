defmodule Thunderline.Thunderbolt.Changes.PruneWorkingMemory do
  @moduledoc "Canonical domain version of PruneWorkingMemory (migrated from Thunderline.Changes.PruneWorkingMemory)."
  use Ash.Resource.Change
  def change(changeset, opts, ctx), do: Thunderline.Changes.PruneWorkingMemory.change(changeset, opts, ctx)
end
