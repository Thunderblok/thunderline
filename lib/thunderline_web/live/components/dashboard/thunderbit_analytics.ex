defmodule ThunderlineWeb.DashboardComponents.ThunderbitAnalytics do
  use Phoenix.Component

  attr :analytics, :map, required: true

  def thunderbit_analytics_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">🔥</div>
        <h3 class="text-lg font-bold text-white">ThunderBit Analytics</h3>
      </div>

      <div class="grid grid-cols-2 gap-3 mb-4">
        <div class="bg-black/20 rounded-lg p-3">
          <div class="text-xs text-gray-400 mb-1">Population</div>
          <div class="text-lg font-bold text-orange-300">
            <%= format_number(@analytics[:total_population]) %>
          </div>
        </div>
        <div class="bg-black/20 rounded-lg p-3">
          <div class="text-xs text-gray-400 mb-1">Active</div>
          <div class="text-lg font-bold text-red-300">
            <%= format_number(@analytics[:active_bits]) %>
          </div>
        </div>
      </div>

      <div class="mb-4">
        <div class="text-sm text-gray-300 mb-2">Birth/Death Rates</div>
        <div class="grid grid-cols-2 gap-2">
          <div class="bg-green-500/10 rounded-lg p-2">
            <div class="text-xs text-green-400">Birth Rate</div>
            <div class="text-sm font-mono text-green-300"><%= Float.round(@analytics[:birth_rate], 1) %>/s</div>
          </div>
          <div class="bg-red-500/10 rounded-lg p-2">
            <div class="text-xs text-red-400">Death Rate</div>
            <div class="text-sm font-mono text-red-300"><%= Float.round(@analytics[:death_rate], 1) %>/s</div>
          </div>
        </div>
      </div>

      <div class="flex-1">
        <div class="text-sm text-gray-300 mb-2">Pattern Types</div>
        <div class="space-y-2">
          <%= for {type, count} <- @analytics[:pattern_types] do %>
            <div class="flex justify-between items-center text-xs">
              <span class="text-gray-400 capitalize"><%= type %></span>
              <span class="text-orange-300 font-mono"><%= count %></span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
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
