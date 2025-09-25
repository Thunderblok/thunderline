defmodule Thunderline.Thunderflow.ErrorClass do
  @moduledoc "Structured error classification wrapper (initial scaffold)."
  @enforce_keys [:origin, :class]
  defstruct [:origin, :class, :severity, :visibility, :raw, :context]
end
