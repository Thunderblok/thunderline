defmodule Thunderline.Thunderbolt.CerebrosBridge do
  @moduledoc """
  Public entry point for launching Cerebros NAS runs through the bridge.

  Now uses a Reactor saga (RunSaga) for full lifecycle management including:
  - Pre-run validation and setup
  - Python environment initialization
  - NAS run execution
  - Result processing and storage
  - Cleanup and compensation on failures
  - Event publishing for observability

  The saga provides proper error handling, compensation, and async execution
  via Oban workers.
  """

  alias Oban.Job
  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, RunSaga}

  require Logger

  @type run_spec :: map()
  @type enqueue_option ::
          {:run_id, String.t()}
          | {:meta, map()}
          | {:budget, map()}
          | {:parameters, map()}

  @doc """
  Enqueue a NAS run using the Reactor saga. Returns `{:ok, Oban.Job}` on success
  or `{:error, term}` when validation fails. If the bridge is disabled the call
  returns `{:error, :bridge_disabled}`.
  """
  @spec enqueue_run(run_spec(), [enqueue_option()]) :: {:ok, Job.t()} | {:error, term()}
  def enqueue_run(spec, opts \\ [])

  def enqueue_run(spec, opts) when is_map(spec) do
    if Client.enabled?() do
      RunSaga.enqueue(spec, opts)
    else
      {:error, :bridge_disabled}
    end
  end

  def enqueue_run(_spec, _opts), do: {:error, :invalid_spec}

  @doc """
  Convenience predicate for UI layers.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: Client.enabled?()

  # ─────────────────────────────────────────────────────────────────────────────
  # UI-facing lifecycle functions (stubs pending full implementation)
  # ─────────────────────────────────────────────────────────────────────────────

  @doc """
  Queue a NAS run with UI params and spec payload.

  This is the UI-facing version of enqueue_run/2.
  """
  @spec queue_run(map(), map()) :: {:ok, String.t()} | {:error, term()}
  def queue_run(params, spec_payload) do
    run_id = Thunderline.UUID.v7()
    spec = Map.merge(spec_payload, %{run_id: run_id, params: params})

    case enqueue_run(spec) do
      {:ok, _job} -> {:ok, run_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancel a running NAS run.

  TODO: Implement via Oban job cancellation and RunSaga compensation
  """
  @spec cancel_run(String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_run(run_id) do
    Logger.debug("[CerebrosBridge] cancel_run called for #{run_id} (stub)")
    {:error, :not_implemented}
  end

  @doc """
  Get results for a completed NAS run.

  TODO: Implement via persistence layer lookup
  """
  @spec get_run_results(String.t()) :: {:ok, map()} | {:error, term()}
  def get_run_results(run_id) do
    Logger.debug("[CerebrosBridge] get_run_results called for #{run_id} (stub)")
    {:error, :not_implemented}
  end

  @doc """
  Download a report for a completed NAS run.

  TODO: Implement via artifact storage system
  """
  @spec download_report(String.t()) :: {:ok, String.t()} | {:error, term()}
  def download_report(run_id) do
    Logger.debug("[CerebrosBridge] download_report called for #{run_id} (stub)")
    {:error, :not_implemented}
  end
end
