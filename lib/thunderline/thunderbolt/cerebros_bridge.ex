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
end
