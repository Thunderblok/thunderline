defmodule Thunderline.Thunderbolt.Cerebros.Data.Dataset do
  @moduledoc false
  def info(%{features: feats, target: target}) do
    %{task: :regression, input_shape: {length(feats)}, target: target}
  end
end
