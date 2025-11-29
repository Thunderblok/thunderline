defmodule ThunderlineWeb.DashboardComponents.SystemHealth do
  @moduledoc """
  System Health Panel Component

  Real-time monitoring of core system metrics including CPU, memory, disk I/O,
  network activity, and process health with beautiful visualizations.
  """

  use Phoenix.Component

  attr :health, :map, required: true

  def system_health_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center space-x-3">
          <div class="text-2xl">💻</div>
          <h3 class="text-lg font-bold text-white">System Health</h3>
        </div>
        <.status_badge status={@health[:status] || :unknown} />
      </div>

      <%!-- CPU Usage Ring --%>
      <div class="mb-6 flex justify-center">
        <div class="relative w-24 h-24">
          <svg class="w-24 h-24 transform -rotate-90" viewBox="0 0 100 100">
            <%!-- Background circle --%>
            <circle
              cx="50"
              cy="50"
              r="40"
              stroke="currentColor"
              stroke-width="8"
              fill="none"
              class="text-gray-700"
            />
            <%!-- Progress circle --%>
            <circle
              cx="50"
              cy="50"
              r="40"
              stroke="currentColor"
              stroke-width="8"
              fill="none"
              class={cpu_color(@health[:cpu_usage])}
              stroke-dasharray={251.2}
              stroke-dashoffset={251.2 - 251.2 * (@health[:cpu_usage] || 0) / 100}
              stroke-linecap="round"
              class="transition-all duration-1000"
            />
          </svg>
          <div class="absolute inset-0 flex items-center justify-center">
            <div class="text-center">
              <div class="text-lg font-bold text-white">{@health[:cpu_usage] || 0}%</div>
              <div class="text-xs text-gray-400">CPU</div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Memory Usage Bar --%>
      <div class="mb-4">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-gray-300">Memory</span>
          <span class="text-sm font-mono text-cyan-300">
            {format_memory(@health[:memory_usage][:used])} / {format_memory(
              @health[:memory_usage][:total]
            )}
          </span>
        </div>
        <div class="w-full bg-gray-700 rounded-full h-2">
          <div
            class={[
              "h-2 rounded-full transition-all duration-1000",
              memory_color(@health[:memory_usage])
            ]}
            style={"width: #{memory_percentage(@health[:memory_usage])}%"}
          >
          </div>
        </div>
      </div>

      <%!-- Disk I/O --%>
      <div class="mb-4">
        <h4 class="text-sm font-medium text-gray-300 mb-3">Disk I/O</h4>
        <div class="grid grid-cols-2 gap-3">
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex items-center space-x-2 mb-1">
              <div class="w-2 h-2 bg-green-400 rounded-full"></div>
              <span class="text-xs text-gray-400">Read</span>
            </div>
            <div class="text-sm font-mono text-green-300">
              {format_bandwidth(@health[:disk_io][:read])}
            </div>
          </div>
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex items-center space-x-2 mb-1">
              <div class="w-2 h-2 bg-orange-400 rounded-full"></div>
              <span class="text-xs text-gray-400">Write</span>
            </div>
            <div class="text-sm font-mono text-orange-300">
              {format_bandwidth(@health[:disk_io][:write])}
            </div>
          </div>
        </div>
      </div>

      <%!-- Network Activity --%>
      <div class="mb-4">
        <h4 class="text-sm font-medium text-gray-300 mb-3">Network</h4>
        <div class="grid grid-cols-2 gap-3">
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex items-center space-x-2 mb-1">
              <div class="w-2 h-2 bg-blue-400 rounded-full"></div>
              <span class="text-xs text-gray-400">In</span>
            </div>
            <div class="text-sm font-mono text-blue-300">
              {format_bandwidth(@health[:network][:incoming])}
            </div>
          </div>
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex items-center space-x-2 mb-1">
              <div class="w-2 h-2 bg-purple-400 rounded-full"></div>
              <span class="text-xs text-gray-400">Out</span>
            </div>
            <div class="text-sm font-mono text-purple-300">
              {format_bandwidth(@health[:network][:outgoing])}
            </div>
          </div>
        </div>
      </div>

      <%!-- Process Info --%>
      <div class="mt-auto">
        <div class="grid grid-cols-2 gap-3 text-xs">
          <div>
            <span class="text-gray-400">Active:</span>
            <span class="text-white font-mono ml-1">{@health[:processes][:active]}</span>
          </div>
          <div>
            <span class="text-gray-400">Total:</span>
            <span class="text-white font-mono ml-1">{@health[:processes][:total]}</span>
          </div>
        </div>
        <div class="mt-2 text-xs text-gray-400">
          Uptime: {format_uptime(@health[:uptime])}
        </div>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <div class={[
      "px-3 py-1 rounded-full text-xs font-medium flex items-center space-x-2",
      status_badge_class(@status)
    ]}>
      <div class={["w-2 h-2 rounded-full", status_dot_class(@status)]}></div>
      <span>{status_text(@status)}</span>
    </div>
    """
  end

  # Helper Functions

  defp cpu_color(usage) when usage > 90, do: "text-red-400"
  defp cpu_color(usage) when usage > 70, do: "text-orange-400"
  defp cpu_color(usage) when usage > 50, do: "text-yellow-400"
  defp cpu_color(_), do: "text-green-400"

  defp memory_color(%{used: used, total: total}) do
    percentage = used / total * 100

    cond do
      percentage > 90 -> "bg-red-400"
      percentage > 70 -> "bg-orange-400"
      percentage > 50 -> "bg-yellow-400"
      true -> "bg-green-400"
    end
  end

  defp memory_percentage(%{used: used, total: total}) do
    (used / total * 100) |> Float.round(1)
  end

  defp status_badge_class(:healthy),
    do: "bg-green-500/20 text-green-300 border border-green-500/30"

  defp status_badge_class(:warning),
    do: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"

  defp status_badge_class(:error), do: "bg-red-500/20 text-red-300 border border-red-500/30"
  defp status_badge_class(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp status_dot_class(:healthy), do: "bg-green-400 animate-pulse"
  defp status_dot_class(:warning), do: "bg-yellow-400 animate-pulse"
  defp status_dot_class(:error), do: "bg-red-400 animate-pulse"
  defp status_dot_class(_), do: "bg-gray-400"

  defp status_text(:healthy), do: "Healthy"
  defp status_text(:warning), do: "Warning"
  defp status_text(:error), do: "Error"
  defp status_text(_), do: "Unknown"

  defp format_memory(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)}GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)}MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
      true -> "#{bytes}B"
    end
  end

  defp format_memory(_), do: "0B"

  defp format_bandwidth(bytes_per_sec) when is_integer(bytes_per_sec) do
    cond do
      bytes_per_sec >= 1_048_576 -> "#{Float.round(bytes_per_sec / 1_048_576, 1)}MB/s"
      bytes_per_sec >= 1024 -> "#{Float.round(bytes_per_sec / 1024, 1)}KB/s"
      true -> "#{bytes_per_sec}B/s"
    end
  end

  defp format_bandwidth(_), do: "0B/s"

  defp format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp format_uptime(_), do: "0m"
end
