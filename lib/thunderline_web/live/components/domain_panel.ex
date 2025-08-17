defmodule ThunderlineWeb.DashboardLive.Components.DomainPanel do
  @moduledoc """
  Domain Panel Component for Thunderblock Dashboard

  Displays metrics and status for each Thunder domain in glassmorphism style.
  """

  use Phoenix.Component
  import ThunderlineWeb.CoreComponents

  attr :domain, :atom, required: true
  attr :metrics, :map, default: %{}
  attr :active, :boolean, default: false
  attr :class, :string, default: ""

  def domain_panel(assigns) do
    ~H"""
    <div
      class={[
        "backdrop-blur-md rounded-2xl border transition-all duration-300 p-6 cursor-pointer",
        (@active && "bg-cyan-500/20 border-cyan-400/50 shadow-lg shadow-cyan-500/25") ||
          "bg-white/5 border-white/10 hover:bg-white/10 hover:border-white/20",
        @class
      ]}
      phx-click="select_domain"
      phx-value-domain={@domain}
    >
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-3">
          <div class="text-2xl">{domain_icon(@domain)}</div>
          <h3 class="text-lg font-semibold text-white capitalize">
            {String.replace(to_string(@domain), "thunder", "")}
          </h3>
        </div>
        <.status_indicator status={@metrics[:status] || :unknown} />
      </div>

      <div class="space-y-3">
        <%= case @domain do %>
          <% :thundercore -> %>
            <.metric_row label="Agents" value={@metrics[:agents]} color="cyan" />
            <.metric_row label="Tasks" value={@metrics[:tasks]} color="green" />
            <.metric_row label="Workflows" value={@metrics[:workflows]} color="blue" />
            <.metric_row
              label="Success Rate"
              value={format_percentage(@metrics[:success_rate])}
              color="purple"
            />
          <% :thunderbit -> %>
            <.metric_row label="Active Bits" value={format_number(@metrics[:active])} color="cyan" />
            <.metric_row label="Dormant Bits" value={format_number(@metrics[:dormant])} color="gray" />
            <.metric_row
              label="Efficiency"
              value={format_percentage(@metrics[:efficiency])}
              color="green"
            />
          <% :thunderbolt -> %>
            <.metric_row label="Chunks" value={@metrics[:chunks]} color="cyan" />
            <.metric_row label="Healthy" value={@metrics[:healthy_chunks]} color="green" />
            <.metric_row label="Health %" value={@metrics[:health_percentage]} color="green" />
            <.metric_row label="Meshes" value={@metrics[:active_meshes]} color="blue" />
          <% :thunderblock -> %>
            <.metric_row label="Communities" value={@metrics[:communities]} color="cyan" />
            <.metric_row
              label="Members"
              value={format_number(@metrics[:total_members])}
              color="green"
            />
            <.metric_row label="Channels" value={@metrics[:active_channels]} color="blue" />
            <.metric_row
              label="Messages"
              value={format_number(@metrics[:messages_today])}
              color="purple"
            />
          <% :thundergrid -> %>
            <.metric_row label="Active Zones" value={@metrics[:active_zones]} color="cyan" />
            <.metric_row label="Total Hexes" value={@metrics[:total_hexes]} color="gray" />
            <.metric_row label="Energy Level" value={@metrics[:energy_level]} color="yellow" />
            <.metric_row
              label="Zone Health"
              value={format_percentage(@metrics[:zone_health])}
              color="green"
            />
          <% :thunderblock_vault -> %>
            <.metric_row label="Records" value={format_number(@metrics[:records])} color="cyan" />
            <.metric_row
              label="Knowledge"
              value={format_number(@metrics[:knowledge_nodes])}
              color="green"
            />
            <.metric_row label="Memory" value={@metrics[:memory_usage]} color="blue" />
            <.metric_row
              label="Query Perf"
              value={format_percentage(@metrics[:query_performance])}
              color="purple"
            />
          <% :thundercom -> %>
            <.metric_row
              label="Fed Messages"
              value={format_number(@metrics[:federated_messages])}
              color="cyan"
            />
            <.metric_row label="Realms" value={@metrics[:realms]} color="green" />
            <.metric_row label="Connections" value={@metrics[:active_connections]} color="blue" />
            <.metric_row label="Throughput" value={@metrics[:message_throughput]} color="purple" />
          <% :thundereye -> %>
            <.metric_row label="Alerts" value={@metrics[:active_alerts]} color="red" />
            <.metric_row label="Uptime" value="#{@metrics[:system_uptime]}%" color="green" />
            <.metric_row
              label="Error Rate"
              value={format_percentage(@metrics[:error_rate])}
              color="yellow"
            />
            <.metric_row label="Response" value="#{@metrics[:response_time]}ms" color="blue" />
          <% :thunderchief -> %>
            <.metric_row label="UI Panels" value={@metrics[:ui_panels]} color="cyan" />
            <.metric_row label="Controls" value={@metrics[:active_controls]} color="green" />
            <.metric_row label="Sessions" value={@metrics[:user_sessions]} color="blue" />
            <.metric_row
              label="Health"
              value={format_percentage(@metrics[:dashboard_health])}
              color="purple"
            />
          <% :thunderflow -> %>
            <.metric_row
              label="Events"
              value={format_number(@metrics[:events_processed])}
              color="cyan"
            />
            <.metric_row label="Streams" value={@metrics[:active_streams]} color="green" />
            <.metric_row label="Flow Rate" value={@metrics[:flow_rate]} color="blue" />
            <.metric_row label="Backlog" value={@metrics[:backlog_size]} color="yellow" />
          <% :thunderstone -> %>
            <.metric_row label="Policies" value={@metrics[:active_policies]} color="cyan" />
            <.metric_row label="Rules" value={@metrics[:enforcement_rules]} color="green" />
            <.metric_row
              label="Compliance"
              value={format_percentage(@metrics[:compliance_rate])}
              color="blue"
            />
            <.metric_row label="Violations" value={@metrics[:policy_violations]} color="red" />
          <% :thunderlink -> %>
            <.metric_row label="Total Links" value={@metrics[:total_links]} color="cyan" />
            <.metric_row label="Active Links" value={@metrics[:active_links]} color="green" />
            <.metric_row
              label="Link Health"
              value={format_percentage(@metrics[:link_health])}
              color="blue"
            />
            <.metric_row label="Throughput" value="#{@metrics[:throughput]} MB/s" color="purple" />
          <% :thundercrown -> %>
            <.metric_row label="Instances" value={@metrics[:instances]} color="cyan" />
            <.metric_row label="Avg Load" value={@metrics[:average_load]} color="green" />
            <.metric_row label="Peak Load" value={@metrics[:peak_load]} color="yellow" />
            <.metric_row
              label="Utilization"
              value={format_percentage(@metrics[:resource_utilization])}
              color="blue"
            />
          <% _ -> %>
            <div class="text-sm text-gray-400">
              No metrics available
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: "gray"

  defp metric_row(assigns) do
    ~H"""
    <div class="flex justify-between items-center text-sm">
      <span class="text-gray-300">{@label}</span>
      <span class={metric_color_class(@color)}>{@value}</span>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_indicator(assigns) do
    ~H"""
    <div
      class={[
        "w-3 h-3 rounded-full",
        status_color(@status)
      ]}
      title={String.capitalize(to_string(@status))}
    >
    </div>
    """
  end

  # Helper Functions

  defp domain_icon(:thundercore), do: "⚡"
  defp domain_icon(:thunderbit), do: "🔥"
  defp domain_icon(:thunderbolt), do: "⚡"
  defp domain_icon(:thunderblock), do: "🏗️"
  defp domain_icon(:thundergrid), do: "🔷"
  defp domain_icon(:thunderblock_vault), do: "🗄️"
  defp domain_icon(:thundercom), do: "📡"
  defp domain_icon(:thundereye), do: "👁️"
  defp domain_icon(:thunderchief), do: "👑"
  defp domain_icon(:thunderflow), do: "🌊"
  defp domain_icon(:thunderstone), do: "🗿"
  defp domain_icon(:thunderlink), do: "🔗"
  defp domain_icon(:thundercrown), do: "👑"
  defp domain_icon(_), do: "⚙️"

  defp status_color(:active), do: "bg-green-400"
  defp status_color(:warning), do: "bg-yellow-400"
  defp status_color(:error), do: "bg-red-400"
  defp status_color(:degraded), do: "bg-orange-400"
  defp status_color(_), do: "bg-gray-400"

  defp metric_color_class("cyan"), do: "text-cyan-300"
  defp metric_color_class("green"), do: "text-green-300"
  defp metric_color_class("blue"), do: "text-blue-300"
  defp metric_color_class("purple"), do: "text-purple-300"
  defp metric_color_class("yellow"), do: "text-yellow-300"
  defp metric_color_class("red"), do: "text-red-300"
  defp metric_color_class("gray"), do: "text-gray-300"
  defp metric_color_class(_), do: "text-white"

  defp format_number(nil), do: "0"

  defp format_number(num) when is_integer(num) do
    cond do
      num >= 1_000_000 -> "#{Float.round(num / 1_000_000, 1)}M"
      num >= 1_000 -> "#{Float.round(num / 1_000, 1)}K"
      true -> to_string(num)
    end
  end

  defp format_number(num), do: to_string(num)

  defp format_percentage(nil), do: "0%"

  defp format_percentage(val) when is_float(val) do
    "#{Float.round(val * 100, 1)}%"
  end

  defp format_percentage(val), do: "#{val}%"
end
