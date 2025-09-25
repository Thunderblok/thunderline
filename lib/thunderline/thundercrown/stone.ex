defmodule Thunderline.Thundercrown.Stone do
  @moduledoc """
  Governance-facing Stone integration.

  Provides a single entrypoint to gate actions using Stone proofs and emit a
  canonical verdict event for observability.

  Contract:
    - input: action :: atom(), ev :: map() | %Thunderline.Event{}
    - output: {:allow | :deny, proof_map}
    - side-effects: telemetry + event publish (system.crown.stone.verdict)
  """
  require Logger
  alias Thunderline.Stone.Proof
  alias Thunderline.Event

  @spec stone(atom(), map() | Event.t()) :: {:allow | :deny, map()}
  def stone(action, ev) when is_atom(action) do
    start = System.monotonic_time()
    allowed? = Proof.allow?(action, normalize_ev(ev))
    decision = if allowed?, do: :allow, else: :deny
    rationale = rationale(action, allowed?, ev)

    subject = %{action: action, context: shrink_subject(ev)}
    proof = Proof.issue(subject, decision, rationale)

    emit_verdict_event(action, decision, rationale, proof)

    :telemetry.execute([
      :thunderline, :stone, :verdict
    ], %{duration: System.monotonic_time() - start}, %{
      action: action,
      decision: decision
    })

    {decision, proof}
  end

  # --- helpers --------------------------------------------------------------
  defp normalize_ev(%Event{} = ev), do: %{name: ev.name, payload: ev.payload, meta: ev.meta}
  defp normalize_ev(%{} = map), do: map
  defp normalize_ev(other), do: %{payload: other}

  defp shrink_subject(%Event{} = ev), do: %{name: ev.name, payload: ev.payload}
  defp shrink_subject(%{payload: p} = _ev), do: %{payload: p}
  defp shrink_subject(other) when is_map(other), do: Map.take(other, [:payload, :name])
  defp shrink_subject(other), do: %{payload: other}

  defp rationale(:trial_start, true, _ev), do: "dataset present and budget acceptable"
  defp rationale(:trial_start, false, ev) do
    has_dataset = not is_nil(get_in(ev, [:payload, :dataset_ref]) || get_in(ev, ["payload", "dataset_ref"]))
    if has_dataset, do: "budget constraint failed", else: "dataset_ref missing"
  end
  defp rationale(_action, true, _ev), do: "policy condition satisfied"
  defp rationale(_action, false, _ev), do: "policy condition not satisfied"

  defp emit_verdict_event(action, decision, rationale, proof) do
    attrs = %{
      name: "system.crown.stone.verdict",
      source: :crown,
      payload: %{
        action: action,
        decision: decision,
        rationale: rationale,
        proof: proof
      },
      meta: %{pipeline: :realtime},
      priority: :normal
    }

    case Event.new(attrs) do
      {:ok, ev} ->
        case Thunderline.EventBus.publish_event(ev) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("[Stone] failed to publish verdict event: #{inspect(reason)}")
        end
      {:error, errs} ->
        Logger.warning("[Stone] failed to build verdict event: #{inspect(errs)}")
    end
  end
end
