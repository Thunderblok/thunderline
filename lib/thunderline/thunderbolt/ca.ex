defmodule Thunderline.Thunderbolt.CA do
  @moduledoc """
  Stable call surface for CA parsing & future CA orchestration.

  High Command directive: keep UI/HTTP layers pointed here; internals may
  swap between direct parser calls & Ash actions without breaking callers.
  """

  alias Thunderline.Thunderbolt.CA.RuleParser

  @spec parse_rule(String.t()) :: {:ok, Thunderline.Thunderbolt.CA.RuleParser.t()} | {:error, term()}
  def parse_rule(line) when is_binary(line), do: RuleParser.parse(line)
end
