defmodule ThunderlineWeb.DashboardLive.Components.ChatPanel do
  @moduledoc """
  Chat Panel Component for Thunderblock Dashboard

  Displays real-time chat messages and social feed from Thunderblock communities.
  """

  use Phoenix.Component

  attr :messages, :list, default: []
  attr :class, :string, default: ""

  def chat_panel(assigns) do
    ~H"""
    <div class={[
      "backdrop-blur-md bg-gradient-to-br from-blue-900/20 to-purple-900/20 rounded-2xl border border-blue-400/30 p-4 h-80",
      @class
    ]}>
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-2">
          <div class="text-lg">💬</div>
          <h4 class="text-sm font-semibold text-white">Thunder Chat</h4>
        </div>
        <div class="flex items-center space-x-2">
          <div class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
          <span class="text-xs text-gray-400">Live</span>
        </div>
      </div>

      <%!-- Messages --%>
      <div class="flex-1 overflow-y-auto space-y-3 mb-4 h-48">
        <%= if Enum.empty?(@messages) do %>
          <%= for message <- mock_messages() do %>
            <.chat_message message={message} />
          <% end %>
        <% else %>
          <%= for message <- @messages do %>
            <.chat_message message={message} />
          <% end %>
        <% end %>
      </div>

      <%!-- Input Area --%>
      <div class="flex space-x-2">
        <input
          type="text"
          placeholder="Type a message..."
          class="flex-1 bg-black/30 border border-white/20 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-400 focus:outline-none focus:border-blue-400/50 focus:bg-black/40"
        />
        <button class="px-3 py-2 bg-blue-500/20 hover:bg-blue-500/30 border border-blue-400/50 rounded-lg text-blue-300 text-sm transition-colors">
          Send
        </button>
      </div>
    </div>
    """
  end

  # Helper Components

  attr :message, :map, required: true

  defp chat_message(assigns) do
    ~H"""
    <div class="flex space-x-2 text-xs">
      <%!-- Avatar --%>
      <div class={[
        "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold",
        avatar_color(@message.user_id)
      ]}>
        {String.first(@message.username)}
      </div>

      <%!-- Message Content --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-baseline space-x-2">
          <span class="font-semibold text-white">{@message.username}</span>
          <span class="text-gray-500">{format_message_time(@message.timestamp)}</span>
        </div>
        <p class="text-gray-300 break-words">{@message.content}</p>

        <%!-- Message Type Indicator --%>
        <%= if @message.type != :text do %>
          <div class="mt-1">
            <.message_type_badge type={@message.type} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :type, :atom, required: true

  defp message_type_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-1 rounded text-xs font-medium",
      type_badge_classes(@type)
    ]}>
      {type_icon(@type)} {String.capitalize(to_string(@type))}
    </span>
    """
  end

  # Helper Functions

  defp avatar_color(user_id) do
    colors = [
      "bg-red-500",
      "bg-blue-500",
      "bg-green-500",
      "bg-yellow-500",
      "bg-purple-500",
      "bg-pink-500",
      "bg-indigo-500",
      "bg-cyan-500"
    ]

    hash = :erlang.phash2(user_id, length(colors))
    Enum.at(colors, hash)
  end

  defp type_badge_classes(:system), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"
  defp type_badge_classes(:alert), do: "bg-red-500/20 text-red-300 border border-red-500/30"
  defp type_badge_classes(:event), do: "bg-blue-500/20 text-blue-300 border border-blue-500/30"
  defp type_badge_classes(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp type_icon(:system), do: "⚙️"
  defp type_icon(:alert), do: "⚠️"
  defp type_icon(:event), do: "📢"
  defp type_icon(:text), do: "💬"
  defp type_icon(_), do: "📝"

  defp format_message_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      true -> Calendar.strftime(datetime, "%m/%d")
    end
  end

  defp format_message_time(_), do: "now"

  defp mock_messages do
    [
      %{
        id: "1",
        user_id: "agent_alpha",
        username: "Agent Alpha",
        content: "Thundergrid energy levels stabilizing at 87%",
        timestamp: DateTime.add(DateTime.utc_now(), -300, :second),
        type: :system
      },
      %{
        id: "2",
        user_id: "thunder_ops",
        username: "ThunderOps",
        content: "New agent cluster deployed to Zone 4",
        timestamp: DateTime.add(DateTime.utc_now(), -240, :second),
        type: :event
      },
      %{
        id: "3",
        user_id: "neural_net_7",
        username: "Neural Net 7",
        content: "Processing 2.3K thunderbits per second",
        timestamp: DateTime.add(DateTime.utc_now(), -180, :second),
        type: :system
      },
      %{
        id: "4",
        user_id: "community_lead",
        username: "Community Lead",
        content: "Welcome to the Thunderblock Federation! 🎉",
        timestamp: DateTime.add(DateTime.utc_now(), -120, :second),
        type: :text
      },
      %{
        id: "5",
        user_id: "alert_system",
        username: "Alert System",
        content: "Memory optimization completed successfully",
        timestamp: DateTime.add(DateTime.utc_now(), -60, :second),
        type: :alert
      },
      %{
        id: "6",
        user_id: "automata_core",
        username: "Automata Core",
        content: "Cellular automata pattern: 144 hexes active",
        timestamp: DateTime.add(DateTime.utc_now(), -30, :second),
        type: :system
      }
    ]
  end
end
