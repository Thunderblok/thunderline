defmodule Thunderline.Thunderbolt.CerebrosBridge.RunWorker do
  @moduledoc """
  Oban worker that executes Cerebros NAS runs via a Reactor saga.

  This worker is responsible for:
  - Validating job arguments
  - Delegating execution to RunSaga (Reactor-based)
  - Error handling and logging
  - Integration with Oban retry/backoff

  ## Expected job args

    * "run_id" - External run identifier (defaults to generated UUID)
    * "spec" - Map describing the NAS search spec (search space, priors, etc.)
    * "budget" - Optional budget constraints map
    * "parameters" - Optional parameter overrides map
    * "meta" - Metadata map propagated to telemetry/EventBus

  The saga handles all lifecycle steps including validation, Python execution,
  result processing, event publishing, and compensation on failures.
  """
  use Oban.Worker, queue: :ml, max_attempts: 1

  require Logger

  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, RunSaga}

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    case job.args do
      %{} = args ->
        run_id = Map.get(args, "run_id") || default_run_id()

        Logger.info("[RunWorker] Starting NAS run via Reactor saga: #{run_id}")

        if Client.enabled?() do
          args = Map.put_new(args, "run_id", run_id)
          execute_saga(args, job)
        else
          {:discard, :bridge_disabled}
        end

      _ ->
        {:discard, :invalid_args}
    end
  end

  # Execute the Reactor saga with proper error handling
  defp execute_saga(args, job) do
    spec = Map.get(args, "spec", %{})
    opts = [
      run_id: args["run_id"],
      budget: Map.get(args, "budget", %{}),
      parameters: Map.get(args, "parameters", %{}),
      meta: Map.merge(Map.get(args, "meta", %{}), %{
        oban_job_id: job.id,
        oban_attempt: job.attempt
      })
    ]

    case RunSaga.run(spec, opts) do
      {:ok, result} ->
        Logger.info("[RunWorker] Saga completed successfully: #{args["run_id"]}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("[RunWorker] Saga failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp default_run_id do
    if Code.ensure_loaded?(Thunderline.UUID) and
         function_exported?(Thunderline.UUID, :v7, 0) do
      Thunderline.UUID.v7()
    else
      Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    end
  end
end
