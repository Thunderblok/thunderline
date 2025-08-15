defmodule ThunderlineWeb.DashboardComponents.OrchestrationEngine do
  use Phoenix.Component

  attr :orchestration_data, :map, required: true

  def orchestration_engine_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">🎭</div>
        <h3 class="text-lg font-bold text-white">Orchestration</h3>
      </div>

      <div class="space-y-4 flex-1">
        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="flex items-center justify-between mb-3">
            <span class="text-sm text-gray-300">Engine Status</span>
            <div class={[
              "px-2 py-1 text-xs rounded-full animate-pulse",
              engine_status_class(@orchestration_data.engine_status)
            ]}>
              <%= String.upcase(@orchestration_data.engine_status) %>
            </div>
          </div>

          <div class="grid grid-cols-3 gap-2">
            <div class="text-center">
              <div class="text-lg font-bold text-blue-300">
                <%= @orchestration_data.active_workflows %>
              </div>
              <div class="text-xs text-gray-400">Workflows</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-bold text-purple-300">
                <%= @orchestration_data.queued_tasks %>
              </div>
              <div class="text-xs text-gray-400">Queued</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-bold text-green-300">
                <%= @orchestration_data.completion_rate %>%
              </div>
              <div class="text-xs text-gray-400">Success</div>
            </div>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Active Processes</div>
          <div class="space-y-2 max-h-32 overflow-y-auto">
            <%= for process <- @orchestration_data.processes do %>
              <div class="flex items-center justify-between p-2 bg-black/20 rounded">
                <div class="flex items-center space-x-2">
                  <div class={[
                    "w-2 h-2 rounded-full",
                    process_status_class(process.status)
                  ]}></div>
                  <span class="text-xs text-gray-300 truncate"><%= process.name %></span>
                </div>
                <div class="flex items-center space-x-2">
                  <span class="text-xs text-gray-400"><%= process.progress %>%</span>
                  <span class={[
                    "text-xs px-1 py-0.5 rounded text-xs",
                    priority_class(process.priority)
                  ]}>
                    <%= process.priority %>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-2">Resource Allocation</div>
          <div class="space-y-2">
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">CPU Cores</span>
              <span class="text-cyan-300"><%= @orchestration_data.allocated_cores %> / <%= @orchestration_data.total_cores %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Memory</span>
              <span class="text-purple-300"><%= @orchestration_data.memory_usage %>%</span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Network I/O</span>
              <span class="text-yellow-300"><%= @orchestration_data.network_throughput %> Mbps</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp engine_status_class("running"), do: "bg-green-500/20 text-green-300 border border-green-500/30"
  defp engine_status_class("scaling"), do: "bg-blue-500/20 text-blue-300 border border-blue-500/30"
  defp engine_status_class("maintenance"), do: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"
  defp engine_status_class("error"), do: "bg-red-500/20 text-red-300 border border-red-500/30"
  defp engine_status_class(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp process_status_class("running"), do: "bg-green-400 animate-pulse"
  defp process_status_class("waiting"), do: "bg-yellow-400"
  defp process_status_class("suspended"), do: "bg-gray-400"
  defp process_status_class("error"), do: "bg-red-400"
  defp process_status_class(_), do: "bg-blue-400"

  defp priority_class("high"), do: "bg-red-500/20 text-red-300"
  defp priority_class("medium"), do: "bg-yellow-500/20 text-yellow-300"
  defp priority_class("low"), do: "bg-green-500/20 text-green-300"
  defp priority_class(_), do: "bg-gray-500/20 text-gray-300"
end
