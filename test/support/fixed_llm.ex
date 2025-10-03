defmodule Thunderline.Test.Support.FixedLLM do
  @moduledoc """
  Deprecated alias kept for older tests. Prefer
  `Thunderline.Thundercrown.LLM.FixedLLM` directly.
  """

  @deprecated "Use Thunderline.Thundercrown.LLM.FixedLLM instead"
  def new(opts \\ []), do: Thunderline.Thundercrown.LLM.FixedLLM.new(opts)

  @deprecated "Use Thunderline.Thundercrown.LLM.FixedLLM instead"
  defdelegate call(model, messages, tools),
    to: Thunderline.Thundercrown.LLM.FixedLLM

  @deprecated "Use Thunderline.Thundercrown.LLM.FixedLLM instead"
  defdelegate serialize_config(model),
    to: Thunderline.Thundercrown.LLM.FixedLLM

  @deprecated "Use Thunderline.Thundercrown.LLM.FixedLLM instead"
  defdelegate restore_from_map(map),
    to: Thunderline.Thundercrown.LLM.FixedLLM
end
