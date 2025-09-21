defmodule Thunderline.Foundry.Blueprint do
  @moduledoc """
  Minimal blueprint representation for Foundry. Future: Ash resource.
  """
  @enforce_keys [:kind, :name, :spec]
  defstruct [:kind, :name, :spec, :labels]

  @type t :: %__MODULE__{kind: String.t(), name: String.t(), spec: map(), labels: map() | nil}

  def from_yaml(yaml) when is_binary(yaml) do
    case :yamerl_constr.string(yaml) do
      [doc] -> {:ok, to_struct(doc)}
      other -> {:error, {:invalid_yaml, other}}
    end
  rescue
    e -> {:error, {:yaml_error, e}}
  end

  defp to_struct(doc) do
    kind = get_in(doc, ["kind"]) || get_in(doc, [:kind]) || "Unknown"
    name = get_in(doc, ["metadata", "name"]) || get_in(doc, [:metadata, :name]) || "noname"
    labels = get_in(doc, ["metadata", "labels"]) || get_in(doc, [:metadata, :labels])
    %__MODULE__{kind: kind, name: name, labels: labels, spec: doc}
  end
end
