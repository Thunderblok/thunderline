defmodule Thunderline.Thunderbolt.Changes.RunNodeLogic do
  @moduledoc "Execute node logic for behavior trees / workflow nodes."
  use Ash.Resource.Change

  def change(changeset, opts, _ctx) do
    node_field = Keyword.get(opts, :node_field, :node_type)
    input_field = Keyword.get(opts, :input_field, :input)
    output_field = Keyword.get(opts, :output_field, :output)

    node_type = Ash.Changeset.get_attribute(changeset, node_field)
    input = Ash.Changeset.get_attribute(changeset, input_field) || %{}

    case execute_node(node_type, input) do
      {:ok, output} ->
        Ash.Changeset.change_attribute(changeset, output_field, output)

      {:error, _reason} ->
        changeset
    end
  end

  defp execute_node(nil, _input), do: {:ok, %{}}
  defp execute_node(_node_type, input), do: {:ok, input}
end
