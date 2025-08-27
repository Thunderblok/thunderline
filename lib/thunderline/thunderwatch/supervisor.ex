defmodule Thunderline.Thunderwatch.Supervisor do
  @moduledoc """
  DEPRECATED shim – use `Thundergate.Thunderwatch.Supervisor`.
  """
  @deprecated "Use Thundergate.Thunderwatch.Supervisor instead"
  def start_link(opts \\ []), do: Thundergate.Thunderwatch.Supervisor.start_link(opts)
end
