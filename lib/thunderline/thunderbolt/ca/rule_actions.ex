defmodule Thunderline.Thunderbolt.CA.RuleActions do
  @moduledoc """
  Ash simple action integration for CA rule parsing so clients can submit rule
  lines via standard Ash API (GraphQL/JSON API layers later) and receive a parsed
  struct plus normalized event emission (already done in RuleParser).

  This is intentionally a lightweight wrapper; we don't persist rule lines yet.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :born, {:array, :integer}
    attribute :survive, {:array, :integer}
    attribute :rate_hz, :integer
    attribute :seed, :string
    attribute :zone, :string
  end

  actions do
    defaults []

    # Accepts a rule line string, returns parsed map representation.
    action :parse_rule, :map do
      argument :line, :string, allow_nil?: false
      run fn input, _ctx ->
        line = input.arguments.line
        case Thunderline.CA.RuleParser.parse(line) do
          {:ok, rule} -> {:ok, Map.from_struct(rule)}
          {:error, err} -> {:error, Ash.Error.Invalid.new(errors: [to_string(err[:message] || inspect(err))])}
        end
      end
    end
  end
end
