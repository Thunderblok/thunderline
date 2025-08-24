defmodule ThunderlineWeb.ThunderlineDashboardLive do
  @moduledoc """
  Thunderline Nexus‑Style Dashboard (daisyUI + Tailwind, LiveView)

  - Left: domain explorer (status pills)
  - Center: KPI + event feed
  - Right: faux‑3D domain map with animated Bezier links + inspector

  Tailwind must have daisyUI enabled.
  """
  use ThunderlineWeb, :live_view
  require Logger

  alias Phoenix.PubSub
  alias Thunderline.DashboardMetrics
  alias Thunderline.Thunderflow.EventBuffer

  # ---- Demo domain tree --------------------------------------------------------
  @sample_domains [
    %{
      id: "thunderline",
      title: "thunderline",
      status: :online,
      children: [
        %{id: "thunderline/api",     title: "API",           status: :online},
        %{id: "thunderline/agents",  title: "Agents",        status: :degraded},
        %{id: "thunderline/ingest",  title: "Ingest",        status: :online},
        %{id: "thunderline/events",  title: "Event Stream",  status: :online}
      ]
    }
  ]

  # ---- LiveView lifecycle ------------------------------------------------------
  @impl true
  def mount(_params, _session, socket) do
    open = MapSet.new(Enum.map(@sample_domains, & &1.id))
    first_child = @sample_domains |> hd() |> Map.fetch!(:children) |> hd()

    if connected?(socket) do
      safe_try(fn -> DashboardMetrics.subscribe() end)
      safe_try(fn -> PubSub.subscribe(Thunderline.PubSub, EventBuffer.topic()) end)

      :timer.send_interval(5_000, self(), :refresh_kpis)
      :timer.send_interval(3_000, self(), :refresh_events)
    end

    initial_events = live_events_snapshot(first_child.id)

    nodes       = graph_nodes()
    edge_counts = compute_edge_counts(initial_events, nodes)

    map_nodes  = domain_map_nodes()
    map_edges  = domain_map_edges()
    map_health = domain_map_health()

    friends = [
      %{id: 1, name: "Sarah Connor",   status: :online,  latency: 24},
      %{id: 2, name: "Mike Johnson",   status: :away,    latency: 51},
      %{id: 3, name: "Nikolai Tesla",  status: :online,  latency: 12},
      %{id: 4, name: "Ripley",         status: :busy,    latency: 5},
      %{id: 5, name: "Neo",            status: :offline, latency: nil}
    ]

    {:ok,
     socket
     |> assign(:domains, @sample_domains)
     |> assign(:open_domains, open)
     |> assign(:active_domain, first_child.id)
     |> assign(:events, initial_events)
     |> assign(:kpis, compute_kpis())
     |> assign(:graph_nodes, nodes)
     |> assign(:edge_counts, edge_counts)
     |> assign(:domain_map_nodes, map_nodes)
     |> assign(:domain_map_edges, map_edges)
     |> assign(:domain_map_health, map_health)
     |> assign(:selected_map_node, nil)
     |> assign(:friends, friends)
     |> assign(:active_friend, friends |> hd() |> Map.get(:id))}
  end

  # ---- UI events ---------------------------------------------------------------
  @impl true
  def handle_event("toggle_root", %{"id" => id}, socket) do
    {:noreply, update(socket, :open_domains, &toggle_set(&1, id))}
  end

  @impl true
  def handle_event("select_map_node", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_map_node, empty_to_nil(id))}
  end

  @impl true
  # Friend selection (purely cosmetic for now)
  @impl true
  def handle_event("select_friend", %{"id" => id}, socket) do
    {:noreply, assign(socket, :active_friend, id)}
  end

  @impl true
  def handle_event("select_domain", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:active_domain, id)
     |> refresh_events_assigns()}
  end

  # ---- Timers & PubSub ---------------------------------------------------------
  @impl true
  def handle_info(:refresh_kpis, socket) do
    {:noreply, assign(socket, :kpis, compute_kpis())}
  end

  @impl true
  def handle_info(:refresh_events, socket) do
    {:noreply, refresh_events_assigns(socket)}
  end

  # EventBuffer.broadcasts {:dashboard_event, evt}
  @impl true
  def handle_info({:dashboard_event, _evt}, socket) do
    # On any inbound event, refresh the feed & edge weights
    {:noreply, refresh_events_assigns(socket)}
  end

  # Metrics push from DashboardMetrics (we subscribed in mount)
  @impl true
  def handle_info({:metrics_update, payload}, socket) when is_map(payload) do
    kpis = build_kpis_from_metrics(payload)
    {:noreply, assign(socket, :kpis, kpis)}
  rescue
    _ -> {:noreply, socket}
  end

  # Ignore any other unexpected messages to avoid crashing the LiveView.
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---- Render ------------------------------------------------------------------
  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0B0F14] text-white">
      <!-- Header bar -->
      <header class="sticky top-0 z-10 bg-gradient-to-r from-white/5 to-transparent backdrop-blur border-b border-white/10">
        <div class="max-w-7xl mx-auto px-4 py-3 flex items-center gap-4">
          <div class="text-sm uppercase tracking-widest text-emerald-300">Thunderline Command</div>
          <div class="text-lg font-semibold">Operations Dashboard</div>
          <div class="ml-auto flex items-center gap-2 text-sm text-white/70">
            <span class="hidden sm:inline">Status:</span>
            <span class="px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-300/30">Green</span>
          </div>
        </div>
      </header>

      <div class="max-w-7xl mx-auto grid grid-cols-12 gap-4 p-4">
        <!-- Friends / Peers list -->
        <aside class="col-span-12 md:col-span-3 xl:col-span-3 panel p-3">
          <div class="flex items-center gap-2 mb-2">
            <div class="w-2 h-2 rounded-full bg-emerald-400" />
            <h2 class="font-semibold">Peers</h2>
          </div>
          <ul class="space-y-1 text-sm">
            <%= for f <- @friends do %>
              <li>
                <button phx-click="select_friend" phx-value-id={f.id}
                        class={"w-full text-left px-3 py-2 rounded-xl transition border border-white/5 hover:bg-white/5 flex items-center gap-3 " <> (if @active_friend == f.id, do: "bg-white/10", else: "")}>
                  <span class={"w-2 h-2 rounded-full " <> friend_dot(f.status)}></span>
                  <span class="truncate flex-1"><%= f.name %></span>
                  <span class="ml-auto text-xs text-white/50 uppercase"><%= f.status %></span>
                  <%= if f.latency do %><span class="text-[10px] ml-2 text-primary"><%= f.latency %>ms</span><% end %>
                </button>
              </li>
            <% end %>
          </ul>
          <div class="mt-4 grid grid-cols-2 gap-2">
            <button class="btn btn-sm btn-ghost border border-white/10">New Chat</button>
            <button class="btn btn-sm btn-ghost border border-white/10">Create Room</button>
          </div>
          <p class="mt-4 text-[10px] opacity-40">peer status reflects last heartbeat</p>
        </aside>

        <!-- Middle column -->
        <main class="col-span-12 md:col-span-5 xl:col-span-5 space-y-4">
          <!-- KPI Panel -->
          <div class="panel p-4">
            <div class="stats stats-vertical lg:stats-horizontal w-full">
              <%= for {label, value, delta} <- @kpis do %>
                <div class="stat">
                  <div class="stat-title"><%= label %></div>
                  <div class={"stat-value " <> (if label == "Ops/min", do: "text-emerald-300", else: "")}><%= value %></div>
                  <%= if delta do %>
                    <div class={"stat-desc " <> (if String.starts_with?(delta, "+"), do: "text-emerald-400", else: "text-rose-300")}><%= delta %></div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Event Flow -->
          <div class="panel p-4 h-72 overflow-auto">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-violet-400" />
              <h3 class="font-semibold">Event Flow</h3>
              <span class="ml-auto text-xs text-white/50">last <%= length(@events) %></span>
              <button class="btn btn-ghost btn-xs" phx-click="select_domain" phx-value-id={@active_domain}>refresh</button>
            </div>
            <div id="eventFeed" class="space-y-2 text-sm">
              <%= for e <- @events do %>
                <div class="p-2 rounded-lg bg-white/5 border border-white/10">
                  <div class="flex items-center gap-2 text-xs mb-0.5">
                    <span class="badge badge-ghost badge-xs"><%= e.source %></span>
                    <time class="opacity-40"><%= e.time %></time>
                  </div>
                  <div class="text-[11px] leading-snug"><%= e.message %></div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Controls -->
            <div class="panel p-4">
              <div class="grid grid-cols-2 gap-3">
                <button class="btn btn-outline">Deploy</button>
                <button class="btn btn-outline">Restart Node</button>
                <button class="btn btn-outline">Open Logs</button>
                <button class="btn btn-outline">Settings</button>
              </div>
            </div>
        </main>

        <!-- Right column -->
        <section class="col-span-12 md:col-span-4 xl:col-span-4 space-y-4">
          <!-- Domain Map -->
          <div class="panel p-4">
            <div class="flex items-center gap-2 mb-3">
              <div class="w-2 h-2 rounded-full bg-cyan-400" />
              <h3 class="font-semibold">Domain Map</h3>
              <span class="ml-auto text-xs text-white/50">interactive</span>
            </div>
            <div class="relative w-full h-[420px]">
              <svg viewBox="0 0 760 420" class="w-full h-full rounded-xl bg-gradient-to-b from-slate-900/40 to-slate-900/10 select-none" preserveAspectRatio="xMinYMin meet">
                <defs>
                  <linearGradient id="wire" x1="0" x2="1">
                    <stop offset="0%" stop-color="#22d3ee" stop-opacity="0.9" />
                    <stop offset="100%" stop-color="#10b981" stop-opacity="0.9" />
                  </linearGradient>
                  <filter id="blur"><feGaussianBlur stdDeviation="6" /></filter>
                </defs>
                <%= for i <- 0..12 do %>
                  <line x1="40" y1={30 + i * 28} x2="720" y2={10 + i * 28} stroke="#1f2937" stroke-width="1" opacity="0.45" />
                <% end %>
                <% by_id = Map.new(@domain_map_nodes, &{&1.id, &1}) %>
                <%= for e <- @domain_map_edges do %>
                  <% a = by_id[e.a]; b = by_id[e.b]; path = cubic_path(a, b) %>
                  <% hot = is_nil(@selected_map_node) or e.a == @selected_map_node or e.b == @selected_map_node %>
                  <g>
                    <path d={path} stroke="#0ea5e9" stroke-opacity={if hot, do: 0.18, else: 0.06} stroke-width="8" fill="none" filter="url(#blur)" />
                    <path d={path} stroke="url(#wire)" stroke-width={if hot, do: 2.5, else: 1.2} fill="none" class={"flow " <> speed_class(e.traffic)}>
                      <title><%= e.a %> -> <%= e.b %> traffic <%= round(e.traffic * 100) %>%</title>
                    </path>
                  </g>
                <% end %>
                <%= for n <- @domain_map_nodes do %>
                  <% selected = n.id == @selected_map_node %>
                  <% connected = Enum.any?(@domain_map_edges, &(&1.a == n.id or &1.b == n.id)) %>
                  <% ring = ring_size(selected, connected) %>
                  <% color = domain_map_status_color(@domain_map_health[n.id][:status]) %>
                  <g phx-click="select_map_node" phx-value-id={n.id} class="cursor-pointer">
                    <circle cx={n.x} cy={n.y} r={14 + ring} fill="none" stroke={color} stroke-opacity="0.35" stroke-width={ring} />
                    <circle cx={n.x} cy={n.y} r="14" fill={color} opacity="0.85" />
                    <text x={n.x + 20} y={n.y + 4} font-size="12" fill="currentColor"><%= n.label %></text>
                  </g>
                <% end %>
              </svg>
            </div>
          </div>

          <!-- Inspector -->
          <div class="panel p-4">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-emerald-400" />
              <h3 class="font-semibold">Inspector</h3>
              <span class="ml-auto text-xs text-white/50"><%= if @selected_map_node, do: @selected_map_node, else: "select a node" %></span>
            </div>
            <%= if @selected_map_node do %>
              <% h = @domain_map_health[@selected_map_node] %>
              <div class="space-y-3">
                <div class="flex items-center gap-3">
                  <div class={"badge badge-outline " <> (case h.status do :healthy -> "badge-success"; :warning -> "badge-warning"; :critical -> "badge-error"; _ -> "" end)}><%= h.status %></div>
                  <div class="text-base font-semibold"><%= @selected_map_node %></div>
                  <button class="btn btn-ghost btn-xs ml-auto" phx-click="select_map_node" phx-value-id="">x</button>
                </div>
                <div class="grid grid-cols-3 gap-2 text-sm">
                  <div class="p-2 rounded-lg bg-white/5 border border-white/10"><div class="text-xs opacity-60">Ops/min</div><div class="text-base"><%= h.ops %></div></div>
                  <div class="p-2 rounded-lg bg-white/5 border border-white/10"><div class="text-xs opacity-60">CPU%</div><div class="text-base"><%= h.cpu %></div></div>
                  <div class="p-2 rounded-lg bg-white/5 border border-white/10"><div class="text-xs opacity-60">p95</div><div class="text-base"><%= h.p95 %>ms</div></div>
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <button class="btn btn-sm btn-outline">Open Logs</button>
                  <button class="btn btn-sm btn-outline">Restart</button>
                  <button class="btn btn-sm btn-outline">Tail Metrics</button>
                  <button class="btn btn-sm btn-outline">Quarantine</button>
                </div>
                <p class="text-[10px] opacity-50">Errors: <%= h.errors %></p>
              </div>
            <% else %>
              <div class="text-sm text-white/60">Click a node on the map to inspect health, metrics and actions.</div>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  # ---- Assign refresh helpers ---------------------------------------------------
  defp refresh_events_assigns(socket) do
    events = live_events_snapshot(socket.assigns.active_domain)
    nodes  = graph_nodes()
    edge_counts = compute_edge_counts(events, nodes)
    socket
    |> assign(:events, events)
    |> assign(:graph_nodes, nodes)
    |> assign(:edge_counts, edge_counts)
  end

  # ---- Data & formatting helpers ------------------------------------------------
  defp compute_kpis do
    sys = safe_call(&DashboardMetrics.get_system_metrics/0, %{})
    evt = safe_call(&DashboardMetrics.get_event_metrics/0, %{})
    users = Map.get(sys, :active_users, 0)
    ops   = Map.get(evt, :events_per_minute, 0)
    mem   = get_in(sys, [:memory, :total]) || 0
    uptime = Map.get(sys, :uptime, 0)

    [
      {"Ops/min", format_number(ops), nil},
      {"Users",   format_number(users), nil},
      {"Mem",     format_number(div(mem, 1024 * 1024)) <> "M", nil},
      {"Uptime",  "#{uptime}s", nil}
    ]
  end

  # Build minimal KPIs directly from an incoming :metrics_update payload so we
  # don't need to perform another metrics fetch.
  defp build_kpis_from_metrics(%{system: sys} = payload) do
    events      = Map.get(payload, :events, %{})
    agents      = Map.get(payload, :agents, %{})
    thunderlane = Map.get(payload, :thunderlane, %{})

    mem_total = get_in(sys, [:memory, :total]) || 0
    uptime    = Map.get(sys, :uptime, 0)
    # events.processing_rate is per second -> per minute
    ops_per_min = (Map.get(events, :processing_rate, 0.0) * 60) |> round()
    active_users = Map.get(agents, :active_agents, 0)

    [
      {"Ops/min", format_number(ops_per_min), nil},
      {"Users",   format_number(active_users), nil},
      {"Mem",     format_number(div(mem_total, 1024 * 1024)) <> "M", nil},
      {"Uptime",  "#{uptime}s", nil}
    ]
  end
  defp build_kpis_from_metrics(_), do: compute_kpis()

  defp live_events_snapshot(domain_id) do
    case safe_call(fn -> EventBuffer.snapshot(50) end, []) do
      [] -> seed_events(domain_id)
      list ->
        list
        |> Enum.map(fn evt ->
          %{
            source: source_from_evt(evt),
            time:   time_hhmmss(System.os_time(:second)),
            message: message_from_evt(evt, domain_id)
          }
        end)
        |> Enum.reject(fn %{message: m} -> is_binary(m) and String.starts_with?(m, "system file changed") end)
        |> then(fn cleaned -> if cleaned == [], do: seed_events(domain_id), else: cleaned end)
    end
  end

  # Topology (hex-ish row)
  defp graph_nodes do
    children = @sample_domains |> hd() |> Map.get(:children, [])
    base = 40
    Enum.with_index(children, fn c, idx ->
      cx = 80 + idx * 140
      cy = 90 + if rem(idx, 2) == 0, do: 0, else: 35
      %{
        id: c.id, label: c.title, status: c.status, cx: cx, cy: cy, size: base,
        points: hex_points(cx, cy, base)
      }
    end)
  end

  defp graph_edges(nodes) do
    ids = Enum.map(nodes, & &1.id)
    Enum.map(Enum.with_index(ids), fn {id, idx} ->
      {id, Enum.at(ids, rem(idx + 1, length(ids)))}
    end)
  end

  defp compute_edge_counts(events, nodes) do
    ring = graph_edges(nodes)
    Enum.reduce(events, %{}, fn e, acc ->
      src = e.source
      case Enum.find(ring, fn {from, _} -> String.contains?(src, Path.basename(from)) end) do
        {from, to} -> Map.update(acc, {from, to}, 1, &(&1 + 1))
        nil -> acc
      end
    end)
  end

  # Domain map (right panel)
  defp domain_map_nodes do
    [
      %{id: "thunderline-core", label: "core", x: 140, y:  90, z: 18},
      %{id: "thundergrid",      label: "grid", x: 380, y: 150, z:  4},
      %{id: "thunderbolt",      label: "bolt", x: 620, y:  90, z: 10},
      %{id: "thunderblock",     label: "block",x: 520, y: 260, z:  0},
      %{id: "mnesia",           label: "mnesia", x: 230, y: 250, z: -6}
    ]
  end

  defp domain_map_edges do
    [
      %{a: "thunderline-core", b: "thundergrid",  traffic: 0.8},
      %{a: "thundergrid",      b: "thunderbolt",  traffic: 0.6},
      %{a: "thunderbolt",      b: "thunderblock", traffic: 0.4},
      %{a: "thundergrid",      b: "mnesia",       traffic: 0.7},
      %{a: "mnesia",           b: "thunderline-core", traffic: 0.5}
    ]
  end

  defp domain_map_health do
    %{
      "thunderline-core" => %{status: :healthy, ops: 920, cpu: 28, p95: 112, errors: 0},
      "thundergrid"      => %{status: :warning, ops: 710, cpu: 63, p95: 188, errors: 2},
      "thunderbolt"      => %{status: :healthy, ops: 560, cpu: 41, p95: 129, errors: 0},
      "thunderblock"     => %{status: :healthy, ops: 330, cpu: 22, p95: 144, errors: 1},
      "mnesia"           => %{status: :critical, ops: 480, cpu: 77, p95: 240, errors: 4}
    }
  end

  # SVG helpers
  defp cubic_path(a, b) do
    c1x = (a.x + b.x) / 2
    c1y = a.y - 60 - a.z * 2
    c2x = (a.x + b.x) / 2
    c2y = b.y + 60 + b.z * 2
    "M #{a.x},#{a.y} C #{c1x},#{c1y} #{c2x},#{c2y} #{b.x},#{b.y}"
  end
  defp speed_class(t) when t > 0.7, do: "fast"
  defp speed_class(t) when t < 0.5, do: "slow"
  defp speed_class(_), do: ""

  defp friend_dot(:online),     do: "dot-online"
  defp friend_dot(:away),       do: "dot-away"
  defp friend_dot(:busy),       do: "dot-busy animate-pulse"
  defp friend_dot(:offline),    do: "dot-offline"
  defp friend_dot(_),           do: "dot-offline"

  # Map health status to SVG color (match Tailwind palette-ish)
  defp domain_map_status_color(:healthy),  do: "#10b981"  # emerald-500
  defp domain_map_status_color(:warning),  do: "#f59e0b"  # amber-500
  defp domain_map_status_color(:critical), do: "#ef4444"  # red-500
  defp domain_map_status_color(_),         do: "#64748b"  # slate-500 fallback

  defp ring_size(true, _conn),  do: 4
  defp ring_size(false, true),  do: 2
  defp ring_size(false, false), do: 1

  # Formatting / safe utils
  defp time_hhmmss(unix_sec) do
    {{_y, _m, _d}, {h, mi, s}} =
      unix_sec
      |> DateTime.from_unix!()
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()

    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, mi, s]) |> IO.iodata_to_binary()
  end

  defp source_from_evt(%{type: t}) when is_binary(t),  do: t
  defp source_from_evt(%{source: s}) when is_binary(s),do: s
  defp source_from_evt(_),                             do: "thundergrid"

  defp message_from_evt(%{message: m}, _d) when is_binary(m), do: m
  defp message_from_evt(%{payload: p}, d) when is_map(p),     do: "#{inspect(Map.take(p, [:id, :status]))} in #{d}"
  defp message_from_evt(evt, d), do: "Event #{Map.get(evt, :id, "?")} for #{d}"

  defp hex_points(cx, cy, size) do
    for i <- 0..5 do
      angle = :math.pi() / 180 * (60 * i - 30)
      x = cx + size * :math.cos(angle)
      y = cy + size * :math.sin(angle)
      :io_lib.format("~.1f,~.1f", [x, y]) |> IO.iodata_to_binary()
    end
    |> Enum.join(" ")
  end

  defp format_number(n) when is_integer(n) do
    cond do
      n >= 1_000_000 -> :io_lib.format("~.1fM", [n / 1_000_000]) |> IO.iodata_to_binary()
      n >= 1_000     -> :io_lib.format("~.1fK", [n / 1_000])     |> IO.iodata_to_binary()
      true           -> Integer.to_string(n)
    end
  end
  defp format_number(n) when is_float(n), do: format_number(round(n))
  defp format_number(other), do: to_string(other)

  defp toggle_set(%MapSet{} = set, id),
    do: (if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp seed_events(domain_id) do
    now = System.os_time(:second)
    for i <- 0..14 do
      ts = now - i
      %{
        source: "seed/#{rem(i, 4)}",
        time: time_hhmmss(ts),
        message: "boot sequence event #{i} for #{domain_id}"
      }
    end
  end

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
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(v),  do: v
end
