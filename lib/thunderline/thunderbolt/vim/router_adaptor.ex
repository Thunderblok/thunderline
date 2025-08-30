defmodule Thunderline.Thunderbolt.VIM.RouterAdaptor do
  @moduledoc "Canonical VIM RouterAdaptor under Thunderbolt; delegates for now."
  defdelegate build_problem(args), to: Thunderline.VIM.RouterAdaptor
end
