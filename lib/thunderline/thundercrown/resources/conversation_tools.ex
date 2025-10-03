defmodule Thunderline.Thundercrown.Resources.ConversationTools do
  @moduledoc """
  Governance-approved helper actions that surface conversational context for LLM tooling.

  The exposed actions power the default conversation agent by providing lightweight
  snapshots of Thunderline state (feature flags, run activity, environment hints, etc.)
  that can be fetched through AshAI tool calls.
  """

  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  alias Decimal
  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.Cerebros.Summary

  code_interface do
    define :context_snapshot
    define :run_digest, args: [:limit]
  end

  actions do
    defaults []

    action :context_snapshot, :map do
      argument :include_features, :boolean, default: true

      run fn %{arguments: %{include_features: include_features}}, context ->
        now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        actor = Map.get(context, :actor)

        feature_snapshot =
          if include_features do
            Feature.all() |> Enum.into(%{})
          else
            %{}
          end

        cerebros_snapshot = Summary.snapshot(run_limit: 3, trial_limit: 0)

        result = %{
          timestamp_iso8601: now,
          environment: Application.get_env(:thunderline, :environment, "dev"),
          actor_role: actor && Map.get(actor, :role),
          actor_tenant: actor && Map.get(actor, :tenant_id),
          mlflow_tracking_uri: cerebros_snapshot.mlflow_tracking_uri,
          cerebros_enabled?: cerebros_snapshot.enabled?,
          feature_flags: feature_snapshot,
          recent_run_count: cerebros_snapshot.run_count
        }

        {:ok, result}
      end
    end

    action :run_digest, :map do
      argument :limit, :integer, default: 3, constraints: [min: 1, max: 10]

      run fn %{arguments: %{limit: limit}}, _context ->
        snapshot = Summary.snapshot(run_limit: limit, trial_limit: 0)

        runs =
          snapshot.runs
          |> Enum.map(&serialize_run/1)

        {:ok,
         %{
           enabled?: snapshot.enabled?,
           mlflow_tracking_uri: snapshot.mlflow_tracking_uri,
           runs: runs
         }}
      end
    end
  end

  policies do
    policy action([:context_snapshot, :run_digest]) do
      authorize_if expr(^actor(:role) in [:owner, :steward, :system])
      authorize_if expr(not is_nil(actor(:tenant_id)))
    end
  end

  attributes do
    uuid_primary_key :id
  end

  defp serialize_run(%{run_id: run_id} = run) do
    %{
      run_id: run_id,
      state: Map.get(run, :state),
      best_metric: to_number(Map.get(run, :best_metric)),
      completed_trials: Map.get(run, :completed_trials, 0),
      started_at: format_datetime(Map.get(run, :started_at)),
      finished_at: format_datetime(Map.get(run, :finished_at)),
      error_message: Map.get(run, :error_message),
      metadata: Map.get(run, :metadata, %{})
    }
  end

  defp serialize_run(_), do: %{}

  defp to_number(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_number(value) when is_number(value), do: value
  defp to_number(_), do: nil

  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_datetime(_), do: nil
end
