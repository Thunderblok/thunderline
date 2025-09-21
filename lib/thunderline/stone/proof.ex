defmodule Thunderline.Stone.Proof do
  @moduledoc """
  Stone: minimal proof issuance for trial start gating.
  """
  require Logger

  @type decision :: :allow | :deny
  @type t :: %{subject: term(), decision: decision(), rationale: String.t(), issued_at: DateTime.t()}

  @spec issue(term(), decision(), String.t()) :: t()
  def issue(subject, decision, rationale) when decision in [:allow, :deny] do
    proof = %{subject: subject, decision: decision, rationale: rationale, issued_at: DateTime.utc_now()}
    :telemetry.execute([:stone, :proof, :emitted], %{count: 1}, %{decision: decision})
    # Future: persist proof (Ash resource) + emit event via Event bus
    proof
  end

  @spec allow?(atom(), map()) :: boolean()
  def allow?(:trial_start, %{payload: p}) do
    dataset_ok? = not is_nil(p[:dataset_ref] || p["dataset_ref"]) # placeholder validation
    budget_ok? = true
    dataset_ok? and budget_ok?
  end
  def allow?(_action, _ev), do: false
end
