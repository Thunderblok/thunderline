defmodule Thunderline.ML.Cerebros.Adapter do
  @moduledoc "Deprecated alias for Thunderline.Thunderbolt.Cerebros.Adapter"
  @deprecated "Use Thunderline.Thunderbolt.Cerebros.Adapter instead"
  defdelegate run_search(opts), to: Thunderline.Thunderbolt.Cerebros.Adapter
  defdelegate load_artifact(path), to: Thunderline.Thunderbolt.Cerebros.Adapter
  defdelegate predict_with_artifact(path, samples), to: Thunderline.Thunderbolt.Cerebros.Adapter
end
