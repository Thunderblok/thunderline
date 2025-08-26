defmodule Thunderline.Thunderbolt.Changes.PutInMap do
  @moduledoc "Canonical domain version of PutInMap (migrated from Thunderline.Changes.PutInMap)."
  use Ash.Resource.Change
  def change(changeset, opts, ctx), do: Thunderline.Changes.PutInMap.change(changeset, opts, ctx)
end
