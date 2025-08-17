defmodule Thunderline.ML.Cerebros.Data.TabularDataset do
  @moduledoc "Deprecated alias for Thunderline.Thunderbolt.Cerebros.Data.TabularDataset"
  @deprecated "Use Thunderline.Thunderbolt.Cerebros.Data.TabularDataset instead"
  def new(rows, features, target), do: Thunderline.Thunderbolt.Cerebros.Data.TabularDataset.new(rows, features, target)
end
