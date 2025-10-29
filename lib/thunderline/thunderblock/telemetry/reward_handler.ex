defmodule Thunderline.Thunderblock.Telemetry.RewardHandler do
  @moduledoc """
  Handles telemetry events for IGPO intrinsic reward metrics.

  Listens to `[:thunderline, :flow, :probe, :reward]` events emitted when
  a ProbeRun completes and computes an intrinsic reward score. Stores
  aggregated metrics for analytics and monitoring.

  ## Event Structure

      :telemetry.execute(
        [:thunderline, :flow, :probe, :reward],
        %{count: 1, intrinsic_reward: float()},
        %{
          run_id: binary(),
          provider: binary(),
          model: binary(),
          success?: boolean(),
          laps_count: integer(),
          duration_ms: integer()
        }
      )

  ## Metrics Tracked

  - Average intrinsic reward per provider
  - Average intrinsic reward per model
  - Reward distribution over time
  - Correlation with lap count and duration

  ## Retention

  Metrics are stored in ETS and follow the same retention policy as other
  telemetry handlers (7 days by default, configurable via Application config).
  """

  require Logger

  @table_name :thunderline_reward_metrics
  @retention_hours 168
  # 7 days

  @doc """
  Initializes the ETS table for reward metrics.

  Called during application startup. Creates a public, set-based ETS table
  for storing reward aggregations.
  """
  def init do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table])
        Logger.info("[RewardHandler] Initialized ETS table #{@table_name}")
        :ok

      _tid ->
        Logger.debug("[RewardHandler] ETS table #{@table_name} already exists")
        :ok
    end
  end

  @doc """
  Handles the `[:thunderline, :flow, :probe, :reward]` telemetry event.

  Stores reward metrics in ETS with provider/model-level aggregations.
  """
  def handle_event([:thunderline, :flow, :probe, :reward], measurements, metadata, _config) do
    %{count: _count, intrinsic_reward: reward} = measurements

    %{
      run_id: run_id,
      provider: provider,
      model: model,
      success?: success?,
      laps_count: laps_count,
      duration_ms: duration_ms
    } = metadata

    timestamp = DateTime.utc_now()

    # Store individual run metric
    run_key = {:run, run_id}

    run_metric = %{
      run_id: run_id,
      provider: provider,
      model: model,
      reward: reward,
      laps_count: laps_count,
      duration_ms: duration_ms,
      success?: success?,
      timestamp: timestamp
    }

    :ets.insert(@table_name, {run_key, run_metric})

    # Update provider-level aggregation
    provider_key = {:provider, provider}
    update_aggregation(provider_key, reward, timestamp)

    # Update model-level aggregation
    model_key = {:model, model}
    update_aggregation(model_key, reward, timestamp)

    # Update global aggregation
    global_key = :global
    update_aggregation(global_key, reward, timestamp)

    Logger.debug(
      "[RewardHandler] Stored reward=#{Float.round(reward, 4)} for run=#{run_id} provider=#{provider} model=#{model}"
    )

    :ok
  rescue
    error ->
      Logger.error("[RewardHandler] Failed to handle reward event: #{Exception.message(error)}")

      :ok
  end

  @doc """
  Returns aggregated reward metrics for a given scope.

  ## Examples

      RewardHandler.get_metrics(:global)
      #=> %{count: 150, avg_reward: 0.65, last_updated: ~U[...]}

      RewardHandler.get_metrics({:provider, "openai"})
      #=> %{count: 75, avg_reward: 0.72, last_updated: ~U[...]}

      RewardHandler.get_metrics({:model, "gpt-4o"})
      #=> %{count: 50, avg_reward: 0.78, last_updated: ~U[...]}
  """
  def get_metrics(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, metrics}] -> {:ok, metrics}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns all individual run metrics, optionally filtered by provider or model.

  ## Examples

      RewardHandler.list_runs()
      #=> [%{run_id: "...", reward: 0.65, ...}, ...]

      RewardHandler.list_runs(provider: "openai")
      #=> [%{run_id: "...", provider: "openai", ...}, ...]
  """
  def list_runs(opts \\ []) do
    provider_filter = Keyword.get(opts, :provider)
    model_filter = Keyword.get(opts, :model)

    :ets.match(@table_name, {{:run, :"$1"}, :"$2"})
    |> Enum.map(fn [_run_id, metric] -> metric end)
    |> maybe_filter_provider(provider_filter)
    |> maybe_filter_model(model_filter)
  end

  @doc """
  Clears metrics older than the configured retention period.

  Called periodically by the retention sweeper. Removes both individual
  run metrics and recalculates aggregations based on retained data.
  """
  def sweep_old_metrics do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_hours, :hour)

    # Delete old run metrics
    deleted_count =
      :ets.match(@table_name, {{:run, :"$1"}, :"$2"})
      |> Enum.count(fn [_run_id, metric] ->
        if DateTime.compare(metric.timestamp, cutoff) == :lt do
          :ets.delete(@table_name, {:run, metric.run_id})
          true
        else
          false
        end
      end)

    if deleted_count > 0 do
      # Recalculate aggregations after deletion
      recalculate_aggregations()

      Logger.info("[RewardHandler] Swept #{deleted_count} old reward metrics (cutoff: #{cutoff})")
    end

    {:ok, deleted_count}
  end

  ## Private Functions

  defp update_aggregation(key, new_reward, timestamp) do
    case :ets.lookup(@table_name, key) do
      [{^key, existing}] ->
        updated = %{
          count: existing.count + 1,
          total_reward: existing.total_reward + new_reward,
          avg_reward: (existing.total_reward + new_reward) / (existing.count + 1),
          last_updated: timestamp
        }

        :ets.insert(@table_name, {key, updated})

      [] ->
        initial = %{
          count: 1,
          total_reward: new_reward,
          avg_reward: new_reward,
          last_updated: timestamp
        }

        :ets.insert(@table_name, {key, initial})
    end
  end

  defp recalculate_aggregations do
    # Clear existing aggregations
    :ets.delete(@table_name, :global)

    :ets.match(@table_name, {{:provider, :"$1"}, :_})
    |> Enum.each(fn [p] ->
      :ets.delete(@table_name, {:provider, p})
    end)

    :ets.match(@table_name, {{:model, :"$1"}, :_})
    |> Enum.each(fn [m] ->
      :ets.delete(@table_name, {:model, m})
    end)

    # Rebuild aggregations from remaining run metrics
    :ets.match(@table_name, {{:run, :"$1"}, :"$2"})
    |> Enum.each(fn [_run_id, metric] ->
      update_aggregation(:global, metric.reward, metric.timestamp)
      update_aggregation({:provider, metric.provider}, metric.reward, metric.timestamp)
      update_aggregation({:model, metric.model}, metric.reward, metric.timestamp)
    end)
  end

  defp maybe_filter_provider(metrics, nil), do: metrics

  defp maybe_filter_provider(metrics, provider) do
    Enum.filter(metrics, fn m -> m.provider == provider end)
  end

  defp maybe_filter_model(metrics, nil), do: metrics

  defp maybe_filter_model(metrics, model) do
    Enum.filter(metrics, fn m -> m.model == model end)
  end
end
