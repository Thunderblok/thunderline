defmodule Thunderline.ML.Cerebros.SimpleSearch do
  @moduledoc """
  DEPRECATED alias module. Use `Thunderline.Thunderbolt.Cerebros.SimpleSearch`.
  Will be removed after migration window.
  """
  @deprecated "Use Thunderline.Thunderbolt.Cerebros.SimpleSearch instead"
  defdelegate simple_search(opts), to: Thunderline.Thunderbolt.Cerebros.SimpleSearch
end
