defmodule ThunderlineWeb.ChannelLive do
  @moduledoc """
  ChannelLive - Discord-style channel real-time chat & AI integration stub.

  Renders message stream, input box, minimal presence, and AI side thread.
  """
  use ThunderlineWeb, :live_view
  alias Thunderline.Thunderlink.Resources.{Community, Channel, Message}
  alias Thunderline.Thunderlink.{Domain, Topics}
  alias ThunderlineWeb.Presence
  require Logger
  import Ash.Expr
  require Ash.Query

  @message_limit 100

  @impl true
  def mount(%{"community_slug" => cslug, "channel_slug" => chslug}, _session, socket) do
    with {:ok, community} <- fetch_community(cslug),
         {:ok, channel} <- fetch_channel(community.id, chslug) do
      # Presence / membership enforcement (ANVIL Priority A)
      actor_ctx = socket.assigns[:actor_ctx]
      case Thunderline.Thunderlink.Presence.Policy.decide(:join, {:channel, channel.id}, actor_ctx) do
        {:deny, reason} ->
          :telemetry.execute([:thunderline, :link, :presence, :blocked_live_mount], %{count: 1}, %{channel_id: channel.id, reason: reason, actor: actor_ctx && actor_ctx.actor_id})
          return_path = "/c/#{community.community_slug}"
          {:ok, socket |> put_flash(:error, "access denied (presence)") |> push_navigate(to: return_path)}
        {:allow, _} ->
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Thunderline.PubSub, Topics.channel_messages(channel.id))
            Phoenix.PubSub.subscribe(Thunderline.PubSub, Topics.channel_reactions(channel.id))
            Phoenix.PubSub.subscribe(Thunderline.PubSub, Topics.channel_presence(channel.id))
            anon_user = presence_identity(actor_ctx)
            Presence.track_channel(self(), channel.id, anon_user)
          end

      {:ok,
       socket
       |> assign(:community, community)
       |> assign(:channel, channel)
       |> assign(:messages, load_messages(channel.id))
       |> assign(:new_message, "")
       |> assign(:ai_thread, [])
       |> assign(:ai_mode, false)
  |> assign(:page_title, "#{channel.channel_name} · #{community.community_name}")
  |> assign(:presence_users, list_channel_presence(channel.id))}
    else
      end
    else
      _ -> {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_message", %{"value" => v}, socket) do
    {:noreply, assign(socket, :new_message, v)}
  end

  def handle_event("send", _params, %{assigns: %{new_message: ""}} = socket), do: {:noreply, socket}
  def handle_event("send", _params, socket) do
    content = String.trim(socket.assigns.new_message)
    if content != "" do
      channel = socket.assigns.channel
      actor_ctx = socket.assigns[:actor_ctx]
      case Thunderline.Thunderlink.Presence.Policy.decide(:send, {:channel, channel.id}, actor_ctx) do
        {:deny, reason} ->
          :telemetry.execute([:thunderline, :link, :presence, :blocked_live_send], %{count: 1}, %{channel_id: channel.id, reason: reason, actor: actor_ctx && actor_ctx.actor_id})
          :ok
        {:allow, _} ->
          send_message(channel, content, actor_ctx)
      end
    end
    {:noreply, assign(socket, :new_message, "")}
  end

  def handle_event("toggle_ai", _params, socket) do
    {:noreply, assign(socket, :ai_mode, !socket.assigns.ai_mode)}
  end

  def handle_event("ai_prompt", %{"prompt" => %{"content" => content}}, socket) when content != "" do
    # Stub AI response - later integrate AshAI pipeline/tooling
    ai_msg = %{id: System.unique_integer(), role: :ai, content: "(AI Stub) #{content}"}
    {:noreply, update(socket, :ai_thread, fn t -> [ai_msg | t] |> Enum.take(@message_limit) end)}
  end

  def handle_event("ai_prompt", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, update(socket, :messages, fn ms -> (ms ++ [message]) |> Enum.take(-@message_limit) end)}
  end

  def handle_info({:message_deleted, %{message_id: id}}, socket) do
    {:noreply, update(socket, :messages, fn ms -> Enum.reject(ms, &(&1.id == id)) end)}
  end

  def handle_info({:message_edited, message}, socket) do
    {:noreply,
     update(socket, :messages, fn ms ->
       Enum.map(ms, fn m -> if m.id == message.id, do: message, else: m end)
     end)}
  end

  def handle_info({:reaction_update, %{message_id: _id}} = _msg, socket) do
    # For now we ignore updating reaction counts - placeholder
    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic}, socket) do
    channel_id = socket.assigns.channel.id
    if topic == Topics.channel_presence(channel_id) do
      {:noreply, assign(socket, :presence_users, list_channel_presence(channel_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full bg-slate-950/70 text-slate-100">
      <!-- Channel sidebar (mini) -->
      <div class="w-56 bg-slate-900/80 border-r border-slate-700/40 p-3 flex flex-col">
        <.link navigate={~p"/c/#{@community.community_slug}"} class="text-xs text-slate-400 hover:text-slate-200 mb-2">← Back</.link>
        <h2 class="text-sm font-semibold mb-1 truncate">#{channel_icon(@channel.channel_type)} {@channel.channel_name}</h2>
        <p class="text-[11px] text-slate-500 leading-snug mb-3 line-clamp-3">{@channel.topic || "No topic set"}</p>
        <div class="mb-3">
          <div class="text-[10px] uppercase tracking-wide text-slate-500 mb-1">Active</div>
          <div class="flex flex-wrap gap-1">
            <%= for u <- @presence_users do %>
              <span class="px-1.5 py-0.5 rounded bg-slate-700/40 text-[10px]" title={u}>{String.slice(u,0,6)}</span>
            <% end %>
          </div>
        </div>
        <div class="mt-auto flex gap-2">
          <button phx-click="toggle_ai" class="flex-1 text-[10px] bg-indigo-600/20 hover:bg-indigo-600/30 rounded px-2 py-1 border border-indigo-500/40">AI</button>
        </div>
      </div>

      <!-- Messages -->
      <div class="flex-1 flex flex-col">
        <div id="messages" phx-hook="AutoScroll" class="flex-1 overflow-y-auto p-4 space-y-3 text-sm">
          <%= for m <- @messages do %>
            <div id={"m-#{m.id}"} class="group">
              <div class="flex items-start gap-2">
                <div class="w-8 h-8 rounded bg-slate-700/50 flex items-center justify-center text-[11px] font-medium">{short_id(m.sender_id)}</div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="font-semibold">{display_sender(m)}</span>
                    <span class="text-[10px] text-slate-500">{format_ts(m.inserted_at)}</span>
                    <%= if m.status != :active do %>
                      <span class="text-[10px] text-amber-400 uppercase">{to_string(m.status)}</span>
                    <% end %>
                  </div>
                  <div class="whitespace-pre-wrap break-words leading-relaxed">{m.content}</div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        <form phx-submit="send" class="p-3 border-t border-slate-700/40 flex gap-2">
          <input name="content" value={@new_message} phx-change="update_message" phx-debounce="50" placeholder="Message ##{@channel.channel_slug}" class="flex-1 bg-slate-800/60 border border-slate-600/40 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-indigo-500" />
          <button class="bg-indigo-600/30 hover:bg-indigo-600/40 border border-indigo-500/40 rounded px-4 text-sm">Send</button>
        </form>
      </div>

      <!-- AI Thread -->
      <%= if @ai_mode do %>
        <div class="w-80 border-l border-slate-700/40 bg-slate-900/70 backdrop-blur flex flex-col">
          <div class="p-3 border-b border-slate-700/40 flex items-center justify-between">
            <h3 class="text-xs font-semibold">AI Thread (Stub)</h3>
            <button phx-click="toggle_ai" class="text-[10px] text-slate-400 hover:text-slate-200">✕</button>
          </div>
          <div class="flex-1 overflow-y-auto p-3 space-y-3 text-xs">
            <%= if @ai_thread == [] do %>
              <p class="text-slate-500">Start a prompt below. Future: tool calls, context window, memory.</p>
            <% else %>
              <%= for a <- @ai_thread do %>
                <div class={["border rounded p-2", ai_bubble_classes(a.role)]}>{a.content}</div>
              <% end %>
            <% end %>
          </div>
          <form phx-submit="ai_prompt" class="p-3 border-t border-slate-700/40 space-y-2">
            <textarea name="prompt[content]" class="w-full h-24 text-xs bg-slate-800/60 rounded border border-slate-600/40 focus:outline-none focus:ring-1 focus:ring-indigo-500 resize-none p-2" placeholder="Ask the AI about this channel..." />
            <button class="w-full text-xs bg-indigo-600/30 hover:bg-indigo-600/40 rounded px-2 py-1 border border-indigo-500/40">Send Prompt</button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  # Data ops
  defp fetch_community(slug) do
    Community
    |> Ash.Query.filter(expr(community_slug == ^slug))
    |> Ash.read_one(domain: Domain)
  end

  defp fetch_channel(community_id, slug) do
    Channel
    |> Ash.Query.filter(expr(community_id == ^community_id and channel_slug == ^slug))
    |> Ash.read_one(domain: Domain)
  end

  defp load_messages(channel_id) do
    Message
    |> Ash.Query.filter(expr(channel_id == ^channel_id and status in [:active, :edited]))
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(domain: Domain)
  rescue
    _ -> []
  end

  defp send_message(channel, content, actor_ctx) do
    # Actor derived sender; fallback ephemeral if missing (should be denied earlier)
    sender_id = if actor_ctx, do: actor_ctx.actor_id, else: Ash.UUID.generate()
    Message.create(%{
      content: content,
      channel_id: channel.id,
      community_id: channel.community_id,
      sender_id: sender_id
    })
  rescue
    e -> Logger.error("Failed to send message: #{inspect(e)}")
  end

  # UI helpers
  defp channel_icon(:text), do: "#"
  defp channel_icon(:voice), do: "🔊"
  defp channel_icon(:announcement), do: "📢"
  defp channel_icon(:ai_agent), do: "🤖"
  defp channel_icon(:pac_coordination), do: "🧠"
  defp channel_icon(:media), do: "🖼️"
  defp channel_icon(:forum), do: "💬"
  defp channel_icon(_), do: "#"

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 4)
  defp short_id(_), do: "usr"

  defp display_sender(m) do
    case m.sender_type do
      :ai_agent -> "AI"
      :pac_agent -> "PAC"
      :system -> "System"
      _ -> short_id(m.sender_id)
    end
  end

  defp format_ts(nil), do: "now"
  defp format_ts(%DateTime{} = dt) do
    case DateTime.to_time(dt) do
      %Time{hour: h, minute: m} -> :io_lib.format("~2..0B:~2..0B", [h, m]) |> to_string()
      _ -> "now"
    end
  end
  defp format_ts(_), do: "now"

  defp ai_bubble_classes(:ai), do: "bg-indigo-600/20 border border-indigo-500/30"
  defp ai_bubble_classes(_), do: "bg-slate-700/30 border border-slate-600/30"

  defp list_channel_presence(channel_id) do
    topic = Topics.channel_presence(channel_id)
    Presence.list(topic)
    |> Enum.map(fn {user_id, metas} ->
      # metas unused currently
      _ = metas
      user_id
    end)
    |> Enum.sort()
  rescue
    _ -> []
  end

  # Build presence identity; if actor present shorten actor id; else ephemeral anon token
  defp presence_identity(%{actor_id: actor_id}) when is_binary(actor_id) do
    String.slice(actor_id, 0, 8)
  end
  defp presence_identity(_), do: "anon-" <> Base.encode16(:crypto.strong_rand_bytes(3))
end
