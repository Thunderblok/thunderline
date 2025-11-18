defmodule ThunderlineWeb.CommunityLive do
  @moduledoc """
  CommunityLive - Discord-style community (server) overview.

  Shows community header, channel list (grouped by category), member stats, and
  provides quick access to AI assistant & command palette.
  """
  use ThunderlineWeb, :live_view
  alias Thunderline.Thunderlink.Resources.{Community, Channel}
  alias Thunderline.Thunderlink.Domain
  # alias Thunderline.Thundercom.Topics # unused
  import Ash.Expr
  require Ash.Query

  require Logger

  @impl true
  def mount(%{"community_slug" => slug}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Thunderline.PubSub, community_topic(slug))

    case fetch_community(slug) do
      {:ok, community} ->
        {:ok,
         socket
         |> assign(:community, community)
         |> assign(:channels, load_channels(community.id))
         |> assign(:channel_groups, group_channels(load_channels(community.id)))
         |> assign(:ai_panel_open, false)
         |> assign(:command_mode, false)
         |> assign(:page_title, "#{community.community_name} · Community")}

      {:error, reason} ->
        Logger.warning("Community slug=#{slug} not found: #{inspect(reason)}")
        {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(%{"community_slug" => _slug}, _uri, socket) do
    # Refresh on param navigation
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_ai", _params, socket) do
    {:noreply, assign(socket, :ai_panel_open, !socket.assigns.ai_panel_open)}
  end

  def handle_event("toggle_command", _params, socket) do
    {:noreply, assign(socket, :command_mode, !socket.assigns.command_mode)}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:community_updated, %{community_id: id}}, socket) do
    if socket.assigns.community.id == id do
      {:noreply, refresh(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:channel_created, _payload}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full text-gray-200">
      <!-- Sidebar: channels -->
      <div class="w-64 bg-slate-900/80 backdrop-blur border-r border-slate-700/40 flex flex-col">
        <div class="p-4 border-b border-slate-700/40">
          <h1 class="text-lg font-semibold truncate" title={@community.community_name}>
            {@community.community_name}
          </h1>
          <p class="text-xs text-slate-400 mt-1">
            Channels: {@community.channel_count} · Members: {@community.member_count}
          </p>
        </div>
        <div class="flex-1 overflow-y-auto px-2 py-3 space-y-4">
          <%= for {category, channels} <- @channel_groups do %>
            <div>
              <div class="text-[10px] uppercase tracking-wide text-slate-400 px-1 mb-1">
                {category || "General"}
              </div>
              <div class="space-y-0.5">
                <%= for ch <- channels do %>
                  <.link
                    navigate={~p"/c/#{@community.community_slug}/#{ch.channel_slug}"}
                    class="flex items-center px-2 py-1.5 rounded hover:bg-slate-700/40 text-sm group"
                  >
                    <span class="text-slate-500 group-hover:text-slate-300 mr-2">
                      #{channel_icon(ch.channel_type)}
                    </span>
                    <span class="truncate">{ch.channel_name}</span>
                    <%= if ch.status == :locked do %>
                      <span class="ml-1 text-xs text-amber-400">🔒</span>
                    <% end %>
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        <div class="p-2 border-t border-slate-700/40 flex gap-2">
          <button
            phx-click="toggle_ai"
            class="flex-1 text-xs bg-indigo-600/20 hover:bg-indigo-600/30 rounded px-2 py-1 border border-indigo-500/40"
          >
            AI
          </button>
          <button
            phx-click="toggle_command"
            class="flex-1 text-xs bg-slate-600/20 hover:bg-slate-600/30 rounded px-2 py-1 border border-slate-500/40"
          >
            ⌘K
          </button>
        </div>
      </div>
      
    <!-- Main area placeholder -->
      <div class="flex-1 flex items-center justify-center bg-slate-950/60">
        <div class="text-center max-w-md">
          <h2 class="text-xl font-semibold mb-2">Select a Channel</h2>
          <p class="text-sm text-slate-400">
            Choose a channel from the left to start chatting. Use AI panel for assistance.
          </p>
        </div>
      </div>

      <%= if @ai_panel_open do %>
        <div class="w-80 border-l border-slate-700/40 bg-slate-900/70 backdrop-blur p-4 flex flex-col">
          <h3 class="text-sm font-semibold mb-2">AI Assistant (Stub)</h3>
          <p class="text-xs text-slate-400 mb-3">
            AshAI integration placeholder. Conversation context & tool usage will appear here.
          </p>
          <form phx-submit="noop" class="mt-auto flex flex-col gap-2">
            <textarea
              class="w-full h-24 text-xs bg-slate-800/60 rounded border border-slate-600/40 focus:outline-none focus:ring-1 focus:ring-indigo-500 resize-none p-2"
              placeholder="Ask the AI..."
            />
            <button class="text-xs bg-indigo-600/30 hover:bg-indigo-600/40 rounded px-2 py-1 border border-indigo-500/40 self-end">
              Send
            </button>
          </form>
        </div>
      <% end %>

      <%= if @command_mode do %>
        <div
          class="fixed inset-0 bg-black/50 flex items-start justify-center pt-32"
          phx-click="toggle_command"
        >
          <div
            class="bg-slate-900/90 backdrop-blur rounded-lg w-[640px] border border-slate-700/50 shadow-xl"
            phx-click="noop"
          >
            <div class="px-4 py-3 border-b border-slate-700/40 flex items-center gap-2">
              <span class="text-xs text-slate-400">Command Palette (Prototype)</span>
            </div>
            <div class="p-3">
              <input
                type="text"
                placeholder="Type a command..."
                class="w-full text-sm bg-slate-800/60 border border-slate-600/40 rounded px-3 py-2 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
              <ul class="mt-3 text-xs text-slate-400 space-y-1">
                <li>/join #channel</li>
                <li>/ai summarize recent</li>
                <li>/search term within #channel</li>
              </ul>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helpers
  defp fetch_community(slug) do
    Community
    |> Ash.Query.filter(expr(community_slug == ^slug))
    |> Ash.read_one(domain: Domain)
  end

  defp load_channels(community_id) do
    Channel
    |> Ash.Query.filter(expr(community_id == ^community_id and status == :active))
    |> Ash.read!(domain: Domain)
  rescue
    _ -> []
  end

  defp group_channels(channels) do
    channels
    |> Enum.group_by(& &1.channel_category)
    |> Enum.sort_by(fn {cat, _} -> cat || "" end)
  end

  defp refresh(socket) do
    comm = socket.assigns.community
    channels = load_channels(comm.id)
    assign(socket, channels: channels, channel_groups: group_channels(channels))
  end

  defp community_topic(slug), do: "thunderline:communities:" <> slug <> ":channels"

  defp channel_icon(:text), do: "#"
  defp channel_icon(:voice), do: "🔊"
  defp channel_icon(:announcement), do: "📢"
  defp channel_icon(:ai_agent), do: "🤖"
  defp channel_icon(:pac_coordination), do: "🧠"
  defp channel_icon(:media), do: "🖼️"
  defp channel_icon(:forum), do: "💬"
  defp channel_icon(_), do: "#"
end
