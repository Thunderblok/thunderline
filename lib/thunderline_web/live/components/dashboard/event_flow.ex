defmodule ThunderlineWeb.DashboardComponents.EventFlow do
  use Phoenix.Component

  attr :events, :list, required: true

  def event_flow_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">⚡</div>
        <h3 class="text-lg font-bold text-white">Event Flow</h3>
      </div>

      <div class="flex-1 overflow-hidden">
        <div class="space-y-2 h-full overflow-y-auto">
          <%= for event <- @events do %>
            <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3 border border-white/5">
              <div class="flex items-center justify-between mb-2">
                <span class={[
                  "px-2 py-1 text-xs rounded-full",
                  event_type_class(event.type)
                ]}>
                  <%= event.type %>
                </span>
                <span class="text-xs text-gray-400">
                  <%= format_timestamp(event.timestamp) %>
                </span>
              </div>
              <div class="text-sm text-gray-300 truncate">
                <%= event.message %>
              </div>
              <div class="flex items-center justify-between mt-2">
                <span class="text-xs text-gray-500"><%= event.source %></span>
                <div class={[
                  "w-2 h-2 rounded-full animate-pulse",
                  status_indicator_class(event.status)
                ]}></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp event_type_class("thunderbolt"), do: "bg-blue-500/20 text-blue-300 border border-blue-500/30"
  defp event_type_class("thunderbit"), do: "bg-purple-500/20 text-purple-300 border border-purple-500/30"
  defp event_type_class("domain"), do: "bg-green-500/20 text-green-300 border border-green-500/30"
  defp event_type_class("system"), do: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"
  defp event_type_class(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp status_indicator_class("processing"), do: "bg-yellow-400"
  defp status_indicator_class("completed"), do: "bg-green-400"
  defp status_indicator_class("error"), do: "bg-red-400"
  defp status_indicator_class(_), do: "bg-gray-400"

  defp format_timestamp(timestamp) do
    timestamp
    |> NaiveDateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)
  end
end
