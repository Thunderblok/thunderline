defmodule Thunderline.Thunderbolt.Cerebros.Data.TabularDataset do
  @moduledoc false
  defstruct [:rows, :features, :target]
  @type t :: %__MODULE__{rows: [map()], features: [atom()], target: atom()}
  def new(rows, features, target), do: %__MODULE__{rows: rows, features: features, target: target}
end
