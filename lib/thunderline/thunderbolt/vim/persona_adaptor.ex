defmodule Thunderline.Thunderbolt.VIM.PersonaAdaptor do
  @moduledoc "Canonical VIM PersonaAdaptor under Thunderbolt; delegates for now."
  defdelegate build_problem(args), to: Thunderline.VIM.PersonaAdaptor
end
