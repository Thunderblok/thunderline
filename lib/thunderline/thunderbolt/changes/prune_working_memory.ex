defmodule Thunderline.Thunderbolt.Changes.PruneWorkingMemory do
  @moduledoc "Canonical domain version of PruneWorkingMemory."
  use Ash.Resource.Change

  def change(changeset, opts, _ctx) do
    path = Keyword.get(opts, :path, [])
    max = Keyword.get(opts, :max, 100)

    case get_in(changeset.attributes, path) do
      list when is_list(list) and length(list) > max ->
        trimmed = Enum.take(list, max)
        put_in(changeset.attributes, path, trimmed)

      _ ->
        changeset
    end
  end
end
