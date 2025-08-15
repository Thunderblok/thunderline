defmodule ThunderlineWeb.DashboardComponents.AlertManager do
  use Phoenix.Component

  attr :alerts_data, :map, required: true

  def alert_manager_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">🚨</div>
        <h3 class="text-lg font-bold text-white">Alert Manager</h3>
      </div>

      <div class="space-y-4 flex-1">
        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="flex items-center justify-between mb-3">
            <span class="text-sm text-gray-300">Alert Status</span>
            <div class={[
              "px-2 py-1 text-xs rounded-full",
              alert_status_class(@alerts_data.overall_status)
            ]}>
              <%= String.upcase(@alerts_data.overall_status) %>
            </div>
          </div>

          <div class="grid grid-cols-4 gap-2">
            <div class="text-center">
              <div class="text-lg font-bold text-red-300">
                <%= @alerts_data.critical_count %>
              </div>
              <div class="text-xs text-gray-400">Critical</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-bold text-orange-300">
                <%= @alerts_data.high_count %>
              </div>
              <div class="text-xs text-gray-400">High</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-bold text-yellow-300">
                <%= @alerts_data.medium_count %>
              </div>
              <div class="text-xs text-gray-400">Medium</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-bold text-blue-300">
                <%= @alerts_data.low_count %>
              </div>
              <div class="text-xs text-gray-400">Low</div>
            </div>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Recent Alerts</div>
          <div class="space-y-2 max-h-40 overflow-y-auto">
            <%= for alert <- @alerts_data.recent_alerts do %>
              <div class="flex items-start justify-between p-2 bg-black/20 rounded">
                <div class="flex items-start space-x-2 flex-1 min-w-0">
                  <div class={[
                    "w-2 h-2 rounded-full mt-1 flex-shrink-0",
                    alert_severity_indicator(alert.severity)
                  ]}></div>
                  <div class="min-w-0 flex-1">
                    <div class="text-xs text-gray-300 truncate"><%= alert.title %></div>
                    <div class="text-xs text-gray-500 truncate"><%= alert.description %></div>
                  </div>
                </div>
                <div class="flex flex-col items-end space-y-1 flex-shrink-0 ml-2">
                  <span class={[
                    "text-xs px-1 py-0.5 rounded",
                    alert_severity_class(alert.severity)
                  ]}>
                    <%= alert.severity %>
                  </span>
                  <span class="text-xs text-gray-400">
                    <%= format_alert_time(alert.timestamp) %>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Alert Rules</div>
          <div class="space-y-2">
            <%= for rule <- @alerts_data.alert_rules do %>
              <div class="flex items-center justify-between p-2 bg-black/20 rounded">
                <div class="flex items-center space-x-2">
                  <div class={[
                    "w-2 h-2 rounded-full",
                    rule_status_indicator(rule.status)
                  ]}></div>
                  <span class="text-xs text-gray-300"><%= rule.name %></span>
                </div>
                <div class="flex items-center space-x-2">
                  <span class="text-xs text-gray-400">
                    <%= rule.trigger_count %> triggers
                  </span>
                  <span class={[
                    "text-xs px-1 py-0.5 rounded",
                    rule_status_class(rule.status)
                  ]}>
                    <%= rule.status %>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-2">Notification Channels</div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-gray-400">Email</span>
            <span class={channel_status_color(@alerts_data.channels.email)}>
              <%= String.upcase(@alerts_data.channels.email) %>
            </span>
          </div>
          <div class="flex justify-between text-xs mb-1">
            <span class="text-gray-400">Slack</span>
            <span class={channel_status_color(@alerts_data.channels.slack)}>
              <%= String.upcase(@alerts_data.channels.slack) %>
            </span>
          </div>
          <div class="flex justify-between text-xs">
            <span class="text-gray-400">PagerDuty</span>
            <span class={channel_status_color(@alerts_data.channels.pagerduty)}>
              <%= String.upcase(@alerts_data.channels.pagerduty) %>
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp alert_status_class("normal"), do: "bg-green-500/20 text-green-300 border border-green-500/30"
  defp alert_status_class("warning"), do: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"
  defp alert_status_class("critical"), do: "bg-red-500/20 text-red-300 border border-red-500/30"
  defp alert_status_class(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp alert_severity_indicator("critical"), do: "bg-red-400 animate-pulse"
  defp alert_severity_indicator("high"), do: "bg-orange-400"
  defp alert_severity_indicator("medium"), do: "bg-yellow-400"
  defp alert_severity_indicator("low"), do: "bg-blue-400"
  defp alert_severity_indicator(_), do: "bg-gray-400"

  defp alert_severity_class("critical"), do: "bg-red-500/20 text-red-300"
  defp alert_severity_class("high"), do: "bg-orange-500/20 text-orange-300"
  defp alert_severity_class("medium"), do: "bg-yellow-500/20 text-yellow-300"
  defp alert_severity_class("low"), do: "bg-blue-500/20 text-blue-300"
  defp alert_severity_class(_), do: "bg-gray-500/20 text-gray-300"

  defp rule_status_indicator("active"), do: "bg-green-400"
  defp rule_status_indicator("triggered"), do: "bg-red-400 animate-pulse"
  defp rule_status_indicator("disabled"), do: "bg-gray-400"
  defp rule_status_indicator(_), do: "bg-yellow-400"

  defp rule_status_class("active"), do: "bg-green-500/20 text-green-300"
  defp rule_status_class("triggered"), do: "bg-red-500/20 text-red-300"
  defp rule_status_class("disabled"), do: "bg-gray-500/20 text-gray-300"
  defp rule_status_class(_), do: "bg-yellow-500/20 text-yellow-300"

  defp channel_status_color("active"), do: "text-green-300"
  defp channel_status_color("degraded"), do: "text-yellow-300"
  defp channel_status_color("down"), do: "text-red-300"
  defp channel_status_color(_), do: "text-gray-300"

  defp format_alert_time(timestamp) do
    timestamp
    |> NaiveDateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)
  end
end
