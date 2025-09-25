defmodule Thunderline.Thunderforge.FactoryRun do
  @moduledoc """
  Thunderforge: factory run executor. Emits telemetry for run lifecycle.
  """
  require Logger
  alias Thunderline.Thunderforge.Blueprint

  @spec run(Blueprint.t()) :: {:ok, map()} | {:error, term()}
  def run(%Blueprint{} = bp) do
    start = System.monotonic_time()
    :telemetry.execute([:thunderline, :thunderforge, :factory, :run, :start], %{count: 1}, %{kind: bp.kind, name: bp.name})
    try do
      case bp.kind do
        "TrialSpec" -> {:ok, %{resource: :trial_spec, name: bp.name, spec: bp.spec}}
        other -> {:error, {:unsupported_kind, other}}
      end
    after
      dur = System.monotonic_time() - start
      :telemetry.execute([:thunderline, :thunderforge, :factory, :run, :stop], %{duration: dur}, %{kind: bp.kind, name: bp.name})
    end
  end
end
