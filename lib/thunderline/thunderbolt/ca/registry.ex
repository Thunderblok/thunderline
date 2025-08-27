defmodule Thunderline.Thunderbolt.CA.Registry do
  @moduledoc """
  Registry for active Cellular Automata runs.

  Uses unique keys with the run_id (string or atom) so we can look up
  the CA runner GenServer via `{:via, Registry, {__MODULE__, run_id}}`.
  """
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
