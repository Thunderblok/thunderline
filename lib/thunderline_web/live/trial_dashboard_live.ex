defmodule ThunderlineWeb.TrialDashboardLive do
  @moduledoc """
  Real-time ML Trial Dashboard with live metrics visualization.

  Displays:
  - Active trials with real-time metric updates
  - Canvas-based loss/accuracy curves
  - Hyperparameter displays
  - MLflow integration links
  - Trial status (running, completed, failed)

  Uses Canvas hooks (proven by whiteboard) + PubSub for real-time updates.
  """
  use ThunderlineWeb, :live_view

  alias Thunderline.Thunderbolt.Resources.{ModelRun, ModelTrial}
  alias Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to trial events for real-time updates
      ThunderlineWeb.Endpoint.subscribe("trials:updates")
    end

    socket =
      socket
      |> assign(:model_runs, [])
      |> assign(:selected_run, nil)
      |> assign(:trials, [])
      |> assign(:metrics_data, %{})
      |> assign(:page_title, "ML Trial Dashboard")
      |> load_model_runs()

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"run_id" => run_id}, _url, socket) do
    socket =
      socket
      |> load_model_run(run_id)
      |> load_trials(run_id)
      |> prepare_metrics_data()

    {:noreply, socket}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_run", %{"run_id" => run_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/trials/#{run_id}")}
  end

  def handle_event("refresh_trials", _, socket) do
    run_id = socket.assigns.selected_run.id

    socket =
      socket
      |> load_trials(run_id)
      |> prepare_metrics_data()

    {:noreply, socket}
  end

  def handle_event("export_metrics", %{"trial_id" => trial_id}, socket) do
    trial = Enum.find(socket.assigns.trials, &(&1.id == trial_id))

    if trial do
      # Convert metrics to CSV format
      csv_data = metrics_to_csv(trial)

      socket =
        push_event(socket, "download_csv", %{
          filename: "trial_#{trial.trial_id}_metrics.csv",
          content: csv_data
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:trial_update, trial_data}, socket) do
    # Real-time trial update via PubSub
    socket =
      socket
      |> update_trial(trial_data)
      |> prepare_metrics_data()

    {:noreply, socket}
  end

  def handle_info({:metrics_update, trial_id, metrics}, socket) do
    # Real-time metrics update
    socket =
      socket
      |> update_trial_metrics(trial_id, metrics)
      |> prepare_metrics_data()
      |> push_metrics_to_chart(trial_id)

    {:noreply, socket}
  end

  # -- Private Functions --

  defp load_model_runs(socket) do
    query =
      ModelRun
      |> Query.sort(inserted_at: :desc)
      |> Query.limit(20)

    case Ash.read(query) do
      {:ok, runs} ->
        assign(socket, :model_runs, runs)

      {:error, _} ->
        assign(socket, :model_runs, [])
    end
  end

  defp load_model_run(socket, run_id) do
    case Ash.get(ModelRun, run_id) do
      {:ok, run} ->
        assign(socket, :selected_run, run)

      {:error, _} ->
        socket
        |> put_flash(:error, "Model run not found")
        |> push_navigate(to: ~p"/dashboard/trials")
    end
  end

  defp load_trials(socket, run_id) do
    query =
      ModelTrial
      |> Query.filter(model_run_id: run_id)
      |> Query.sort(inserted_at: :desc)
      |> Query.load(:mlflow_run)

    case Ash.read(query) do
      {:ok, trials} ->
        assign(socket, :trials, trials)

      {:error, _} ->
        assign(socket, :trials, [])
    end
  end

  defp prepare_metrics_data(socket) do
    trials = socket.assigns.trials

    metrics_data =
      trials
      |> Enum.filter(fn trial -> trial.metrics != %{} end)
      |> Enum.reduce(%{}, fn trial, acc ->
        trial_metrics = extract_time_series_metrics(trial)
        Map.put(acc, trial.id, trial_metrics)
      end)

    assign(socket, :metrics_data, metrics_data)
  end

  defp extract_time_series_metrics(trial) do
    # Extract metrics for chart visualization
    %{
      loss: extract_metric_series(trial.metrics, "loss"),
      accuracy: extract_metric_series(trial.metrics, "accuracy"),
      trial_id: trial.trial_id,
      parameters: trial.parameters,
      spectral_norm: trial.spectral_norm
    }
  end

  defp extract_metric_series(metrics, key) when is_map(metrics) do
    case Map.get(metrics, key) do
      value when is_number(value) ->
        [{0, value}]

      values when is_list(values) ->
        values
        |> Enum.with_index()
        |> Enum.map(fn {val, idx} -> {idx, val} end)

      _ ->
        []
    end
  end

  defp extract_metric_series(_, _), do: []

  defp update_trial(socket, trial_data) do
    trials =
      Enum.map(socket.assigns.trials, fn trial ->
        if trial.id == trial_data.id do
          Map.merge(trial, trial_data)
        else
          trial
        end
      end)

    assign(socket, :trials, trials)
  end

  defp update_trial_metrics(socket, trial_id, new_metrics) do
    trials =
      Enum.map(socket.assigns.trials, fn trial ->
        if trial.id == trial_id do
          %{trial | metrics: Map.merge(trial.metrics, new_metrics)}
        else
          trial
        end
      end)

    assign(socket, :trials, trials)
  end

  defp push_metrics_to_chart(socket, trial_id) do
    metrics = get_in(socket.assigns.metrics_data, [trial_id])

    if metrics do
      push_event(socket, "update_metrics", %{
        trial_id: trial_id,
        metrics: metrics
      })
    else
      socket
    end
  end

  defp metrics_to_csv(trial) do
    headers = ["metric", "value", "step"]

    rows =
      trial.metrics
      |> Enum.flat_map(fn {key, value} ->
        case value do
          val when is_number(val) ->
            [["#{key}", "#{val}", "0"]]

          list when is_list(list) ->
            list
            |> Enum.with_index()
            |> Enum.map(fn {val, idx} -> ["#{key}", "#{val}", "#{idx}"] end)

          _ ->
            []
        end
      end)

    [headers | rows]
    |> Enum.map_join("\n", fn row -> Enum.join(row, ",") end)
  end

  defp format_status(:succeeded), do: {"✓", "text-green-400"}
  defp format_status(:failed), do: {"✗", "text-red-400"}
  defp format_status(:skipped), do: {"⊘", "text-gray-400"}
  defp format_status(:cancelled), do: {"⊗", "text-yellow-400"}
  defp format_status(_), do: {"?", "text-gray-400"}

  defp format_duration(nil), do: "—"

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  defp format_duration(_), do: "—"

  defp format_number(nil), do: "—"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.split("", trim: true)
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", fn chunk -> Enum.join(chunk, "") end)
    |> String.reverse()
  end

  defp format_number(_), do: "—"

  defp mlflow_url(trial) do
    base_url = System.get_env("MLFLOW_TRACKING_URI", "http://localhost:5000")

    if trial.mlflow_run_id do
      "#{base_url}/#/experiments/#{(trial.mlflow_run && trial.mlflow_run.mlflow_experiment_id) || "default"}/runs/#{trial.mlflow_run_id}"
    else
      nil
    end
  end
end
