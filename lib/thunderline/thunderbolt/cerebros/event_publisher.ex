defmodule Thunderline.Thunderbolt.Cerebros.EventPublisher do
  @moduledoc """
  Bridges Cerebros telemetry into the Thunderflow EventBus and PubSub topics so
  dashboards and LiveViews can react without polling metrics snapshots.

  Runs as a lightweight GenServer attaching to the Cerebros telemetry namespace
  and emitting:

    * `ml.run.queued|started|stopped|failed`
    * `ml.trial.started|stopped|exception`

  Broadcasts run lifecycle updates to `"cerebros:runs"` and trial updates to
  `"cerebros:trials"` via `Thunderline.PubSub`.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Thunderbolt.Cerebros.Telemetry

  @run_topic "cerebros:runs"
  @trial_topic "cerebros:trials"

  @run_events [
    Telemetry.metrics_namespace() ++ [:run, :queued],
    Telemetry.metrics_namespace() ++ [:run, :started],
    Telemetry.metrics_namespace() ++ [:run, :stopped],
    Telemetry.metrics_namespace() ++ [:run, :failed]
  ]

  @trial_events [
    Telemetry.metrics_namespace() ++ [:trial, :started],
    Telemetry.metrics_namespace() ++ [:trial, :stopped],
    Telemetry.metrics_namespace() ++ [:trial, :exception]
  ]

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{name: name}, name: name)
  end

  @impl true
  def init(state) do
    handler_ids = attach_handlers(self())
    {:ok, Map.put(state, :handler_ids, handler_ids)}
  end

  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    case event do
      [_, _, _, :run, stage] ->
        handle_run_event(stage, measurements, metadata)

      [_, _, _, :trial, stage] ->
        handle_trial_event(stage, measurements, metadata)

      _ ->
        :ok
    end

    {:noreply, state}
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
  # Handlers
  # ---------------------------------------------------------------------------

  defp handle_run_event(stage, measurements, metadata) do
    update = build_run_update(stage, measurements, metadata)

    publish_run_event(stage, update)
    broadcast_run(update)
  end

  defp handle_trial_event(stage, measurements, metadata) do
    update = build_trial_update(stage, measurements, metadata)

    publish_trial_event(stage, update)
    broadcast_trial(update)
  end

  # ---------------------------------------------------------------------------
  # Builders & publishers
  # ---------------------------------------------------------------------------

  defp build_run_update(stage, measurements, metadata) do
    %{
      run_id: metadata[:run_id],
      stage: stage,
      metadata: sanitize(metadata),
      measurements: sanitize(measurements),
      published_at: DateTime.utc_now(),
      source: :telemetry
    }
  end

  defp build_trial_update(stage, measurements, metadata) do
    %{
      run_id: metadata[:run_id],
      trial_id: metadata[:trial_id],
      stage: stage,
      metadata: sanitize(metadata),
      measurements: sanitize(measurements),
      published_at: DateTime.utc_now(),
      source: :telemetry
    }
  end

  defp publish_run_event(stage, %{run_id: run_id} = update) when is_binary(run_id) do
    name = "ml.run." <> Atom.to_string(stage)
    payload = Map.take(update, [:run_id, :stage, :metadata, :measurements])

    publish_event(name, payload)
  end

  defp publish_run_event(_stage, _update), do: :ok

  defp publish_trial_event(stage, %{run_id: run_id} = update) when is_binary(run_id) do
    name = "ml.trial." <> Atom.to_string(stage)

    payload =
      update
      |> Map.take([:run_id, :trial_id, :stage, :metadata, :measurements])
      |> Map.put_new(:trial_id, update[:trial_id])

    publish_event(name, payload)
  end

  defp publish_trial_event(_stage, _update), do: :ok

  defp publish_event(name, payload) do
    attrs = [name: name, source: :bolt, payload: payload, meta: %{pipeline: :realtime}]

    case Event.new(attrs) do
      {:ok, event} ->
        _ = EventBus.publish_event(event)
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Cerebros.EventPublisher] failed to build event #{name}: #{inspect(reason)}"
        )

        :ok
    end
  rescue
    error ->
      Logger.warning("[Cerebros.EventPublisher] failed to publish #{name}: #{inspect(error)}")
      :ok
  end

  defp broadcast_run(update) do
    PubSub.broadcast(Thunderline.PubSub, @run_topic, {:run_update, update})
  end

  defp broadcast_trial(update) do
    PubSub.broadcast(Thunderline.PubSub, @trial_topic, {:trial_update, update})
  end

  # ---------------------------------------------------------------------------
  # Telemetry attachment helpers
  # ---------------------------------------------------------------------------

  defp attach_handlers(pid) do
    events = @run_events ++ @trial_events

    Enum.map(events, fn event ->
      id = {__MODULE__, pid, event}

      case :telemetry.attach(id, event, &__MODULE__.dispatch/4, %{pid: pid}) do
        :ok -> id
        {:error, :already_exists} -> id
        _ -> id
      end
    end)
  end

  def dispatch(event, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  # ---------------------------------------------------------------------------
  # Sanitizers
  # ---------------------------------------------------------------------------

  defp sanitize(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, normalize_key(k), normalize_value(v))
    end)
  end

  defp sanitize(_), do: %{}

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: inspect(key)

  defp normalize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp normalize_value(%{} = map), do: sanitize(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(other), do: other
end
