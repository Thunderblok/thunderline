defmodule ThunderlineWeb.ThunderlineDashboardLive do
  @moduledoc """
  Thunderline Nexus‑Style Dashboard (daisyUI + Tailwind, LiveView)

  Provides:
    * Left domain explorer (collapsible) with status pills
    * Center metrics cards + charts placeholder + event flow feed
    * Right chat/resources panel with WhatsApp‑style bubbles
    * Responsive layout: md -> 2 columns (sidebar + main), xl -> 3 columns
    * Accessible: aria labels, buttons, semantic headings

  NOTE: Requires daisyUI plugin enabled in Tailwind (see assets/css/app.css).
  """
  use ThunderlineWeb, :live_view
  require Logger
  alias Thunderline.DashboardMetrics
  alias Thunderline.Thunderflow.EventBuffer

  # Thunderline-focused domains
  @sample_domains [
    %{id: "thunderline", title: "thunderline", status: :online, children: [
      %{id: "thunderline/api", title: "API", status: :online},
      %{id: "thunderline/agents", title: "Agents", status: :degraded},
      %{id: "thunderline/ingest", title: "Ingest", status: :online},
      %{id: "thunderline/events", title: "Event Stream", status: :online}
    ]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    open = MapSet.new(Enum.map(@sample_domains, & &1.id))
    first_child = @sample_domains |> hd() |> Map.fetch!(:children) |> hd()

    if connected?(socket) do
      # Subscribe to dashboard metrics topic (public API is subscribe/0; direct topic may not be exposed)
      safe_try(fn -> DashboardMetrics.subscribe() end)
      # Event buffer for real-time events
  # Subscribe directly to the EventBuffer topic (string) which broadcasts {:dashboard_event, event}
  safe_try(fn -> Phoenix.PubSub.subscribe(Thunderline.PubSub, EventBuffer.topic()) end)
      # periodic refresh of KPI + events
      :timer.send_interval(5_000, self(), :refresh_kpis)
      :timer.send_interval(3_000, self(), :refresh_events)
    end

    initial_events = live_events_snapshot(first_child.id)

  {:ok,
   socket
     |> assign(:domains, @sample_domains)
     |> assign(:open_domains, open)
     |> assign(:active_domain, first_child.id)
     |> assign(:show_chat, true)
   # Open sidebar by default for initial discoverability on all screen sizes
   |> assign(:sidebar_open, true)
     |> assign(:events, initial_events)
     |> assign(:chat_messages, %{})
     |> assign(:composer, "")
     |> assign(:kpis, compute_kpis())
     |> assign(:last_metrics, nil)}
  end

  @impl true
  def handle_event("toggle_root", %{"id" => id}, socket) do
    open = toggle_set(socket.assigns.open_domains, id)
    {:noreply, assign(socket, :open_domains, open)}
  end

  def handle_event("select_domain", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:active_domain, id)
     |> assign(:show_chat, true)
     |> assign(:events, live_events_snapshot(id))}
  end

  def handle_event("toggle_chat", _params, socket), do: {:noreply, update(socket, :show_chat, &(!&1))}
  def handle_event("toggle_sidebar", _params, socket), do: {:noreply, update(socket, :sidebar_open, &(!&1))}
  def handle_event("update_composer", %{"value" => v}, socket), do: {:noreply, assign(socket, :composer, v)}

  def handle_event("send_message", _params, %{assigns: assigns} = socket) do
    msg = %{id: System.unique_integer([:positive]), body: assigns.composer, ts: System.system_time(:second), author: :you}
    domain_id = assigns.active_domain
    chat_messages = Map.update(assigns.chat_messages, domain_id, [msg], fn list -> [msg | list] |> Enum.take(200) end)
    {:noreply, assign(socket, chat_messages: chat_messages, composer: "")}
  end

  @impl true
  def handle_info(:refresh_kpis, socket), do: {:noreply, assign(socket, :kpis, compute_kpis())}
  def handle_info(:refresh_events, socket), do: {:noreply, assign(socket, :events, live_events_snapshot(socket.assigns.active_domain))}
  def handle_info({:dashboard_metrics, _}, socket), do: {:noreply, assign(socket, :kpis, compute_kpis())}

  # New metrics update message we observed in logs: {:metrics_update, map}
  def handle_info({:metrics_update, payload}, socket) when is_map(payload) do
    {:noreply,
     socket
     |> assign(:last_metrics, payload)
     |> assign(:kpis, kpis_from_metrics(payload))}
  end

  # Phoenix PubSub delivers messages as {topic, message}; match on tuple pattern
  def handle_info({"dashboard:events", {:dashboard_event, _evt}}, socket), do: {:noreply, assign(socket, :events, live_events_snapshot(socket.assigns.active_domain))}

  # Helpers ------------------------------------------------------------------
  defp toggle_set(set, id), do: if(MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp seed_events(domain_id) do
    for i <- 0..29 do
      %{
        source: Enum.at(["thunderline-api", "thunderline-agents", "thunderline-ingest"], rem(i, 3)),
        time: Timex.format!(Timex.now() |> Timex.shift(seconds: -i), "%H:%M:%S", :strftime),
        message: "Processed #{Enum.random(30..120)} ops in #{domain_id}",
        idx: i
      }
    end
  end

  defp compute_kpis do
    # Fallback when we haven't received structured metrics_update yet
    sys = safe_call(&DashboardMetrics.get_system_metrics/0, %{})
    evt = safe_call(&DashboardMetrics.get_event_metrics/0, %{})
    users = Map.get(sys, :active_users, 0)
    ops = Map.get(evt, :events_per_minute, 0)
    mem = get_in(sys, [:memory, :total]) || 0
    uptime = Map.get(sys, :uptime, 0)

    [
      {"Ops/min", format_number(ops), nil},
      {"Users", format_number(users), nil},
      {"Mem", format_number(div(mem, 1024 * 1024)) <> "M", nil},
      {"Uptime", "#{uptime}s", nil}
    ]
  end

  defp kpis_from_metrics(%{system: system} = payload) do
    events = Map.get(payload, :events, %{})
    agents = Map.get(payload, :agents, %{})
    ops = Map.get(events, :processing_rate, 0.0)
    active_agents = Map.get(agents, :active_agents, 0)
    mem = get_in(system, [:memory, :total]) || 0
    uptime = Map.get(system, :uptime, 0)

    [
      {"Ops/sec", format_number(round(ops)), nil},
      {"Agents", format_number(active_agents), nil},
      {"Mem", format_number(div(mem, 1024 * 1024)) <> "M", nil},
      {"Uptime", "#{uptime}s", nil}
    ]
  end
  defp kpis_from_metrics(_), do: compute_kpis()

  defp live_events_snapshot(domain_id) do
    case safe_call(fn -> EventBuffer.snapshot(50) end, []) do
      [] -> seed_events(domain_id)
      list ->
        list
        |> Enum.map(fn evt ->
          %{source: source_from_evt(evt), time: time_from_evt(evt), message: message_from_evt(evt, domain_id)}
        end)
        # Filter out noisy development code reload events to keep feed meaningful
        |> Enum.reject(fn %{message: m} -> is_binary(m) and String.starts_with?(m, "system file changed") end)
        |> then(fn cleaned -> if cleaned == [], do: seed_events(domain_id), else: cleaned end)
    end
  end

  defp source_from_evt(%{type: t}) when is_binary(t), do: t
  defp source_from_evt(%{source: s}) when is_binary(s), do: s
  defp source_from_evt(_), do: "thundergrid"

  defp time_from_evt(%{ts: ts}) when is_integer(ts) do
    Timex.from_unix(div(ts, 1000)) |> Timex.format!("%H:%M:%S", :strftime)
  rescue
    _ -> Timex.format!(Timex.now(), "%H:%M:%S", :strftime)
  end
  defp time_from_evt(_), do: Timex.format!(Timex.now(), "%H:%M:%S", :strftime)

  defp message_from_evt(%{message: m}, _d) when is_binary(m), do: m
  defp message_from_evt(%{payload: p}, d) when is_map(p), do: "#{inspect(Map.take(p, [:id, :status]))} in #{d}"
  defp message_from_evt(evt, d), do: "Event #{evt |> Map.get(:id, "?")} for #{d}"

  defp safe_call(fun, fallback) do
    try do
      fun.()
    rescue
      _ -> fallback
    catch
      _, _ -> fallback
    end
  end

  defp status_color(:online), do: "badge-success"
  defp status_color(:degraded), do: "badge-warning"
  defp status_color(:maintenance), do: "badge-neutral"
  defp status_color(_), do: "badge-ghost"

  # Accept either a LiveView socket (with :assigns) or a plain assigns map
  defp domain_active?(%{assigns: assigns}, id), do: Map.get(assigns, :active_domain) == id
  defp domain_active?(assigns, id) when is_map(assigns), do: Map.get(assigns, :active_domain) == id

  defp root_open?(%{assigns: assigns}, id) do
    assigns
    |> Map.get(:open_domains, MapSet.new())
    |> MapSet.member?(id)
  end
  defp root_open?(assigns, id) when is_map(assigns) do
    assigns
    |> Map.get(:open_domains, MapSet.new())
    |> MapSet.member?(id)
  end

  defp chat_msgs(assigns, id), do: Map.get(assigns.chat_messages, id, []) |> Enum.reverse()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300 text-base-content p-4">
      <div class="flex items-center gap-3 mb-4">
        <button class="btn btn-sm btn-ghost xl:hidden" phx-click="toggle_sidebar" aria-label="Toggle sidebar">
          <%= if @sidebar_open, do: "✕", else: "☰" %>
        </button>
        <h1 class="text-lg font-semibold tracking-wide">Thunderline • Nexus Dashboard</h1>
        <span class="text-xs opacity-60">High Command</span>
        <a href="#" class="ml-auto link link-primary text-xs flex items-center gap-1">Docs ↗</a>
      </div>

      <div class="grid grid-cols-12 gap-4">
        <!-- Sidebar -->
        <aside class={"col-span-12 md:col-span-4 xl:col-span-2 space-y-3 " <> (if @sidebar_open, do: "block", else: "hidden xl:block") } aria-label="Domains Sidebar">
          <div class="card bg-base-200/60 backdrop-blur-lg shadow-sm">
            <div class="card-body p-4">
              <h2 class="card-title text-sm mb-2">Domains</h2>
              <input type="text" placeholder="Filter" class="input input-sm input-bordered w-full mb-3" aria-label="Filter domains" />
              <nav class="space-y-1">
                <%= for d <- @domains do %>
                  <div class="mb-1">
                    <button phx-click="toggle_root" phx-value-id={d.id} class="w-full flex items-center gap-2 text-left px-2 py-1.5 rounded-md hover:bg-base-300/70 focus:outline-none focus:ring"
                      aria-expanded={root_open?(@socket, d.id)} aria-controls={"children-"<>d.id}>
                      <span class="w-4 text-xs opacity-70"><%= if root_open?(@socket, d.id), do: "▼", else: "▶" %></span>
                      <span class="truncate text-sm"><%= d.title %></span>
                      <span class="ml-auto badge badge-xs #{status_color(d.status)}"><%= d.status %></span>
                    </button>
                    <ul id={"children-"<>d.id} class={"mt-1 ml-5 space-y-0.5 border-l border-base-300 pl-3 " <> if(root_open?(@socket, d.id), do: "block", else: "hidden")}>
                      <%= for c <- d.children || [] do %>
                        <li>
                          <button phx-click="select_domain" phx-value-id={c.id}
                            class={"w-full flex items-center gap-2 px-2 py-1 rounded text-left text-xs hover:bg-base-300/60 #{domain_active?(@socket, c.id) && "bg-base-300"}"}
                            aria-current={domain_active?(@socket, c.id)}>
                            <span class="truncate"><%= c.title %></span>
                            <span class="ml-auto badge badge-ghost badge-xs #{status_color(c.status)}"><%= c.status %></span>
                          </button>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
              </nav>
            </div>
          </div>
        </aside>

        <!-- Main Center -->
        <main class="col-span-12 md:col-span-8 xl:col-span-7 space-y-4">
          <!-- KPI Cards -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <%= for {label, value, delta} <- @kpis do %>
              <div class="card bg-base-200/60 backdrop-blur-xl shadow-sm">
                <div class="card-body p-4">
                  <span class="text-xs opacity-70"><%= label %></span>
                  <div class="mt-2 text-xl font-semibold"><%= value %></div>
                  <%= if delta do %><div class={"mt-1 text-[10px] font-medium " <> (String.starts_with?(delta, "+") && "text-warning" || "text-error") }><%= delta %> vs last</div><% end %>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Charts Placeholder -->
          <section class="card bg-base-200/60 backdrop-blur-xl shadow-sm h-64">
            <div class="card-body items-center justify-center text-sm opacity-70">Charts area (Recharts/ECharts placeholder)</div>
          </section>

          <!-- Event Flow -->
          <section class="card bg-base-200/60 backdrop-blur-xl shadow-sm h-[32rem] flex flex-col">
            <div class="card-body p-4 pb-2 flex items-center gap-2">
              <h3 class="font-semibold text-sm">Event Flow</h3>
              <span class="ml-auto text-[10px] opacity-60">last <%= length(@events) %> events</span>
              <button class="btn btn-xs btn-ghost" aria-label="Refresh events" phx-click="select_domain" phx-value-id={@active_domain}>↻</button>
            </div>
            <div id="eventFeed" phx-hook="EventFlowScroll" class="px-4 pb-4 space-y-2 overflow-auto custom-scrollbar">
              <%= for e <- @events do %>
                <div class="rounded-lg border border-base-300 bg-base-100/40 p-2 text-xs">
                  <div class="flex items-center gap-2 mb-0.5">
                    <span class="badge badge-ghost badge-xs"><%= e.source %></span>
                    <span class="opacity-50"><%= e.time %></span>
                  </div>
                  <div class="text-[11px] leading-snug"><%= e.message %></div>
                </div>
              <% end %>
            </div>
          </section>
        </main>

        <!-- Right Column -->
        <aside class="col-span-12 xl:col-span-3 space-y-4">
          <div class="flex items-center gap-2">
            <h3 class="text-sm font-semibold">Panel</h3>
            <button class="btn btn-xs btn-outline" phx-click="toggle_chat" aria-label="Toggle chat/resources">
              <%= if @show_chat, do: "Resources", else: "Chat" %>
            </button>
          </div>
          <%= if @show_chat do %>
            <section class="card bg-base-200/60 backdrop-blur-xl shadow-sm h-[32rem] flex flex-col" aria-label="Chat Panel">
              <div class="card-body p-3 border-b border-base-300 flex items-center gap-2">
                <h4 class="font-semibold text-sm truncate"><%= @active_domain %></h4>
              </div>
              <div id="messagesArea" class="flex-1 overflow-y-auto p-3 space-y-3 custom-scrollbar">
                <%= for m <- Map.get(@chat_messages, @active_domain, []) |> Enum.reverse() do %>
                  <div class="flex items-start gap-2 message-bubble">
                    <div class="w-8 h-8 rounded-full bg-base-300" />
                    <div class="max-w-xs lg:max-w-sm">
                      <div class="bg-base-100 rounded-2xl rounded-tl-sm p-2 shadow-md">
                        <p class="text-xs"><%= m.body %></p>
                      </div>
                      <p class="text-[10px] opacity-50 mt-1 ml-1"><%= relative_time(m.ts) %></p>
                    </div>
                  </div>
                <% end %>
              </div>
              <form phx-submit="send_message" class="p-2 border-t border-base-300 glass-effect">
                <div class="flex items-center gap-2">
                  <input name="message" value={@composer} phx-change="update_composer" phx-debounce="300" placeholder="Type a message…" class="input input-sm flex-1 input-bordered" aria-label="Message composer" />
                  <button type="submit" class="btn btn-sm btn-primary chat-gradient" disabled={@composer == ""}>Send</button>
                </div>
              </form>
            </section>
          <% else %>
            <section class="card bg-base-200/60 backdrop-blur-xl shadow-sm h-[32rem]" aria-label="Resources Panel">
              <div class="card-body p-4 space-y-2 text-xs">
                <h4 class="font-semibold text-sm mb-2">Resources</h4>
                <ul class="space-y-1">
                  <li>CPU: <span class="text-error">OFFLINE</span></li>
                  <li>Storage: <span class="text-warning">healthy</span></li>
                  <li>Last deploy: 3m ago</li>
                </ul>
                <p class="opacity-60 mt-4">Swap with dynamic domain resource metrics.</p>
              </div>
            </section>
          <% end %>
        </aside>
      </div>
    </div>
    """
  end

  defp relative_time(ts) do
    now = System.system_time(:second)
    diff = max(now - ts, 0)
    cond do
      diff < 5 -> "now"
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff,60)}m"
      true -> Timex.format!(Timex.from_unix(ts), "%H:%M", :strftime)
    end
  end

  defp format_number(n) when is_integer(n) do
    cond do
      n >= 1_000_000 -> :io_lib.format("~.1fM", [n/1_000_000]) |> IO.iodata_to_binary()
      n >= 1_000 -> :io_lib.format("~.1fK", [n/1_000]) |> IO.iodata_to_binary()
      true -> Integer.to_string(n)
    end
  end
  defp format_number(n) when is_float(n), do: format_number(round(n))
  defp format_number(other), do: to_string(other)

  defp safe_call(fun, fallback) do
    try do
      fun.()
    rescue
      _ -> fallback
    catch
      _, _ -> fallback
    end
  end
  defp safe_try(fun), do: safe_call(fun, :ok)
end
