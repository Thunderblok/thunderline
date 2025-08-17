defmodule Thunderline.Support.CircuitBreaker do
  @moduledoc """
  DEPRECATED shim. CircuitBreaker moved to Thunderline.Thunderflow.Support.CircuitBreaker.

  Leave temporarily to prevent crashes from any stale references. Update
  supervisors & callers, then remove this file.
  """
  @deprecated "Use Thunderline.Thunderflow.Support.CircuitBreaker instead"

  defdelegate call(key, fun), to: Thunderline.Thunderflow.Support.CircuitBreaker
  defdelegate reset(key), to: Thunderline.Thunderflow.Support.CircuitBreaker
  defdelegate get_circuit_state(key), to: Thunderline.Thunderflow.Support.CircuitBreaker
  def start_link(opts \\ []), do: Thunderline.Thunderflow.Support.CircuitBreaker.start_link(opts)
end
