defmodule Thunderline.CA do
  @moduledoc """
  Stable call surface for CA parsing & future CA orchestration.

  High Command directive: keep UI/HTTP layers pointed here; internals may
  swap between direct parser calls & Ash actions without breaking callers.
  """

  alias Thunderline.CA.RuleParser

  @spec parse_rule(String.t()) :: {:ok, Thunderline.CA.RuleParser.t()} | {:error, term()}
  def parse_rule(line) when is_binary(line), do: RuleParser.parse(line)
end
