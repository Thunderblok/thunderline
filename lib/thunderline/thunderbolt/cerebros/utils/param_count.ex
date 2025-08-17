defmodule Thunderline.Thunderbolt.Cerebros.Utils.ParamCount do
  @moduledoc false
  def count(model) do
    params = Axon.get_parameters(model)
    total = Enum.reduce(params, 0, fn {_name, tensor}, acc -> acc + Nx.size(tensor) end)
    %{total: total}
  end
end
