defmodule Thunderline.Stone do
  @moduledoc """
  Stone - Root module for policy proofs and verification.

  Delegates to `Thunderline.Stone.Proof` for actual implementation.
  """

  defdelegate allow?(action, ev), to: Thunderline.Stone.Proof
  defdelegate issue(subject, decision, rationale), to: Thunderline.Stone.Proof
end
