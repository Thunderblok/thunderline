defmodule ThunderlineWeb.MetricsLive do
  @moduledoc """
  MetricsLive - Advanced metrics visualization and analysis

  Provides detailed views of:
  - System performance metrics
  - Real-time telemetry data
  - Historical trend analysis
  - Performance bottleneck identification
  """

  use ThunderlineWeb, :live_view

  alias Thunderline.DashboardMetrics
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DashboardMetrics.subscribe()
      # Subscribe to metrics-specific updates
      PubSub.subscribe(Thunderline.PubSub, "metrics:detailed")
    end

    {:ok,
     socket
     |> assign(:page_title, "System Metrics")
     |> assign(:metrics_data, load_detailed_metrics())
     |> assign(:selected_domain, "thundercore")
     |> assign(:time_range, "1h")
     |> assign(:refresh_rate, 5)
     |> schedule_refresh()}
  end

  @impl true
  def handle_info({:metrics_update, metrics}, socket) do
    {:noreply, assign(socket, :metrics_data, metrics)}
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    updated_metrics = load_detailed_metrics()

    socket =
      socket
      |> assign(:metrics_data, updated_metrics)
      |> schedule_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_domain", %{"domain" => domain}, socket) do
    {:noreply, assign(socket, :selected_domain, domain)}
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, :time_range, range)}
  end

  @impl true
  def handle_event("adjust_refresh_rate", %{"rate" => rate}, socket) do
    rate_value = String.to_integer(rate)
    {:noreply, assign(socket, :refresh_rate, rate_value)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="metrics-dashboard">
      <div class="header-section mb-6">
        <h1 class="text-3xl font-bold text-gray-900 mb-4">System Metrics</h1>
        
    <!-- Controls -->
        <div class="bg-white rounded-lg shadow p-4 mb-6">
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <!-- Domain Selection -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Domain</label>
              <select
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                phx-change="select_domain"
                name="domain"
              >
                <option value="thundercore" selected={@selected_domain == "thundercore"}>
                  ThunderCore
                </option>
                <option value="thunderbit" selected={@selected_domain == "thunderbit"}>
                  ThunderBit
                </option>
                <option value="thunderbolt" selected={@selected_domain == "thunderbolt"}>
                  ThunderBolt
                </option>
                <option value="thunderblock" selected={@selected_domain == "thunderblock"}>
                  ThunderBlock
                </option>
                <option value="thundergrid" selected={@selected_domain == "thundergrid"}>
                  ThunderGrid
                </option>
                <!-- Removed legacy ThunderVault alias option -->
                <option value="thundercom" selected={@selected_domain == "thundercom"}>
                  ThunderCom
                </option>
                <option value="thundereye" selected={@selected_domain == "thundereye"}>
                  ThunderEye
                </option>
              </select>
            </div>
            
    <!-- Time Range -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Time Range</label>
              <select
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                phx-change="change_time_range"
                name="range"
              >
                <option value="5m" selected={@time_range == "5m"}>5 minutes</option>
                <option value="1h" selected={@time_range == "1h"}>1 hour</option>
                <option value="6h" selected={@time_range == "6h"}>6 hours</option>
                <option value="24h" selected={@time_range == "24h"}>24 hours</option>
                <option value="7d" selected={@time_range == "7d"}>7 days</option>
              </select>
            </div>
            
    <!-- Refresh Rate -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Refresh (seconds)</label>
              <input
                type="range"
                min="1"
                max="60"
                value={@refresh_rate}
                class="w-full"
                phx-change="adjust_refresh_rate"
                name="rate"
              />
              <span class="text-sm text-gray-500">{@refresh_rate}s</span>
            </div>
            
    <!-- Status -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Status</label>
              <div class="flex items-center">
                <div class="w-3 h-3 bg-green-500 rounded-full mr-2"></div>
                <span class="text-sm text-green-600 font-medium">Live</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Main Metrics Display -->
        <div class="lg:col-span-2 space-y-6">
          <!-- Domain Metrics -->
          <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">
              {String.capitalize(@selected_domain)} Metrics
            </h2>

            {render_domain_metrics(assigns)}
          </div>
          
    <!-- Performance Graph -->
          <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Performance Trends</h2>
            <div class="h-64 bg-gray-50 rounded border-2 border-dashed border-gray-300 flex items-center justify-center">
              <div class="text-center text-gray-500">
                <svg
                  class="mx-auto h-12 w-12 text-gray-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                  />
                </svg>
                <p class="mt-2 text-sm font-medium">Performance Chart</p>
                <p class="text-sm">Time range: {@time_range}</p>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Side Panel -->
        <div class="space-y-6">
          <!-- System Overview -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">System Overview</h3>

            <%= if system_metrics = Map.get(@metrics_data, :system) do %>
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-gray-600">Node:</span>
                  <span class="font-mono text-sm text-blue-600">
                    {Map.get(system_metrics, :node, "unknown")}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Uptime:</span>
                  <span class="font-mono text-sm text-green-600">
                    {format_uptime(Map.get(system_metrics, :uptime, 0))}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Processes:</span>
                  <span class="font-mono text-sm text-gray-900">
                    {Map.get(system_metrics, :process_count, 0)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Schedulers:</span>
                  <span class="font-mono text-sm text-gray-900">
                    {Map.get(system_metrics, :schedulers, 0)}
                  </span>
                </div>
              </div>
            <% end %>
          </div>
          
    <!-- Memory Usage -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Memory Usage</h3>

            <%= if memory = get_in(@metrics_data, [:system, :memory]) do %>
              <div class="space-y-3">
                <div>
                  <div class="flex justify-between text-sm">
                    <span class="text-gray-600">Total</span>
                    <span class="font-mono">{format_bytes(Map.get(memory, :total, 0))}</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2 mt-1">
                    <div
                      class="bg-blue-500 h-2 rounded-full"
                      style={"width: #{calculate_memory_percentage(memory, :total)}%"}
                    >
                    </div>
                  </div>
                </div>

                <div>
                  <div class="flex justify-between text-sm">
                    <span class="text-gray-600">Processes</span>
                    <span class="font-mono">{format_bytes(Map.get(memory, :processes, 0))}</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2 mt-1">
                    <div
                      class="bg-green-500 h-2 rounded-full"
                      style={"width: #{calculate_memory_percentage(memory, :processes)}%"}
                    >
                    </div>
                  </div>
                </div>

                <div>
                  <div class="flex justify-between text-sm">
                    <span class="text-gray-600">System</span>
                    <span class="font-mono">{format_bytes(Map.get(memory, :system, 0))}</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2 mt-1">
                    <div
                      class="bg-yellow-500 h-2 rounded-full"
                      style={"width: #{calculate_memory_percentage(memory, :system)}%"}
                    >
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
          
    <!-- Event Metrics -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Event Processing</h3>

            <%= if events = Map.get(@metrics_data, :events) do %>
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-gray-600">Processed:</span>
                  <span class="font-mono text-sm text-green-600">
                    {Map.get(events, :total_processed, 0) |> format_number()}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Rate/sec:</span>
                  <span class="font-mono text-sm text-blue-600">
                    {Map.get(events, :processing_rate, 0)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Queue Size:</span>
                  <span class="font-mono text-sm text-yellow-600">
                    {Map.get(events, :queue_size, 0)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Failed:</span>
                  <span class="font-mono text-sm text-red-600">
                    {Map.get(events, :failed_events, 0)}
                  </span>
                </div>
              </div>
            <% end %>
          </div>
          
    <!-- Mnesia Status -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Mnesia Status</h3>

            <%= if mnesia = get_in(@metrics_data, [:system, :mnesia_status]) do %>
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-gray-600">Status:</span>
                  <span class={status_color(Map.get(mnesia, :status))}>
                    {Map.get(mnesia, :status, :unknown) |> to_string() |> String.capitalize()}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Tables:</span>
                  <span class="font-mono text-sm text-gray-900">
                    {Map.get(mnesia, :tables, 0)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Nodes:</span>
                  <span class="font-mono text-sm text-blue-600">
                    {length(Map.get(mnesia, :nodes, []))}
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## Private Functions

  defp load_detailed_metrics do
    DashboardMetrics.get_dashboard_data()
  end

  defp schedule_refresh(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_metrics, socket.assigns.refresh_rate * 1000)
    end

    socket
  end

  defp render_domain_metrics(assigns) do
    domain_metrics = get_domain_metrics(assigns.metrics_data, assigns.selected_domain)

    assigns = assign(assigns, :domain_metrics, domain_metrics)

    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <%= for {key, value} <- @domain_metrics do %>
        <div class="text-center p-4 bg-gray-50 rounded-lg">
          <div class="text-2xl font-bold text-blue-600">
            {format_metric_value(value)}
          </div>
          <div class="text-sm text-gray-600 capitalize">
            {format_metric_key(key)}
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp get_domain_metrics(metrics_data, domain) do
    case domain do
      "thundercore" -> Map.get(metrics_data, :thundercore, %{})
      "thunderbit" -> Map.get(metrics_data, :thunderbit, %{})
      "thunderbolt" -> Map.get(metrics_data, :thunderbolt, %{})
      "thunderblock" -> Map.get(metrics_data, :thunderblock, %{})
      "thundergrid" -> Map.get(metrics_data, :thundergrid, %{})
      # Legacy alias removed; vault metrics now under :thunderblock_vault key
      "thunderblock_vault" -> Map.get(metrics_data, :thunderblock_vault, %{})
      "thundercom" -> Map.get(metrics_data, :thundercom, %{})
      "thundereye" -> Map.get(metrics_data, :thundereye, %{})
      _ -> %{}
    end
  end

  defp format_metric_value(value) when is_number(value) do
    cond do
      value > 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M"
      value > 1_000 -> "#{Float.round(value / 1_000, 1)}K"
      is_float(value) -> Float.round(value, 2)
      true -> value
    end
  end

  defp format_metric_value(value) when is_atom(value) do
    value |> to_string() |> String.capitalize()
  end

  defp format_metric_value(value), do: to_string(value)

  defp format_metric_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
  end

  defp calculate_memory_percentage(memory, type) do
    total = Map.get(memory, :total, 1)
    value = Map.get(memory, type, 0)

    if total > 0 do
      min(100, value / total * 100)
    else
      0
    end
  end

  defp status_color(:running), do: "font-mono text-sm text-green-600"
  defp status_color(:error), do: "font-mono text-sm text-red-600"
  defp status_color(_), do: "font-mono text-sm text-yellow-600"
end
