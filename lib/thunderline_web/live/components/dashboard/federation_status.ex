defmodule ThunderlineWeb.DashboardComponents.FederationStatus do
  use Phoenix.Component

  attr :federation_data, :map, required: true

  def federation_status_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">🌐</div>
        <h3 class="text-lg font-bold text-white">Federation</h3>
      </div>

      <div class="space-y-4 flex-1">
        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="flex items-center justify-between mb-3">
            <span class="text-sm text-gray-300">Network Status</span>
            <div class={[
              "px-2 py-1 text-xs rounded-full",
              network_status_class(@federation_data.network_status)
            ]}>
              <%= String.upcase(@federation_data.network_status) %>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div class="text-center">
              <div class="text-xl font-bold text-cyan-300">
                <%= @federation_data.connected_nodes %>
              </div>
              <div class="text-xs text-gray-400">Nodes</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-bold text-purple-300">
                <%= @federation_data.sync_percentage %>%
              </div>
              <div class="text-xs text-gray-400">Sync</div>
            </div>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Active Connections</div>
          <div class="space-y-2">
            <%= for node <- @federation_data.nodes do %>
              <div class="flex items-center justify-between p-2 bg-black/20 rounded">
                <div class="flex items-center space-x-2">
                  <div class={[
                    "w-2 h-2 rounded-full",
                    node_status_class(node.status)
                  ]}></div>
                  <span class="text-xs text-gray-300"><%= node.name %></span>
                </div>
                <div class="flex items-center space-x-2">
                  <span class="text-xs text-gray-400"><%= node.latency %>ms</span>
                  <span class={[
                    "text-xs",
                    bandwidth_color(node.bandwidth)
                  ]}>
                    <%= node.bandwidth %>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-2">Mesh Health</div>
          <div class="flex justify-between text-xs">
            <span class="text-gray-400">Redundancy</span>
            <span class="text-green-300"><%= @federation_data.redundancy_level %></span>
          </div>
          <div class="flex justify-between text-xs">
            <span class="text-gray-400">Consensus</span>
            <span class="text-blue-300"><%= @federation_data.consensus_status %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp network_status_class("active"), do: "bg-green-500/20 text-green-300 border border-green-500/30"
  defp network_status_class("degraded"), do: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"
  defp network_status_class("critical"), do: "bg-red-500/20 text-red-300 border border-red-500/30"
  defp network_status_class(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp node_status_class("online"), do: "bg-green-400 animate-pulse"
  defp node_status_class("syncing"), do: "bg-yellow-400 animate-pulse"
  defp node_status_class("offline"), do: "bg-red-400"
  defp node_status_class(_), do: "bg-gray-400"

  defp bandwidth_color("high"), do: "text-green-300"
  defp bandwidth_color("medium"), do: "text-yellow-300"
  defp bandwidth_color("low"), do: "text-red-300"
  defp bandwidth_color(_), do: "text-gray-300"
end
