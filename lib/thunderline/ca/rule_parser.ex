defmodule Thunderline.CA.RuleParser do
  @moduledoc "DEPRECATED: use Thunderline.Thunderbolt.CA.RuleParser. Kept as shim during refactor."
  @deprecated "Use Thunderline.Thunderbolt.CA.RuleParser"
  def parse(str), do: Thunderline.Thunderbolt.CA.RuleParser.parse(str)
end
