defmodule Thunderline.Thunderbolt.Changes.DeleteInMap do
  @moduledoc "Delete a key from a map attribute in the changeset."
  use Ash.Resource.Change
  def change(changeset, opts, _ctx) do
    attr = Keyword.fetch!(opts, :attribute)
    key = Keyword.fetch!(opts, :key)
    current = Map.get(changeset.attributes, attr)
    if is_map(current) and Map.has_key?(current, key) do
      updated = Map.delete(current, key)
      %{changeset | attributes: Map.put(changeset.attributes, attr, updated)}
    else
      changeset
    end
  end
end
