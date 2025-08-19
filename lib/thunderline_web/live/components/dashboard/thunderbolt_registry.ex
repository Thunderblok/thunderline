defmodule ThunderlineWeb.DashboardComponents.ThunderboltRegistry do
  @moduledoc """
  ThunderBolt Registry Panel Component

  Real-time monitoring and management of active ThunderBolt cubes with
  performance metrics, controls, and creation interface.
  """

  use Phoenix.Component

  attr :thunderbolts, :list, required: true

  def thunderbolt_registry_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-3">
          <div class="text-2xl">⚡</div>
          <h3 class="text-lg font-bold text-white">ThunderBolt Registry</h3>
        </div>
        <button
          class="px-3 py-1 bg-cyan-500/20 hover:bg-cyan-500/30 border border-cyan-500/50 rounded-lg text-cyan-300 text-sm transition-colors"
          phx-click="show_create_modal"
        >
          + New
        </button>
      </div>

      <%!-- Stats Summary --%>
      <div class="grid grid-cols-2 gap-3 mb-4">
        <div class="bg-black/20 rounded-lg p-3">
          <div class="text-xs text-gray-400 mb-1">Active Cubes</div>
          <div class="text-lg font-bold text-cyan-300">
            {Enum.count(@thunderbolts, &(&1.status == :running))}
          </div>
        </div>
        <div class="bg-black/20 rounded-lg p-3">
          <div class="text-xs text-gray-400 mb-1">Avg FPS</div>
          <div class="text-lg font-bold text-green-300">
            {calculate_avg_fps(@thunderbolts)}
          </div>
        </div>
      </div>

      <%!-- ThunderBolt List --%>
      <div class="flex-1 overflow-y-auto space-y-3">
        <%= for bolt <- @thunderbolts do %>
          <div class={[
            "bg-black/20 rounded-lg p-4 border transition-all duration-300 hover:bg-black/30",
            thunderbolt_border_class(bolt.status)
          ]}>
            <%!-- Header Row --%>
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center space-x-3">
                <.status_indicator status={bolt.status} />
                <div>
                  <div class="font-medium text-white text-sm">{bolt.name}</div>
                  <div class="text-xs text-gray-400">ID: {bolt.id}</div>
                </div>
              </div>
              <.action_menu bolt_id={bolt.id} status={bolt.status} />
            </div>

            <%!-- Metrics Row --%>
            <div class="grid grid-cols-2 gap-3 mb-3">
              <div>
                <div class="text-xs text-gray-400">FPS</div>
                <div class="text-sm font-mono text-cyan-300">{bolt.fps}</div>
              </div>
              <div>
                <div class="text-xs text-gray-400">Generation</div>
                <div class="text-sm font-mono text-green-300">{format_number(bolt.generation)}</div>
              </div>
            </div>

            <%!-- Population Bar --%>
            <div class="mb-3">
              <div class="flex items-center justify-between mb-1">
                <span class="text-xs text-gray-400">Population</span>
                <span class="text-xs font-mono text-purple-300">
                  {format_number(bolt.population)}
                </span>
              </div>
              <div class="w-full bg-gray-700 rounded-full h-1.5">
                <div
                  class="bg-gradient-to-r from-purple-500 to-pink-500 h-1.5 rounded-full transition-all duration-1000"
                  style={"width: #{min(bolt.population / 1000, 100)}%"}
                >
                </div>
              </div>
            </div>

            <%!-- Energy Level --%>
            <div class="flex items-center justify-between">
              <span class="text-xs text-gray-400">Energy</span>
              <div class="flex items-center space-x-2">
                <div class="w-12 bg-gray-700 rounded-full h-1.5">
                  <div
                    class={[
                      "h-1.5 rounded-full transition-all duration-1000",
                      energy_color(bolt.energy)
                    ]}
                    style={"width: #{bolt.energy}%"}
                  >
                  </div>
                </div>
                <span class="text-xs font-mono text-yellow-300">{bolt.energy}%</span>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Performance Summary --%>
      <div class="mt-4 pt-4 border-t border-white/10">
        <div class="text-xs text-gray-400 mb-2">Performance</div>
        <div class="grid grid-cols-3 gap-2 text-xs">
          <div>
            <span class="text-gray-400">Speed:</span>
            <span class="text-cyan-300 font-mono ml-1">{calculate_avg_speed(@thunderbolts)}x</span>
          </div>
          <div>
            <span class="text-gray-400">Total Pop:</span>
            <span class="text-purple-300 font-mono ml-1">
              {format_number(calculate_total_population(@thunderbolts))}
            </span>
          </div>
          <div>
            <span class="text-gray-400">Efficiency:</span>
            <span class="text-green-300 font-mono ml-1">{calculate_efficiency(@thunderbolts)}%</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :status, :atom, required: true

  defp status_indicator(assigns) do
    ~H"""
    <div
      class={[
        "w-3 h-3 rounded-full border-2",
        status_indicator_class(@status)
      ]}
      title={status_title(@status)}
    >
    </div>
    """
  end

  attr :bolt_id, :string, required: true
  attr :status, :atom, required: true

  defp action_menu(assigns) do
    ~H"""
    <div class="flex items-center space-x-1">
      <%= case @status do %>
        <% :running -> %>
          <button
            phx-click="thunderbolt_action"
            phx-value-action="stop"
            phx-value-bolt_id={@bolt_id}
            class="px-2 py-1 bg-red-500/20 hover:bg-red-500/30 border border-red-500/50 rounded text-xs text-red-300 transition-colors"
          >
            Stop
          </button>
        <% :paused -> %>
          <button
            phx-click="thunderbolt_action"
            phx-value-action="start"
            phx-value-bolt_id={@bolt_id}
            class="px-2 py-1 bg-green-500/20 hover:bg-green-500/30 border border-green-500/50 rounded text-xs text-green-300 transition-colors"
          >
            Start
          </button>
        <% :error -> %>
          <button
            phx-click="thunderbolt_action"
            phx-value-action="restart"
            phx-value-bolt_id={@bolt_id}
            class="px-2 py-1 bg-yellow-500/20 hover:bg-yellow-500/30 border border-yellow-500/50 rounded text-xs text-yellow-300 transition-colors"
          >
            Restart
          </button>
        <% _ -> %>
          <button
            phx-click="thunderbolt_action"
            phx-value-action="start"
            phx-value-bolt_id={@bolt_id}
            class="px-2 py-1 bg-cyan-500/20 hover:bg-cyan-500/30 border border-cyan-500/50 rounded text-xs text-cyan-300 transition-colors"
          >
            Start
          </button>
      <% end %>
    </div>
    """
  end

  # Helper Functions

  defp thunderbolt_border_class(:running), do: "border-green-500/30"
  defp thunderbolt_border_class(:paused), do: "border-yellow-500/30"
  defp thunderbolt_border_class(:error), do: "border-red-500/30"
  defp thunderbolt_border_class(_), do: "border-gray-500/30"

  defp status_indicator_class(:running), do: "bg-green-400 border-green-300 animate-pulse"
  defp status_indicator_class(:paused), do: "bg-yellow-400 border-yellow-300"
  defp status_indicator_class(:error), do: "bg-red-400 border-red-300 animate-pulse"
  defp status_indicator_class(:starting), do: "bg-cyan-400 border-cyan-300 animate-spin"
  defp status_indicator_class(_), do: "bg-gray-400 border-gray-300"

  defp status_title(:running), do: "Running"
  defp status_title(:paused), do: "Paused"
  defp status_title(:error), do: "Error"
  defp status_title(:starting), do: "Starting"
  defp status_title(_), do: "Unknown"

  defp energy_color(energy) when energy > 80, do: "bg-green-400"
  defp energy_color(energy) when energy > 50, do: "bg-yellow-400"
  defp energy_color(energy) when energy > 20, do: "bg-orange-400"
  defp energy_color(_), do: "bg-red-400"

  defp calculate_avg_fps(thunderbolts) do
    case thunderbolts do
      [] ->
        0

      bolts ->
        running_bolts = Enum.filter(bolts, &(&1.status == :running))

        case running_bolts do
          [] ->
            0

          bolts ->
            (Enum.sum(Enum.map(bolts, & &1.fps)) / length(bolts))
            |> Float.round(1)
        end
    end
  end

  defp calculate_avg_speed(thunderbolts) do
    case thunderbolts do
      [] ->
        0.0

      bolts ->
        (Enum.sum(Enum.map(bolts, & &1.evolution_speed)) / length(bolts))
        |> Float.round(1)
    end
  end

  defp calculate_total_population(thunderbolts) do
    Enum.sum(Enum.map(thunderbolts, & &1.population))
  end

  defp calculate_efficiency(thunderbolts) do
    case thunderbolts do
      [] ->
        0

      bolts ->
        running_count = Enum.count(bolts, &(&1.status == :running))
        (running_count / length(bolts) * 100) |> Float.round(0) |> trunc()
    end
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
