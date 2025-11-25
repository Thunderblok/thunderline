defmodule Thunderline.Thunderbolt.Cerebros.Summary do
  @moduledoc """
  Aggregates recent Cerebros NAS activity for dashboard surfaces.

  This module intentionally keeps its return values presentation-friendly so
  LiveViews and API surfaces can render lightweight cards without repeatedly
  touching Ash resources.
  """

  alias Ash.{NotLoaded, Query}
  alias Thunderline.Thunderbolt.CerebrosBridge
  alias Thunderline.Thunderbolt.Domain
  alias Thunderline.Thunderbolt.Resources.{ModelRun, ModelTrial}

  @type run_summary :: %{
          required(:run_id) => String.t(),
          required(:state) => atom(),
          required(:best_metric) => float() | nil,
          required(:completed_trials) => non_neg_integer(),
          required(:started_at) => DateTime.t() | nil,
          required(:finished_at) => DateTime.t() | nil,
          optional(:error_message) => String.t() | nil,
          optional(:metadata) => map() | nil,
          optional(:bridge_result) => map() | nil
        }

  @type trial_summary :: %{
          required(:run_id) => String.t(),
          required(:trial_id) => String.t(),
          required(:status) => atom(),
          required(:metric) => number() | String.t() | nil,
          required(:inserted_at) => NaiveDateTime.t() | nil,
          optional(:rank) => integer() | nil
        }

  @type snapshot :: %{
          required(:enabled?) => boolean(),
          required(:mlflow_tracking_uri) => String.t() | nil,
          required(:runs) => [run_summary()],
          required(:active_run) => run_summary() | nil,
          required(:run_count) => non_neg_integer(),
          required(:trials) => [trial_summary()]
        }

  @default_run_limit 5
  @default_trial_limit 6

  @doc """
  Returns a snapshot of the latest Cerebros runs and trials.

  The snapshot gracefully degrades when the bridge is disabled or when reads
  fail, so callers can render UI without defensive clauses.
  """
  @spec snapshot(keyword()) :: snapshot()
  def snapshot(opts \\ []) do
    run_limit = Keyword.get(opts, :run_limit, @default_run_limit)
    trial_limit = Keyword.get(opts, :trial_limit, @default_trial_limit)

    runs = fetch_runs(run_limit)
    active_run = Enum.find(runs, &running?/1)
    trials = fetch_trials(trial_limit)

    %{
      enabled?: CerebrosBridge.enabled?(),
      mlflow_tracking_uri: mlflow_tracking_uri(),
      runs: runs,
      active_run: active_run,
      run_count: length(runs),
      trials: trials
    }
  end

  defp fetch_runs(limit) when is_integer(limit) and limit > 0 do
    ModelRun
    |> Query.sort(inserted_at: :desc)
    |> Query.limit(limit)
    |> Ash.read(domain: Domain)
    |> case do
      {:ok, list} -> Enum.map(list, &to_run_summary/1)
      {:error, _reason} -> []
    end
  rescue
    _ -> []
  end

  defp fetch_runs(_), do: []

  defp fetch_trials(limit) when is_integer(limit) and limit > 0 do
    ModelTrial
    |> Query.load(:model_run)
    |> Query.sort(inserted_at: :desc)
    |> Query.limit(limit)
    |> Ash.read(domain: Domain)
    |> case do
      {:ok, list} -> Enum.map(list, &to_trial_summary/1)
      {:error, _reason} -> []
    end
  rescue
    _ -> []
  end

  defp fetch_trials(_), do: []

  defp to_run_summary(%ModelRun{} = run) do
    %{
      run_id: run.run_id,
      state: run.state,
      best_metric: run.best_metric,
      completed_trials: run.completed_trials || 0,
      started_at: run.started_at,
      finished_at: run.finished_at,
      error_message: run.error_message,
      metadata: hydrate_metadata(run.metadata),
      bridge_result: hydrate_metadata(run.bridge_result)
    }
  end

  defp to_run_summary(_), do: %{}

  defp to_trial_summary(%ModelTrial{} = trial) do
    %{
      run_id: parent_run_id(trial),
      trial_id: trial.trial_id,
      status: trial.status,
      metric: extract_metric(trial.metrics),
      inserted_at: trial.inserted_at,
      rank: trial.rank
    }
  end

  defp to_trial_summary(_), do: %{}

  defp hydrate_metadata(map) when is_map(map), do: map
  defp hydrate_metadata(_), do: %{}

  defp parent_run_id(%ModelTrial{} = trial) do
    case Map.get(trial, :model_run) do
      %ModelRun{run_id: run_id} when is_binary(run_id) -> run_id
      %ModelRun{} -> trial.model_run_id
      %NotLoaded{} -> trial.model_run_id
      _ -> trial.model_run_id
    end
  end

  defp extract_metric(value) when is_map(value) do
    value
    |> Enum.reduce_while(nil, fn
      {_key, number}, nil when is_number(number) ->
        {:halt, number}

      {_key, %{} = nested}, nil ->
        case extract_metric(nested) do
          nil -> {:cont, nil}
          found -> {:halt, found}
        end

      _pair, acc ->
        {:cont, acc}
    end)
  end

  defp extract_metric(list) when is_list(list) do
    list
    |> Enum.reduce_while(nil, fn
      {_, number}, nil when is_number(number) ->
        {:halt, number}

      {_k, %{} = nested}, nil ->
        case extract_metric(nested) do
          nil -> {:cont, nil}
          found -> {:halt, found}
        end

      number, nil when is_number(number) ->
        {:halt, number}

      _other, acc ->
        {:cont, acc}
    end)
  end

  defp extract_metric(value) when is_number(value), do: value
  defp extract_metric(value) when is_binary(value), do: value
  defp extract_metric(_), do: nil

  defp running?(%{state: state}) when state in [:running, :initialized], do: true
  defp running?(_), do: false

  defp mlflow_tracking_uri do
    System.get_env("MLFLOW_TRACKING_URI")
    |> case do
      uri when is_binary(uri) and uri != "" -> uri
      _ -> Application.get_env(:thunderline, :mlflow_tracking_uri)
    end
  end
end
