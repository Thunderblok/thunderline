defmodule ThunderlineWeb.DashboardComponents.DomainStatus do
  @moduledoc """
  Domain Status Grid Panel Component

  Real-time monitoring of all 13 consolidated domains with health status,
  event processing rates, error tracking, and resource usage.
  """

  use Phoenix.Component
  import ThunderlineWeb.CoreComponents

  attr :domains, :map, required: true

  def domain_status_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-3">
          <div class="text-2xl">🏗️</div>
          <h3 class="text-lg font-bold text-white">Domain Status</h3>
        </div>
        <div class="text-xs text-purple-300 font-mono">
          <%= healthy_count(@domains) %>/<%= total_count(@domains) %> Healthy
        </div>
      </div>

      <%!-- Overall Health Summary --%>
      <div class="mb-4 bg-black/20 rounded-lg p-3">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs text-gray-400">System Health</span>
          <span class="text-xs font-mono text-purple-300"><%= overall_health_percentage(@domains) %>%</span>
        </div>
        <div class="w-full bg-gray-700 rounded-full h-2">
          <div class={[
            "h-2 rounded-full transition-all duration-1000",
            overall_health_color(@domains)
          ]}
          style={"width: #{overall_health_percentage(@domains)}%"}></div>
        </div>
      </div>

      <%!-- Domain Grid --%>
      <div class="flex-1 overflow-y-auto">
        <div class="grid grid-cols-1 gap-2">
          <%= for {domain, metrics} <- @domains do %>
            <div class={[
              "bg-black/20 rounded-lg p-3 border transition-all duration-300 hover:bg-black/30",
              domain_border_class(metrics[:status])
            ]}>
              <%!-- Domain Header --%>
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center space-x-2">
                  <.status_dot status={metrics[:status]} />
                  <span class="text-sm font-medium text-white">
                    <%= domain_display_name(domain) %>
                  </span>
                </div>
                <span class="text-xs text-gray-400"><%= domain_icon(domain) %></span>
              </div>

              <%!-- Metrics Grid --%>
              <div class="grid grid-cols-2 gap-2 text-xs">
                <div>
                  <span class="text-gray-400">Events/s:</span>
                  <span class="text-cyan-300 font-mono ml-1"><%= metrics[:events_per_sec] || 0 %></span>
                </div>
                <div>
                  <span class="text-gray-400">Memory:</span>
                  <span class="text-blue-300 font-mono ml-1"><%= metrics[:memory_mb] || 0 %>MB</span>
                </div>
                <div>
                  <span class="text-gray-400">Errors:</span>
                  <span class={[
                    "font-mono ml-1",
                    if(metrics[:errors] > 5, do: "text-red-300", else: "text-green-300")
                  ]}><%= metrics[:errors] || 0 %></span>
                </div>
                <div>
                  <span class="text-gray-400">CPU:</span>
                  <span class="text-purple-300 font-mono ml-1"><%= metrics[:cpu_percent] || 0 %>%</span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Summary Stats --%>
      <div class="mt-4 pt-4 border-t border-white/10">
        <div class="grid grid-cols-2 gap-3 text-xs">
          <div>
            <span class="text-gray-400">Total Events/s:</span>
            <span class="text-cyan-300 font-mono ml-1"><%= total_events_per_sec(@domains) %></span>
          </div>
          <div>
            <span class="text-gray-400">Total Errors:</span>
            <span class={[
              "font-mono ml-1",
              if(total_errors(@domains) > 10, do: "text-red-300", else: "text-green-300")
            ]}><%= total_errors(@domains) %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :status, :atom, required: true

  defp status_dot(assigns) do
    ~H"""
    <div class={[
      "w-2 h-2 rounded-full",
      status_dot_class(@status)
    ]}></div>
    """
  end

  # Helper Functions

  defp domain_border_class(:healthy), do: "border-green-500/30"
  defp domain_border_class(:warning), do: "border-yellow-500/30"
  defp domain_border_class(:error), do: "border-red-500/30"
  defp domain_border_class(:degraded), do: "border-orange-500/30"
  defp domain_border_class(_), do: "border-gray-500/30"

  defp status_dot_class(:healthy), do: "bg-green-400 animate-pulse"
  defp status_dot_class(:warning), do: "bg-yellow-400"
  defp status_dot_class(:error), do: "bg-red-400 animate-pulse"
  defp status_dot_class(:degraded), do: "bg-orange-400"
  defp status_dot_class(_), do: "bg-gray-400"

  defp domain_display_name(domain) do
    domain
    |> to_string()
    |> String.replace("thunder", "")
    |> String.capitalize()
  end

  defp domain_icon(:thundercore), do: "⚡"
  defp domain_icon(:thunderbit), do: "🔥"
  defp domain_icon(:thunderbolt), do: "⚡"
  defp domain_icon(:thunderblock), do: "🏗️"
  defp domain_icon(:thundergrid), do: "🔷"
  defp domain_icon(:thundervault), do: "🗄️"
  defp domain_icon(:thundercom), do: "📡"
  defp domain_icon(:thundereye), do: "👁️"
  defp domain_icon(:thunderchief), do: "👑"
  defp domain_icon(:thunderflow), do: "🌊"
  defp domain_icon(:thunderstone), do: "🗿"
  defp domain_icon(:thunderlink), do: "🔗"
  defp domain_icon(:thundercrown), do: "👑"
  defp domain_icon(_), do: "⚙️"

  defp healthy_count(domains) do
    domains
    |> Enum.count(fn {_domain, metrics} -> metrics[:status] == :healthy end)
  end

  defp total_count(domains) do
    map_size(domains)
  end

  defp overall_health_percentage(domains) do
    case total_count(domains) do
      0 -> 0
      total ->
        healthy = healthy_count(domains)
        Float.round((healthy / total) * 100, 0) |> trunc()
    end
  end

  defp overall_health_color(domains) do
    percentage = overall_health_percentage(domains)
    cond do
      percentage >= 90 -> "bg-green-400"
      percentage >= 70 -> "bg-yellow-400"
      percentage >= 50 -> "bg-orange-400"
      true -> "bg-red-400"
    end
  end

  defp total_events_per_sec(domains) do
    domains
    |> Enum.map(fn {_domain, metrics} -> metrics[:events_per_sec] || 0 end)
    |> Enum.sum()
    |> format_number()
  end

  defp total_errors(domains) do
    domains
    |> Enum.map(fn {_domain, metrics} -> metrics[:errors] || 0 end)
    |> Enum.sum()
  end

  defp format_number(num) when is_integer(num) do
    cond do
      num >= 1_000_000 -> "#{Float.round(num / 1_000_000, 1)}M"
      num >= 1_000 -> "#{Float.round(num / 1_000, 1)}K"
      true -> to_string(num)
    end
  end
  defp format_number(num), do: to_string(num)
end
