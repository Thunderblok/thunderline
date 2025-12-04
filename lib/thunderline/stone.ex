defmodule Thunderline.Stone do
  @moduledoc """
  Stone - Root module for policy proofs and verification.

  Delegates to `Thunderline.Thundercrown.Proof` for actual implementation.
  """

  defdelegate allow?(action, ev), to: Thunderline.Thundercrown.Proof
  defdelegate issue(subject, decision, rationale), to: Thunderline.Thundercrown.Proof
end
