defmodule ThunderlineWeb.DashboardLive.Components.AutomataPanel do
  @moduledoc """
  3D Cellular Automata Panel Component for Thunderblock Dashboard
  
  Renders real-time 3D hexagonal grid with cellular automata states.
  """
  
  use Phoenix.Component
  import ThunderlineWeb.CoreComponents

  attr :state, :map, required: true
  attr :expanded, :boolean, default: false
  attr :class, :string, default: ""

  def automata_panel(assigns) do
    ~H"""
    <div class={[
      "backdrop-blur-md bg-gradient-to-br from-cyan-900/20 to-purple-900/20 rounded-2xl border border-cyan-400/30 p-6 relative overflow-hidden",
      @class
    ]}>
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6 relative z-10">
        <div class="flex items-center space-x-3">
          <div class="text-2xl">🔷</div>
          <h3 class="text-xl font-bold text-white">Thundergrid Automata</h3>
        </div>
        
        <div class="flex items-center space-x-4">
          <div class="text-sm text-cyan-300">
            Energy: <span class="font-mono"><%= @state[:energy_level] || 0 %>%</span>
          </div>
          <button 
            phx-click="toggle_automata"
            class="px-3 py-1 bg-cyan-500/20 hover:bg-cyan-500/30 border border-cyan-400/50 rounded-lg text-cyan-300 text-sm transition-colors"
          >
            <%= if @expanded, do: "Collapse", else: "Expand" %>
          </button>
        </div>
      </div>

      <%!-- 3D Hex Grid --%>
      <div class={[
        "relative flex items-center justify-center transition-all duration-500",
        @expanded && "h-96" || "h-48"
      ]} 
      id="hex-grid-container" 
      phx-hook="HexGrid"
      data-state={Jason.encode!(@state[:cell_states] || [])}>
        
        <%!-- 3D Perspective Container --%>
        <div class="hex-grid-3d" style="
          perspective: 1000px;
          transform-style: preserve-3d;
        ">
          <%= for cell <- (@state[:cell_states] || mock_cells()) do %>
            <div 
              class={[
                "hex-cell absolute transition-all duration-300 cursor-pointer",
                hex_cell_classes(cell[:state])
              ]}
              style={"#{hex_position_style(cell)} opacity: #{cell[:energy] / 100};"}
              phx-click="hex_click"
              phx-value-coords={Jason.encode!(%{q: cell[:q], r: cell[:r], s: cell[:s]})}
              title={"State: #{cell[:state]} | Energy: #{Float.round(cell[:energy], 1)}%"}
            >
              <%!-- Hex Shape --%>
              <div class="hex-inner w-8 h-8 relative">
                <div class="absolute inset-0 bg-current rounded-sm transform rotate-45"></div>
                <div class="absolute inset-1 bg-gray-900/80 rounded-sm transform rotate-45"></div>
                
                <%!-- Energy Indicator --%>
                <div class="absolute inset-2 flex items-center justify-center">
                  <div class={[
                    "w-2 h-2 rounded-full",
                    energy_indicator_class(cell[:energy])
                  ]}></div>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Grid Overlay --%>
        <div class="absolute inset-0 pointer-events-none">
          <svg class="w-full h-full opacity-20" viewBox="0 0 400 400">
            <defs>
              <pattern id="hexPattern" x="0" y="0" width="40" height="40" patternUnits="userSpaceOnUse">
                <polygon points="20,2 38,12 38,28 20,38 2,28 2,12" 
                         fill="none" 
                         stroke="currentColor" 
                         stroke-width="1" 
                         class="text-cyan-500"/>
              </pattern>
            </defs>
            <rect x="0" y="0" width="100%" height="100%" fill="url(#hexPattern)"/>
          </svg>
        </div>
      </div>

      <%!-- Stats Panel --%>
      <div class="mt-6 grid grid-cols-2 md:grid-cols-4 gap-4 relative z-10">
        <.stat_card 
          label="Active Zones" 
          value={@state[:active_zones] || 0}
          color="cyan"
          icon="🟢"
        />
        <.stat_card 
          label="Total Hexes" 
          value={@state[:total_hexes] || 144}
          color="blue"
          icon="⬢"
        />
        <.stat_card 
          label="Energy Level" 
          value="#{@state[:energy_level] || 0}%"
          color="yellow"
          icon="⚡"
        />
        <.stat_card 
          label="Last Update" 
          value={format_time(@state[:last_update])}
          color="purple"
          icon="🕐"
        />
      </div>

      <%!-- Background Animation --%>
      <div class="absolute inset-0 pointer-events-none">
        <div class="absolute top-0 left-0 w-full h-full bg-gradient-to-br from-transparent via-cyan-500/5 to-transparent animate-pulse"></div>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: "gray"
  attr :icon, :string, default: "📊"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3 border border-white/10">
      <div class="flex items-center space-x-2 mb-1">
        <span class="text-sm"><%= @icon %></span>
        <span class="text-xs text-gray-400 uppercase tracking-wide"><%= @label %></span>
      </div>
      <div class={[
        "text-lg font-mono font-bold",
        stat_color_class(@color)
      ]}>
        <%= @value %>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp hex_cell_classes(:active), do: "text-cyan-400 animate-pulse"
  defp hex_cell_classes(:processing), do: "text-yellow-400 animate-bounce"
  defp hex_cell_classes(:dormant), do: "text-gray-500"
  defp hex_cell_classes(_), do: "text-gray-600"

  defp hex_position_style(%{q: q, r: r}) do
    # Convert axial coordinates to pixel position
    x = 200 + (q * 30) + (r * 15)
    y = 200 + (r * 26)
    z = :rand.uniform(20) - 10  # Add slight Z variation
    
    "left: #{x}px; top: #{y}px; transform: translateZ(#{z}px);"
  end

  defp energy_indicator_class(energy) when energy > 80, do: "bg-green-400"
  defp energy_indicator_class(energy) when energy > 50, do: "bg-yellow-400"
  defp energy_indicator_class(energy) when energy > 20, do: "bg-orange-400"
  defp energy_indicator_class(_), do: "bg-red-400"

  defp stat_color_class("cyan"), do: "text-cyan-300"
  defp stat_color_class("blue"), do: "text-blue-300"
  defp stat_color_class("yellow"), do: "text-yellow-300"
  defp stat_color_class("purple"), do: "text-purple-300"
  defp stat_color_class(_), do: "text-white"

  defp format_time(nil), do: "Never"
  defp format_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
  defp format_time(_), do: "Unknown"

  defp mock_cells do
    # Generate mock cell data for testing
    for q <- -3..3, r <- -3..3, abs(q + r) <= 3 do
      %{
        q: q,
        r: r,
        s: -(q + r),
        state: Enum.random([:active, :dormant, :processing]),
        energy: :rand.uniform() * 100
      }
    end
  end
end