defmodule Thunderline.Thunderbolt.Changes.ApplyTickResult do
  @moduledoc "Apply tick result data to the changeset - merges tick outcome into state."
  use Ash.Resource.Change

  def change(changeset, opts, _ctx) do
    tick_result_arg = Keyword.get(opts, :argument, :tick_result)

    case Ash.Changeset.get_argument(changeset, tick_result_arg) do
      nil ->
        changeset

      tick_result when is_map(tick_result) ->
        # Apply tick result fields to changeset if they exist
        changeset
        |> maybe_apply_field(:energy, tick_result)
        |> maybe_apply_field(:tick_count, tick_result)
        |> maybe_apply_field(:state, tick_result)
        |> maybe_apply_field(:metadata, tick_result)

      _ ->
        changeset
    end
  end

  defp maybe_apply_field(changeset, field, tick_result) do
    case Map.get(tick_result, field) || Map.get(tick_result, to_string(field)) do
      nil -> changeset
      value -> Ash.Changeset.change_attribute(changeset, field, value)
    end
  end
end
