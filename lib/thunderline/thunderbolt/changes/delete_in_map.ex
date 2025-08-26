defmodule Thunderline.Thunderbolt.Changes.DeleteInMap do
  @moduledoc "Canonical domain version of DeleteInMap (migrated from Thunderline.Changes.DeleteInMap)."
  use Ash.Resource.Change
  def change(changeset, opts, ctx), do: Thunderline.Changes.DeleteInMap.change(changeset, opts, ctx)
end
