defmodule Thunderline.ML.Cerebros.Artifacts do
  @moduledoc "Deprecated alias for Thunderline.Thunderbolt.Cerebros.Artifacts"
  @deprecated "Use Thunderline.Thunderbolt.Cerebros.Artifacts instead"
  defdelegate load(path), to: Thunderline.Thunderbolt.Cerebros.Artifacts
  defdelegate predict_stub(a, samples), to: Thunderline.Thunderbolt.Cerebros.Artifacts
  defdelegate persist(a), to: Thunderline.Thunderbolt.Cerebros.Artifacts
end
