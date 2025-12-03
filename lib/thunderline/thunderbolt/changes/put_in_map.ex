defmodule Thunderline.Thunderbolt.Changes.PutInMap do
  @moduledoc "Put a key-value into a map attribute in the changeset."
  use Ash.Resource.Change

  def change(changeset, opts, _ctx) do
    attr = Keyword.fetch!(opts, :attribute)
    key = Keyword.fetch!(opts, :key)
    value = Keyword.get(opts, :value)

    current = Ash.Changeset.get_attribute(changeset, attr) || %{}

    if is_map(current) do
      updated = Map.put(current, key, value)
      Ash.Changeset.change_attribute(changeset, attr, updated)
    else
      changeset
    end
  end
end
