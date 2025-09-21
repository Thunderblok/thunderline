defmodule Thunderline.Foundry.FactoryRun do
  @moduledoc """
  Foundry: factory run executor. Emits telemetry for run lifecycle.
  """
  require Logger
  alias Thunderline.Foundry.Blueprint

  @spec run(Blueprint.t()) :: {:ok, map()} | {:error, term()}
  def run(%Blueprint{} = bp) do
    start = System.monotonic_time()
    :telemetry.execute([:foundry, :factory, :run, :start], %{count: 1}, %{kind: bp.kind, name: bp.name})
    try do
      case bp.kind do
        "TrialSpec" -> {:ok, %{resource: :trial_spec, name: bp.name, spec: bp.spec}}
        other -> {:error, {:unsupported_kind, other}}
      end
    after
      dur = System.monotonic_time() - start
      :telemetry.execute([:foundry, :factory, :run, :stop], %{duration: dur}, %{kind: bp.kind, name: bp.name})
    end
  end
end
