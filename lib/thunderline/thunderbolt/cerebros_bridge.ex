defmodule Thunderline.Thunderbolt.CerebrosBridge do
  @moduledoc """
  Public entry point for launching Cerebros NAS runs through the bridge.

  Wraps `Thunderline.Thunderbolt.CerebrosBridge.RunWorker` with a friendlier API
  and centralises argument shaping so callers (LiveView, agents, CLI) do not need
  to know the worker internals.
  """

  alias Oban
  alias Oban.Job
  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, RunWorker}

  @type run_spec :: map()
  @type enqueue_option ::
          {:run_id, String.t()}
          | {:meta, map()}
          | {:pulse_id, String.t()}
          | {:budget, map()}
          | {:parameters, map()}
          | {:tau, term()}
          | {:correlation_id, String.t()}
          | {:extra, map()}

  @doc """
  Enqueue a NAS run. Returns `{:ok, Oban.Job}` on success or `{:error, term}` when
  validation fails. If the bridge is disabled the call returns
  `{:error, :bridge_disabled}`.
  """
  @spec enqueue_run(run_spec(), [enqueue_option()]) :: {:ok, Job.t()} | {:error, term()}
  def enqueue_run(spec, opts \\ []) when is_map(spec) do
    if Client.enabled?() do
      # Workaround for Oban 2.20.1 bug: ensure timestamps are set
      # by using schedule_in: 0 which forces immediate scheduling with timestamps
      RunWorker.new(build_args(spec, opts), schedule_in: 0)
      |> Oban.insert()
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

  defp build_args(spec, opts) do
    %{
      "spec" => spec,
      "run_id" => Keyword.get(opts, :run_id) || Map.get(spec, "run_id"),
      "pulse_id" => Keyword.get(opts, :pulse_id) || Map.get(spec, "pulse_id"),
      "budget" => Keyword.get(opts, :budget) || Map.get(spec, "budget", %{}),
      "parameters" => Keyword.get(opts, :parameters) || Map.get(spec, "parameters", %{}),
      "tau" => Keyword.get(opts, :tau) || Map.get(spec, "tau"),
      "correlation_id" => Keyword.get(opts, :correlation_id) || Map.get(spec, "correlation_id"),
      "meta" => Keyword.get(opts, :meta, %{}),
      "extra" => Keyword.get(opts, :extra) || Map.get(spec, "extra", %{})
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
end
