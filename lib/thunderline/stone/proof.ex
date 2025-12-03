defmodule Thunderline.Stone.Proof do
  @moduledoc """
  Stone Proof - Cryptographic policy proof generation and verification.

  Stubbed module for HC micro-sprint. Implements minimal proof verification
  for governance gates.

  Future: Proper cryptographic proofs with verifiable policy execution.
  """

  @type proof_map :: %{
          subject: map(),
          decision: :allow | :deny,
          rationale: String.t(),
          timestamp: DateTime.t(),
          signature: binary() | nil
        }

  @doc """
  Check if an action is allowed given the event context.

  Currently permissive - returns true for most actions.
  """
  @spec allow?(atom(), map()) :: boolean()
  def allow?(:trial_start, ev) do
    # Basic check: must have dataset_ref
    has_dataset =
      not is_nil(get_in(ev, [:payload, :dataset_ref]) || get_in(ev, ["payload", "dataset_ref"]))

    has_dataset
  end

  def allow?(_action, _ev), do: true

  @doc """
  Issue a proof for a decision.

  Returns a proof map documenting the decision and rationale.
  """
  @spec issue(map(), :allow | :deny, String.t()) :: proof_map()
  def issue(subject, decision, rationale) do
    %{
      subject: subject,
      decision: decision,
      rationale: rationale,
      timestamp: DateTime.utc_now(),
      signature: nil
    }
  end
end
