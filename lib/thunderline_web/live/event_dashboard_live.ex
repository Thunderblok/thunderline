defmodule ThunderlineWeb.EventDashboardLive do
  @moduledoc """
  Real-time Event Monitoring Dashboard for ThunderFlow.

  Displays live event streams, pipeline metrics, validation stats, and telemetry
  using EventBuffer for rolling window data and Canvas visualization.
  """
  use ThunderlineWeb, :live_view

  alias Phoenix.PubSub
  alias Thunderline.Thunderflow.EventBuffer

  @topic "dashboard:events"
  @refresh_interval 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(Thunderline.PubSub, @topic)
      schedule_refresh()
    end

    socket =
      socket
      |> assign(:page_title, "Event Monitor")
      |> assign(:events, EventBuffer.snapshot(100))
      |> assign(:pipeline_stats, calculate_pipeline_stats())
      |> assign(:event_rate, calculate_event_rate())
      |> assign(:validation_stats, calculate_validation_stats())
      |> assign(:flow_data, prepare_flow_data())
      |> assign(:chart_config, flow_chart_config())

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_events", _params, socket) do
    # Just reload from buffer - actual clearing would need EventBuffer API change
    {:noreply, assign(socket, :events, EventBuffer.snapshot(100))}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    events = socket.assigns.events
    csv_content = generate_csv(events)

    socket =
      socket
      |> push_event("download", %{
        filename: "events_#{DateTime.utc_now() |> DateTime.to_unix()}.csv",
        content: csv_content,
        mime_type: "text/csv"
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:event_buffered, event}, socket) do
    events = [normalize_event(event) | socket.assigns.events] |> Enum.take(100)

    socket =
      socket
      |> assign(:events, events)
      |> update(:pipeline_stats, fn _ -> calculate_pipeline_stats() end)
      |> update(:event_rate, fn _ -> calculate_event_rate() end)
      |> update(:flow_data, fn _ -> prepare_flow_data() end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()

    socket =
      socket
      |> assign(:pipeline_stats, calculate_pipeline_stats())
      |> assign(:event_rate, calculate_event_rate())
      |> assign(:validation_stats, calculate_validation_stats())
      |> assign(:flow_data, prepare_flow_data())

    {:noreply, socket}
  end

  # --- Helpers ---

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp calculate_pipeline_stats do
    events = EventBuffer.snapshot(500)

    by_pipeline =
      events
      |> Enum.group_by(fn ev -> Map.get(ev, :pipeline, :general) end)
      |> Enum.map(fn {pipeline, evs} -> {pipeline, length(evs)} end)
      |> Enum.into(%{})

    %{
      realtime: Map.get(by_pipeline, :realtime, 0),
      cross_domain: Map.get(by_pipeline, :cross_domain, 0),
      general: Map.get(by_pipeline, :general, 0),
      total: length(events)
    }
  end

  defp calculate_event_rate do
    events = EventBuffer.snapshot(500)
    now = System.system_time(:second)

    recent =
      events
      |> Enum.filter(fn ev ->
        ts = Map.get(ev, :timestamp, now)
        ts_sec = if is_struct(ts, DateTime), do: DateTime.to_unix(ts), else: now
        now - ts_sec <= 60
      end)
      |> length()

    %{
      per_minute: recent,
      per_second: Float.round(recent / 60, 2)
    }
  end

  defp calculate_validation_stats do
    # Would need telemetry integration for real stats
    # Placeholder for demonstration
    %{
      passed: 0,
      dropped: 0,
      invalid: 0
    }
  end

  defp prepare_flow_data do
    events = EventBuffer.snapshot(100)

    # Group events by 5-second windows for flow visualization
    now = System.system_time(:second)

    windowed =
      events
      |> Enum.map(fn ev ->
        ts = Map.get(ev, :timestamp, now)
        ts_sec = if is_struct(ts, DateTime), do: DateTime.to_unix(ts), else: now
        window = div(now - ts_sec, 5)
        pipeline = Map.get(ev, :pipeline, :general)
        {window, pipeline}
      end)
      |> Enum.group_by(fn {w, _p} -> w end)
      |> Enum.map(fn {window, events} ->
        by_pipeline =
          events
          |> Enum.map(fn {_w, p} -> p end)
          |> Enum.frequencies()

        %{
          window: window * 5,
          realtime: Map.get(by_pipeline, :realtime, 0),
          cross_domain: Map.get(by_pipeline, :cross_domain, 0),
          general: Map.get(by_pipeline, :general, 0)
        }
      end)
      |> Enum.sort_by(& &1.window)
      |> Enum.take(-20)

    Jason.encode!(windowed)
  end

  defp flow_chart_config do
    %{
      x_label: "Time Window (seconds ago)",
      y_label: "Events",
      colors: %{
        realtime: "#3b82f6",
        cross_domain: "#8b5cf6",
        general: "#10b981"
      }
    }
  end

  defp normalize_event(ev) when is_map(ev) do
    %{
      name: Map.get(ev, :name, Map.get(ev, "name", "unknown")),
      source: Map.get(ev, :source, Map.get(ev, "source", "unknown")),
      pipeline: Map.get(ev, :pipeline, Map.get(ev, "pipeline", :general)),
      timestamp: Map.get(ev, :timestamp, Map.get(ev, "timestamp", DateTime.utc_now())),
      priority: Map.get(ev, :priority, Map.get(ev, "priority", :normal))
    }
  end

  defp normalize_event(_), do: %{name: "unknown", source: "unknown", pipeline: :general}

  defp format_timestamp(ts) when is_struct(ts, DateTime) do
    DateTime.to_iso8601(ts)
  end

  defp format_timestamp(_), do: "—"

  defp format_pipeline(:realtime), do: "Real-Time"
  defp format_pipeline(:cross_domain), do: "Cross-Domain"
  defp format_pipeline(:general), do: "General"
  defp format_pipeline(other), do: to_string(other) |> String.capitalize()

  defp format_priority(:high), do: "High"
  defp format_priority(:normal), do: "Normal"
  defp format_priority(:low), do: "Low"
  defp format_priority(other), do: to_string(other) |> String.capitalize()

  defp pipeline_color(:realtime), do: "bg-blue-500"
  defp pipeline_color(:cross_domain), do: "bg-purple-500"
  defp pipeline_color(:general), do: "bg-green-500"
  defp pipeline_color(_), do: "bg-gray-500"

  defp priority_color(:high), do: "bg-red-500"
  defp priority_color(:normal), do: "bg-blue-500"
  defp priority_color(:low), do: "bg-gray-500"
  defp priority_color(_), do: "bg-gray-400"

  defp generate_csv(events) do
    header = "Timestamp,Name,Source,Pipeline,Priority\n"

    rows =
      events
      |> Enum.map(fn ev ->
        [
          format_timestamp(ev.timestamp),
          ev.name,
          to_string(ev.source),
          to_string(ev.pipeline),
          to_string(ev.priority)
        ]
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    header <> rows
  end
end
