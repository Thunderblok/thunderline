defmodule Thunderline.Support.Backoff do
  @moduledoc """
  DEPRECATED shim. Moved to Thunderline.Thunderflow.Support.Backoff.

  This module remains temporarily to avoid breaking any lingering references.
  It delegates to the new domain-scoped implementation. Prefer updating
  callers to use `Thunderline.Thunderflow.Support.Backoff` directly, then
  remove this file.
  """
  @deprecated "Use Thunderline.Thunderflow.Support.Backoff instead"

  defdelegate exp(attempt), to: Thunderline.Thunderflow.Support.Backoff
  defdelegate linear(attempt, step_ms \\ 5_000), to: Thunderline.Thunderflow.Support.Backoff
  defdelegate jitter(delay_ms), to: Thunderline.Thunderflow.Support.Backoff
  defdelegate config(), to: Thunderline.Thunderflow.Support.Backoff
end
