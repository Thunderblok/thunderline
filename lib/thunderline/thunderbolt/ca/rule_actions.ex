defmodule Thunderline.Thunderbolt.CA.RuleActions do
  @moduledoc """
  Ash simple action integration for CA rule parsing so clients can submit rule
  lines via standard Ash API (GraphQL/JSON API layers later) and receive a parsed
  struct plus normalized event emission (already done in RuleParser).

  This is intentionally a lightweight wrapper; we don't persist rule lines yet.
  """
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults []

    action :parse_rule do
      returns :map
      argument :line, :string, allow_nil?: false

      run fn input, _context ->
        case Thunderline.Thunderbolt.CA.RuleParser.parse(input.arguments.line) do
          {:ok, rule} ->
            {:ok,
             %{
               born: rule.born,
               survive: rule.survive,
               rate_hz: rule.rate_hz,
               seed: rule.seed,
               zone: rule.zone
             }}

          {:error, err} ->
            {:error, to_string(err[:message] || "invalid rule line")}
        end
      end
    end
  end

  attributes do
    attribute :born, {:array, :integer}
    attribute :survive, {:array, :integer}
    attribute :rate_hz, :integer
    attribute :seed, :string
    attribute :zone, :string
  end
end
