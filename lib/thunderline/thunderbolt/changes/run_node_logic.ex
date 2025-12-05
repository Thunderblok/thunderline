defmodule Thunderline.Thunderbolt.Changes.RunNodeLogic do
  @moduledoc "Execute node logic for behavior trees / workflow nodes."
  use Ash.Resource.Change

  def change(changeset, opts, _ctx) do
    node_field = Keyword.get(opts, :node_field, :node_type)
    input_field = Keyword.get(opts, :input_field, :input)
    output_field = Keyword.get(opts, :output_field, :output)

    node_type = Ash.Changeset.get_attribute(changeset, node_field)
    input = Ash.Changeset.get_attribute(changeset, input_field) || %{}

    # execute_node/2 currently always returns {:ok, _}
    {:ok, output} = execute_node(node_type, input)
    Ash.Changeset.change_attribute(changeset, output_field, output)
  end

  defp execute_node(nil, _input), do: {:ok, %{}}
  defp execute_node(_node_type, input), do: {:ok, input}
end
