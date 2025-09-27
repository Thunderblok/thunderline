defmodule Thunderline.Thunderflow.Support.ErrorKinds do
  @moduledoc "Categorization of errors for event pipeline logic (backoff, circuit breaker, routing)."
  @transient [:timeout, :overloaded, :rate_limited, :network_glitch]
  @permanent [:invalid_payload, :auth_failure, :not_found, :unsupported]
  def transient?(reason), do: reason in @transient
  def permanent?(reason), do: reason in @permanent
  def classify(%{__exception__: true, reason: r}), do: classify(r)
  def classify(%{__exception__: true} = e), do: map_exception(e)

  def classify(atom) when is_atom(atom) do
    cond do
      atom in @transient -> {:transient, atom}
      atom in @permanent -> {:permanent, atom}
      true -> {:unknown, atom}
    end
  end

  def classify(_), do: {:unknown, :generic}
  defp map_exception(%MatchError{}), do: {:permanent, :invalid_payload}
  defp map_exception(%FunctionClauseError{}), do: {:permanent, :invalid_payload}
  defp map_exception(%ArgumentError{}), do: {:permanent, :invalid_payload}

  defp map_exception(%RuntimeError{message: msg}) do
    cond do
      String.contains?(msg, ["timeout", "temporarily"]) -> {:transient, :timeout}
      String.contains?(msg, ["rate", "limit"]) -> {:transient, :rate_limited}
      true -> {:unknown, :runtime}
    end
  end

  defp map_exception(_), do: {:unknown, :exception}
end
