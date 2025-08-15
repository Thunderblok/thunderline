defmodule ThunderlineWeb.DashboardComponents.SystemControls do
  use Phoenix.Component

  attr :controls_data, :map, required: true

  def system_controls_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">🎛️</div>
        <h3 class="text-lg font-bold text-white">System Controls</h3>
      </div>

      <div class="space-y-4 flex-1">
        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Quick Actions</div>
          <div class="grid grid-cols-2 gap-2">
            <button 
              phx-click="system_control"
              phx-value-action="emergency_stop"
              class="bg-gradient-to-r from-blue-500/20 to-cyan-500/20 border border-blue-500/30 rounded-lg p-2 text-xs text-blue-300 hover:from-blue-500/30 hover:to-cyan-500/30 transition-all duration-200"
            >
              Emergency Stop
            </button>
            <button 
              phx-click="system_control"
              phx-value-action="system_restart"
              class="bg-gradient-to-r from-green-500/20 to-emerald-500/20 border border-green-500/30 rounded-lg p-2 text-xs text-green-300 hover:from-green-500/30 hover:to-emerald-500/30 transition-all duration-200"
            >
              System Restart
            </button>
            <button 
              phx-click="system_control"
              phx-value-action="safe_mode"
              class="bg-gradient-to-r from-purple-500/20 to-pink-500/20 border border-purple-500/30 rounded-lg p-2 text-xs text-purple-300 hover:from-purple-500/30 hover:to-pink-500/30 transition-all duration-200"
            >
              Safe Mode
            </button>
            <button 
              phx-click="system_control"
              phx-value-action="maintenance_mode"
              class="bg-gradient-to-r from-yellow-500/20 to-orange-500/20 border border-yellow-500/30 rounded-lg p-2 text-xs text-yellow-300 hover:from-yellow-500/30 hover:to-orange-500/30 transition-all duration-200"
            >
              Maintenance
            </button>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">System Parameters</div>
          <div class="space-y-3">
            <div>
              <div class="flex justify-between text-xs mb-1">
                <span class="text-gray-400">Throttle Limit</span>
                <span class="text-cyan-300"><%= @controls_data.throttle_limit %>%</span>
              </div>
              <div class="w-full bg-black/30 rounded-full h-1.5">
                <div
                  class="bg-gradient-to-r from-cyan-500 to-blue-500 h-1.5 rounded-full transition-all duration-300"
                  style={"width: #{@controls_data.throttle_limit}%"}
                ></div>
              </div>
            </div>

            <div>
              <div class="flex justify-between text-xs mb-1">
                <span class="text-gray-400">Auto-Scale</span>
                <span class="text-purple-300"><%= @controls_data.auto_scale_level %>%</span>
              </div>
              <div class="w-full bg-black/30 rounded-full h-1.5">
                <div
                  class="bg-gradient-to-r from-purple-500 to-pink-500 h-1.5 rounded-full transition-all duration-300"
                  style={"width: #{@controls_data.auto_scale_level}%"}
                ></div>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Circuit Breakers</div>
          <div class="space-y-2">
            <%= for breaker <- @controls_data.circuit_breakers do %>
              <div class="flex items-center justify-between p-2 bg-black/20 rounded">
                <span class="text-xs text-gray-300"><%= breaker.name %></span>
                <div class="flex items-center space-x-2">
                  <span class="text-xs text-gray-400"><%= breaker.failure_rate %>%</span>
                  <div class={[
                    "w-3 h-3 rounded-full border-2",
                    breaker_status_class(breaker.status)
                  ]}>
                    <div class={[
                      "w-full h-full rounded-full",
                      breaker_indicator_class(breaker.status)
                    ]}></div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-2">System State</div>
          <div class="space-y-1">
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Uptime</span>
              <span class="text-green-300"><%= @controls_data.uptime %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Last Restart</span>
              <span class="text-blue-300"><%= @controls_data.last_restart %></span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Boot Mode</span>
              <span class="text-purple-300"><%= @controls_data.boot_mode %></span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp breaker_status_class("closed"), do: "border-green-400"
  defp breaker_status_class("open"), do: "border-red-400"
  defp breaker_status_class("half-open"), do: "border-yellow-400"
  defp breaker_status_class(_), do: "border-gray-400"

  defp breaker_indicator_class("closed"), do: "bg-green-400"
  defp breaker_indicator_class("open"), do: "bg-red-400 animate-pulse"
  defp breaker_indicator_class("half-open"), do: "bg-yellow-400 animate-pulse"
  defp breaker_indicator_class(_), do: "bg-gray-400"
end
