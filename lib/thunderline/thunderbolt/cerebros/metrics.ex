defmodule Thunderline.Thunderbolt.Cerebros.Metrics do
  @moduledoc """
  Aggregates Cerebros NAS telemetry signals into lightweight counters and
  summaries suitable for dashboards and health checks.

  Exposes `snapshot/1` and `reset/1` for LiveDashboard panes or Grafana
  collectors. Attachments are idempotent and cleaned up on terminate so tests
  can spin up additional instances safely.
  """

  use GenServer

  alias Thunderline.Thunderbolt.Cerebros.Telemetry

  @events [
    Telemetry.metrics_namespace() ++ [:run, :queued],
    Telemetry.metrics_namespace() ++ [:run, :started],
    Telemetry.metrics_namespace() ++ [:run, :stopped],
    Telemetry.metrics_namespace() ++ [:run, :failed],
    Telemetry.metrics_namespace() ++ [:trial, :started],
    Telemetry.metrics_namespace() ++ [:trial, :stopped],
    Telemetry.metrics_namespace() ++ [:trial, :exception]
  ]

  @type summary :: %{
          count: non_neg_integer(),
          sum: number(),
          min: number() | nil,
          max: number() | nil
        }
  @type state :: %{
          name: term(),
          handler_ids: [term()],
          queue_latency: summary,
          run_latency: summary,
          trial_latency: summary,
          run_started: non_neg_integer(),
          run_completed: non_neg_integer(),
          run_failed: non_neg_integer(),
          trial_started: non_neg_integer(),
          trial_completed: non_neg_integer(),
          trial_failed: non_neg_integer(),
          last_run: map() | nil,
          last_failure: map() | nil,
          last_trial: map() | nil
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  def snapshot(name \\ __MODULE__), do: GenServer.call(name, :snapshot)
  def reset(name \\ __MODULE__), do: GenServer.call(name, :reset)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    state = initial_state(name)
    {:ok, attach(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, format_snapshot(state), state}
  end

  def handle_call(:reset, _from, state) do
    new_state = initial_state(state.name)
    {:reply, :ok, attach_handlers(new_state, state.handler_ids)}
  end

  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    {:noreply, handle_event(event, measurements, metadata, state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{handler_ids: ids}) do
    Enum.each(ids, fn id ->
      try do
        :telemetry.detach(id)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Event handling
  # ---------------------------------------------------------------------------

  defp handle_event([_, _, _, :run, :queued], measurements, metadata, state) do
    state
    |> update_summary(:queue_latency, measurements[:queue_time_ms])
    |> put_last_run(metadata[:run_id], :queued, measurements, metadata)
    |> bump(:run_started)
  end

  defp handle_event([_, _, _, :run, :started], _measurements, metadata, state) do
    state
    |> put_last_run(metadata[:run_id], :started, %{}, metadata)
  end

  defp handle_event([_, _, _, :run, :stopped], measurements, metadata, state) do
    duration = measurements[:duration_ms]

    state
    |> update_summary(:run_latency, duration)
    |> put_last_run(metadata[:run_id], metadata[:status] || :ok, measurements, metadata)
    |> bump(:run_completed)
  end

  defp handle_event([_, _, _, :run, :failed], measurements, metadata, state) do
    duration = measurements[:duration_ms]

    state
    |> update_summary(:run_latency, duration)
    |> Map.put(:last_failure, %{
      run_id: metadata[:run_id],
      class: metadata[:class],
      reason: metadata[:reason],
      correlation_id: metadata[:correlation_id],
      duration_ms: duration
    })
    |> bump(:run_failed)
  end

  defp handle_event([_, _, _, :trial, :started], _measurements, metadata, state) do
    state
    |> bump(:trial_started)
    |> put_last_trial(metadata[:run_id], metadata[:trial_id], :started, %{}, metadata)
  end

  defp handle_event([_, _, _, :trial, :stopped], measurements, metadata, state) do
    duration = measurements[:duration_ms]

    state
    |> update_summary(:trial_latency, duration)
    |> bump(:trial_completed)
    |> put_last_trial(
      metadata[:run_id],
      metadata[:trial_id],
      metadata[:status] || :ok,
      measurements,
      metadata
    )
  end

  defp handle_event([_, _, _, :trial, :exception], measurements, metadata, state) do
    duration = measurements[:duration_ms]

    state
    |> update_summary(:trial_latency, duration)
    |> bump(:trial_failed)
    |> put_last_trial(metadata[:run_id], metadata[:trial_id], :exception, measurements, metadata)
  end

  defp handle_event(_event, _measurements, _metadata, state), do: state

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp initial_state(name) do
    %{
      name: name,
      handler_ids: [],
      queue_latency: new_summary(),
      run_latency: new_summary(),
      trial_latency: new_summary(),
      run_started: 0,
      run_completed: 0,
      run_failed: 0,
      trial_started: 0,
      trial_completed: 0,
      trial_failed: 0,
      last_run: nil,
      last_failure: nil,
      last_trial: nil
    }
  end

  defp attach(state) do
    handler_ids =
      Enum.map(@events, fn event ->
        id = {__MODULE__, state.name, event}

        try do
          :telemetry.attach(id, event, &__MODULE__.dispatch/4, %{pid: self(), event: event})
          id
        rescue
          _ -> id
        end
      end)

    %{state | handler_ids: handler_ids}
  end

  defp attach_handlers(new_state, handler_ids) do
    %{new_state | handler_ids: handler_ids}
  end

  def dispatch(event, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp update_summary(state, _key, value) when not is_number(value), do: state

  defp update_summary(state, key, value) do
    summary = Map.get(state, key, new_summary())

    updated = %{
      count: summary.count + 1,
      sum: summary.sum + value,
      min: min_value(summary.min, value),
      max: max_value(summary.max, value)
    }

    Map.put(state, key, updated)
  end

  defp min_value(nil, value), do: value
  defp min_value(existing, value), do: min(existing, value)

  defp max_value(nil, value), do: value
  defp max_value(existing, value), do: max(existing, value)

  defp bump(state, key) do
    Map.update!(state, key, &(&1 + 1))
  end

  defp put_last_run(state, nil, _status, _m, _meta), do: state

  defp put_last_run(state, run_id, status, measurements, metadata) do
    Map.put(state, :last_run, %{
      run_id: run_id,
      status: status,
      duration_ms: measurements[:duration_ms],
      best_metric: measurements[:best_metric],
      trials: measurements[:trials],
      queue_time_ms: measurements[:queue_time_ms],
      priority: metadata[:priority],
      component: metadata[:component],
      best_trial_id: metadata[:best_trial_id],
      artifact_id: metadata[:artifact_id],
      correlation_id: metadata[:correlation_id]
    })
  end

  defp put_last_trial(state, nil, _trial_id, _status, _m, _meta), do: state

  defp put_last_trial(state, run_id, trial_id, status, measurements, metadata) do
    Map.put(state, :last_trial, %{
      run_id: run_id,
      trial_id: trial_id,
      status: status,
      duration_ms: measurements[:duration_ms],
      metric: measurements[:metric],
      val_loss: measurements[:val_loss],
      spec_hash: metadata[:spec_hash],
      component: metadata[:component],
      correlation_id: metadata[:correlation_id],
      class: metadata[:class],
      reason: metadata[:reason]
    })
  end

  defp new_summary, do: %{count: 0, sum: 0, min: nil, max: nil}

  defp format_snapshot(state) do
    %{
      queue_latency: enrich_summary(state.queue_latency),
      run_latency: enrich_summary(state.run_latency),
      trial_latency: enrich_summary(state.trial_latency),
      run_started: state.run_started,
      run_completed: state.run_completed,
      run_failed: state.run_failed,
      trial_started: state.trial_started,
      trial_completed: state.trial_completed,
      trial_failed: state.trial_failed,
      trial_success_rate: success_rate(state.trial_completed, state.trial_failed),
      last_run: state.last_run,
      last_trial: state.last_trial,
      last_failure: state.last_failure
    }
  end

  defp enrich_summary(%{count: 0} = summary), do: summary

  defp enrich_summary(%{count: count, sum: sum} = summary) do
    Map.put(summary, :avg, sum / max(count, 1))
  end

  defp success_rate(completed, failed) do
    total = completed + failed

    cond do
      total == 0 -> nil
      true -> completed / total
    end
  end
end
