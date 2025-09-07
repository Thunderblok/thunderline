defmodule Thunderline.CA.RuleParser do
  @moduledoc "Thin alias to canonical parser under Thunderbolt domain."
  alias Thunderline.Thunderbolt.CA.RuleParser, as: Impl
  defdelegate parse(line), to: Impl
  @type t :: %Impl{born: [integer()], survive: [integer()], rate_hz: integer(), seed: String.t() | nil, zone: String.t() | nil}
end
