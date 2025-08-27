defmodule Thunderline.Thunderwatch.Manager do
  @moduledoc """
  DEPRECATED shim – Thunderwatch has moved under `Thundergate.Thunderwatch.Manager`.
  This module will be removed after Q4 2025. Update imports/aliases.
  """
  @deprecated "Use Thundergate.Thunderwatch.Manager instead"
  defdelegate start_link(opts \\ []), to: Thundergate.Thunderwatch.Manager
  defdelegate subscribe(), to: Thundergate.Thunderwatch.Manager
  defdelegate current_seq(), to: Thundergate.Thunderwatch.Manager
  defdelegate snapshot(), to: Thundergate.Thunderwatch.Manager
  defdelegate changes_since(seq), to: Thundergate.Thunderwatch.Manager
  defdelegate rescan(), to: Thundergate.Thunderwatch.Manager
end
