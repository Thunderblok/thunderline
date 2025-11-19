defmodule ThunderlineWeb.DashboardLive.Components.ProfilePanel do
  @moduledoc """
  Profile Panel Component for Thunderblock Dashboard

  Displays profile updates, news feed, and recent activities from Thundervault.
  """

  use Phoenix.Component
  import ThunderlineWeb.CoreComponents

  attr :updates, :list, default: []
  attr :class, :string, default: ""

  def profile_panel(assigns) do
    ~H"""
    <div class={[
      "backdrop-blur-md bg-gradient-to-br from-purple-900/20 to-pink-900/20 rounded-2xl border border-purple-400/30 p-4 h-80",
      @class
    ]}>
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-2">
          <div class="text-lg">👤</div>
          <h4 class="text-sm font-semibold text-white">Activity Feed</h4>
        </div>
        <button class="text-xs text-purple-300 hover:text-purple-200 transition-colors">
          View All
        </button>
      </div>

      <%!-- Updates Feed --%>
      <div class="flex-1 overflow-y-auto space-y-3 h-56">
        <%= if Enum.empty?(@updates) do %>
          <%= for update <- mock_updates() do %>
            <.profile_update update={update} />
          <% end %>
        <% else %>
          <%= for update <- @updates do %>
            <.profile_update update={update} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :update, :map, required: true

  defp profile_update(assigns) do
    ~H"""
    <div class="flex space-x-3 p-3 bg-black/20 rounded-lg border border-white/5 hover:bg-black/30 transition-colors">
      <%!-- Activity Icon --%>
      <div class={[
        "w-8 h-8 rounded-full flex items-center justify-center text-sm",
        activity_icon_color(@update.type)
      ]}>
        {activity_icon(@update.type)}
      </div>

      <%!-- Update Content --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-baseline justify-between">
          <h5 class="text-sm font-semibold text-white truncate">{@update.title}</h5>
          <span class="text-xs text-gray-500 ml-2">{format_update_time(@update.timestamp)}</span>
        </div>

        <p class="text-xs text-gray-300 mt-1 line-clamp-2">{@update.description}</p>

        <%!-- Metrics --%>
        <%= if @update.metrics do %>
          <div class="flex items-center space-x-4 mt-2">
            <%= for {key, value} <- @update.metrics do %>
              <div class="flex items-center space-x-1">
                <span class="text-xs text-gray-500">{format_metric_key(key)}:</span>
                <span class="text-xs font-mono text-purple-300">{value}</span>
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Tags --%>
        <%= if @update.tags && !Enum.empty?(@update.tags) do %>
          <div class="flex flex-wrap gap-1 mt-2">
            <%= for tag <- Enum.take(@update.tags, 3) do %>
              <span class="inline-block px-2 py-1 bg-purple-500/20 text-purple-300 text-xs rounded border border-purple-500/30">
                {tag}
              </span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp activity_icon(:memory), do: "🧠"
  defp activity_icon(:knowledge), do: "📚"
  defp activity_icon(:experience), do: "⭐"
  defp activity_icon(:decision), do: "⚖️"
  defp activity_icon(:system), do: "⚙️"
  defp activity_icon(:user), do: "👤"
  defp activity_icon(:post), do: "📝"
  defp activity_icon(:achievement), do: "🏆"
  defp activity_icon(_), do: "📊"

  defp activity_icon_color(:memory), do: "bg-cyan-500/20 text-cyan-400"
  defp activity_icon_color(:knowledge), do: "bg-blue-500/20 text-blue-400"
  defp activity_icon_color(:experience), do: "bg-yellow-500/20 text-yellow-400"
  defp activity_icon_color(:decision), do: "bg-green-500/20 text-green-400"
  defp activity_icon_color(:system), do: "bg-gray-500/20 text-gray-400"
  defp activity_icon_color(:user), do: "bg-purple-500/20 text-purple-400"
  defp activity_icon_color(:post), do: "bg-pink-500/20 text-pink-400"
  defp activity_icon_color(:achievement), do: "bg-orange-500/20 text-orange-400"
  defp activity_icon_color(_), do: "bg-gray-500/20 text-gray-400"

  defp format_update_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86_400)}d"
      true -> Calendar.strftime(datetime, "%m/%d")
    end
  end

  defp format_update_time(_), do: "now"

  defp format_metric_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp mock_updates do
    [
      %{
        id: "1",
        type: :memory,
        title: "Memory Record Created",
        description: "New episodic memory logged for agent interaction sequence #2847",
        timestamp: DateTime.add(DateTime.utc_now(), -180, :second),
        metrics: %{confidence: "94%", recall_strength: "8.7"},
        tags: ["episodic", "agent-interaction", "high-confidence"]
      },
      %{
        id: "2",
        type: :knowledge,
        title: "Knowledge Graph Updated",
        description: "Added 23 new knowledge nodes connecting Thunderbit processing patterns",
        timestamp: DateTime.add(DateTime.utc_now(), -420, :second),
        metrics: %{nodes_added: 23, connections: 67},
        tags: ["knowledge-graph", "thunderbit", "patterns"]
      },
      %{
        id: "3",
        type: :experience,
        title: "Experience Synthesis",
        description: "Synthesized learning from 1,247 agent decisions into actionable insights",
        timestamp: DateTime.add(DateTime.utc_now(), -720, :second),
        metrics: %{decisions: "1.2K", accuracy: "96.3%"},
        tags: ["synthesis", "learning", "insights"]
      },
      %{
        id: "4",
        type: :decision,
        title: "Decision Framework Updated",
        description: "Updated decision weights based on recent Thundergrid optimization results",
        timestamp: DateTime.add(DateTime.utc_now(), -980, :second),
        metrics: %{weight_changes: 12, performance_gain: "+8.4%"},
        tags: ["decision-framework", "optimization", "thundergrid"]
      },
      %{
        id: "5",
        type: :post,
        title: "Community Post",
        description: "Agent Alpha shared insights on efficient chunk processing strategies",
        timestamp: DateTime.add(DateTime.utc_now(), -1260, :second),
        metrics: %{likes: 34, comments: 7},
        tags: ["community", "chunk-processing", "strategy"]
      },
      %{
        id: "6",
        type: :achievement,
        title: "Milestone Reached",
        description: "Thundervault has successfully processed 1 million memory records!",
        timestamp: DateTime.add(DateTime.utc_now(), -1800, :second),
        metrics: %{total_records: "1M", processing_time: "2.3ms avg"},
        tags: ["milestone", "memory", "performance"]
      }
    ]
  end
end
