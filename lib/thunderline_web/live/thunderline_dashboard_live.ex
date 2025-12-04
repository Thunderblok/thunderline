defmodule ThunderlineWeb.ThunderlineDashboardLive do
  @moduledoc """
  Thunderline Nexus‑Style Dashboard (daisyUI + Tailwind, LiveView)

  React mount variant: this LiveView now only hydrates initial assigns into
  data-* attributes for the React client component.
  """

  # Re-introduce LiveView behaviour & helpers (removed during minimalization).
  use ThunderlineWeb, :live_view
  # Attach unified auth on_mount so current_user is consistently available
  on_mount ThunderlineWeb.Live.Auth
  require Logger
  alias Phoenix.PubSub
  alias Thunderline.DashboardMetrics
  alias Thunderline.Thunderflow.EventBuffer
  alias Thunderline.Thunderflow.Observability.NDJSON
  alias Thunderline.Thunderblock.Checkpoint
  alias Thunderline.Thunderbolt.Cerebros.Summary, as: CerebrosSummary
  alias Thunderline.Thunderbolt.CerebrosBridge
  alias Thunderline.Thunderbolt.CerebrosBridge.{RunOptions, Validator}

  # Domain tree used by helper functions (was removed earlier; re-added).
  @sample_domains [
    %{
      id: "thunderline",
      title: "thunderline",
      status: :online,
      children: [
        %{id: "thunderline/api", title: "API", status: :online},
        %{id: "thunderline/agents", title: "Agents", status: :degraded},
        %{id: "thunderline/ingest", title: "Ingest", status: :online},
        %{id: "thunderline/events", title: "Event Stream", status: :online}
      ]
    }
  ]

  @cerebros_run_topic "cerebros:runs"
  @cerebros_trial_topic "cerebros:trials"

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    Logger.debug("[DashboardLive] mount start")
    open = MapSet.new(Enum.map(@sample_domains, & &1.id))
    first_child = @sample_domains |> hd() |> Map.fetch!(:children) |> hd()

    if connected?(socket) do
      safe_try(fn -> DashboardMetrics.subscribe() end)
      safe_try(fn -> PubSub.subscribe(Thunderline.PubSub, EventBuffer.topic()) end)
      # Subscribe to realtime dashboard updates emitted by RealTimePipeline
      safe_try(fn -> PubSub.subscribe(Thunderline.PubSub, "thunderline_web:dashboard") end)
      # Subscribe to subsystem topics for richer visibility (best‑effort; ignore errors)
      for t <- ["thunderline:metrics:update", "thunderline:agents:batch_update"] do
        safe_try(fn -> PubSub.subscribe(Thunderline.PubSub, t) end)
      end

      safe_try(fn -> PubSub.subscribe(Thunderline.PubSub, @cerebros_run_topic) end)
      safe_try(fn -> PubSub.subscribe(Thunderline.PubSub, @cerebros_trial_topic) end)

      :timer.send_interval(5_000, self(), :refresh_kpis)
      :timer.send_interval(3_000, self(), :refresh_events)
    end

    Logger.debug("[DashboardLive] before snapshot")
    initial_events = live_events_snapshot(first_child.id) |> Enum.take(5)
    Logger.debug("[DashboardLive] after snapshot count=#{length(initial_events)}")
    nodes = graph_nodes()
    edge_counts = compute_edge_counts(initial_events, nodes)

    # Defer potentially heavy domain map computation to after first render.
    send(self(), :init_domain_map)

    friends = [
      %{id: 1, name: "Sarah Connor", status: :online, latency: 24},
      %{id: 2, name: "Mike Johnson", status: :away, latency: 51},
      %{id: 3, name: "Nikolai Tesla", status: :online, latency: 12},
      %{id: 4, name: "Ripley", status: :busy, latency: 5},
      %{id: 5, name: "Neo", status: :offline, latency: nil}
    ]

    agent_insights = [
      %{
        id: "stability",
        name: "Stability Sentinel",
        status: :active,
        depth: "5 playbooks",
        summary: "Watching cluster posture and maintaining redundancy",
        description:
          "Runs proactive failover drills and verifies quorum health across Thunderblock nodes.",
        next_action: "Validate replica sync for Thunderbolt edge region",
        signals: [
          "Replica lag trending 12%",
          "Event jitter within tolerance",
          "No lost heartbeats"
        ]
      },
      %{
        id: "recovery",
        name: "Recovery Operator",
        status: :preparing,
        depth: "3 playbooks",
        summary: "Stages incident responses for degraded agents domain",
        description:
          "Coordinates with Thunderflow to queue remediation steps for any domain flagged as critical.",
        next_action: "Draft restart plan for Agents domain",
        signals: ["Agent queue depth high", "Last drill 42m ago", "Fallback cache warm"]
      },
      %{
        id: "insight",
        name: "Insight Cartographer",
        status: :idle,
        depth: "7 playbooks",
        summary: "Maps telemetry streams into operator-ready narratives",
        description:
          "Aggregates KPI deltas, clusters anomalies, and prepares summaries for command briefings.",
        next_action: "Awaiting new KPI drift beyond threshold",
        signals: ["NDJSON stream stable", "No open annotations", "Dashboard baselines aligned"]
      }
    ]

    socket =
      socket
      |> assign(:domains, @sample_domains)
      |> assign(:open_domains, open)
      |> assign(:active_domain, first_child.id)
      |> assign(:events, initial_events)
      |> assign(:kpis, compute_kpis())
      |> assign(:graph_nodes, nodes)
      |> assign(:edge_counts, edge_counts)
      |> assign(:domain_map_nodes, [])
      |> assign(:domain_map_edges, [])
      |> assign(:domain_map_health, %{})
      |> assign(:selected_map_node, nil)
      |> assign(:friends, friends)
      |> assign(:active_friend, friends |> hd() |> Map.get(:id))
      |> assign(:agent_insights, agent_insights)
      |> assign(:active_agent, agent_insights |> hd() |> Map.get(:id))
      |> assign(:ups_status, nil)
      |> assign(:ndjson, false)
      |> assign(:ai_messages, [])
      |> assign(:ai_busy, false)
      |> assign_new(:admin_tab_open, fn -> false end)
      |> assign_cerebros_summary()

    Logger.debug("[DashboardLive] mount end assigns_keys=#{socket.assigns |> map_size()}")
    {:ok, socket}
  end

  defp current_agent(agents, active_id) do
    Enum.find(agents, &(&1.id == active_id))
  end

  defp agent_button_classes(agent, active_id) do
    base = "border-white/10 hover:border-white/20 hover:bg-white/10"

    if agent.id == active_id do
      base <> " bg-white/10 border-white/20 shadow-md text-surface-strong"
    else
      base <> " bg-black/20 text-surface-subtle"
    end
  end

  defp agent_status_badge(:active), do: "badge-success"
  defp agent_status_badge(:preparing), do: "badge-warning"
  defp agent_status_badge(:idle), do: "badge-ghost"
  defp agent_status_badge(_), do: "badge-ghost"
  @max_domain_map_nodes 250

  @impl true
  def handle_info(:init_domain_map, socket) do
    started = System.monotonic_time(:millisecond)
    nodes = safe_call(&domain_map_nodes/0, [])
    trimmed = Enum.take(nodes, @max_domain_map_nodes)
    edges = domain_map_edges(trimmed)
    health = domain_map_health(trimmed)
    dur = System.monotonic_time(:millisecond) - started

    Logger.debug(
      "[DashboardLive] domain map built nodes=#{length(nodes)} trimmed=#{length(trimmed)} edges=#{length(edges)} ms=#{dur}"
    )

    {:noreply,
     socket
     |> assign(:domain_map_nodes, trimmed)
     |> assign(:domain_map_edges, edges)
     |> assign(:domain_map_health, health)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- DASHBOARD_SENTINEL -->
    <div class="max-w-7xl mx-auto px-4 py-6 relative">
      <header class="flex items-center gap-3 mb-5">
        <h1 class="text-lg font-semibold tracking-wide">Thunderline Dashboard</h1>
        <span class="text-[11px] text-surface-muted">realtime systems view</span>
        <a href="/thunderprism" class="ml-auto btn btn-ghost btn-xs text-cyan-400">
          <span class="w-2 h-2 rounded-full bg-cyan-400 mr-1"></span> Prism DAG
        </a>
        <a href="#" class="link text-xs text-surface-subtle hover:text-surface-strong">
          docs
        </a>
        <%= if can_admin?(@current_user) do %>
          <a href="/admin" class="btn btn-xs ml-2">Admin</a>
          <button class="btn btn-ghost btn-xs" phx-click="toggle_admin_tab">
            {if @admin_tab_open, do: "Hide", else: "Tab"}
          </button>
        <% end %>
      </header>
      <!-- Floating Admin iframe panel (role-gated) -->
      <%= if @admin_tab_open and can_admin?(@current_user) do %>
        <div class="fixed top-20 right-4 w-[640px] h-[480px] bg-neutral-900/95 backdrop-blur border border-white/10 rounded-xl shadow-2xl z-50 flex flex-col">
          <div class="flex items-center gap-2 p-2 border-b border-white/10 text-sm">
            <span class="w-2 h-2 rounded-full bg-sky-400" />
            <span class="font-semibold">Admin</span>
            <a href="/admin" class="link text-xs ml-auto" target="_blank" rel="noopener">open full</a>
            <button class="btn btn-ghost btn-xs" phx-click="toggle_admin_tab">close</button>
          </div>
          <div class="flex-1">
            <iframe src="/admin" class="w-full h-full border-0" referrerpolicy="no-referrer"></iframe>
          </div>
        </div>
      <% end %>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
        <!-- Column 1: Map + Inspector stacked -->
        <div class="space-y-6">
          <!-- 1. Domain Map -->
          <section class="panel p-4 flex flex-col h-[420px] max-h-[420px] overflow-hidden min-h-0">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-cyan-400" />
              <h3 class="font-semibold">Domain Map</h3>
              <span class="ml-auto text-xs text-surface-muted">interactive</span>
            </div>
            <div class="relative w-full flex-1 rounded-lg overflow-hidden bg-neutral-900/40">
              <svg
                viewBox="0 0 760 420"
                class="w-full h-full select-none"
                preserveAspectRatio="xMinYMin meet"
              >
                <defs>
                  <linearGradient id="wire" x1="0" x2="1">
                    <stop offset="0%" stop-color="#22d3ee" stop-opacity="0.9" />
                    <stop offset="100%" stop-color="#10b981" stop-opacity="0.9" />
                  </linearGradient>
                  <filter id="blur"><feGaussianBlur stdDeviation="6" /></filter>
                </defs>
                <%= for i <- 0..12 do %>
                  <line
                    x1="40"
                    y1={30 + i * 28}
                    x2="720"
                    y2={10 + i * 28}
                    stroke="#1f2937"
                    stroke-width="1"
                    opacity="0.45"
                  />
                <% end %>
                <% by_id = Map.new(@domain_map_nodes, &{&1.id, &1}) %>
                <%= for {e, _idx} <- Enum.with_index(@domain_map_edges) do %>
                  <% a = by_id[e.a]
                  b = by_id[e.b]
                  path = cubic_path(a, b) %>
                  <% hot =
                    is_nil(@selected_map_node) or e.a == @selected_map_node or
                      e.b == @selected_map_node %>
                  <% edge_id = "edge-" <> e.a <> "-" <> e.b %>
                  <g class="group">
                    <path
                      d={path}
                      stroke="#0ea5e9"
                      stroke-opacity={if hot, do: 0.22, else: 0.05}
                      stroke-width={if hot, do: 10, else: 8}
                      fill="none"
                      filter="url(#blur)"
                    />
                    <path
                      id={edge_id}
                      d={path}
                      stroke="url(#wire)"
                      stroke-width={if hot, do: 3, else: 1.4}
                      fill="none"
                      pathLength="1000"
                      class={"flow flow-edge " <> speed_class(e.traffic) <> (if hot, do: " hot", else: "")}
                    >
                      \n
                      <title>{e.a} -> {e.b} traffic {round(e.traffic * 100)}%</title>
                    </path>
                    <circle r="3" fill="#22d3ee" class="flow-particle">
                      <animateMotion
                        dur={edge_duration(e.traffic)}
                        repeatCount="indefinite"
                        rotate="auto"
                      >
                        <mpath href={"#" <> edge_id} />
                      </animateMotion>
                    </circle>
                  </g>
                <% end %>
                <%= for n <- @domain_map_nodes do %>
                  <% selected = n.id == @selected_map_node %>
                  <% connected = Enum.any?(@domain_map_edges, &(&1.a == n.id or &1.b == n.id)) %>
                  <% ring = ring_size(selected, connected) %>
                  <% color = domain_map_status_color(@domain_map_health[n.id][:status]) %>
                  <g phx-click="select_map_node" phx-value-id={n.id} class="cursor-pointer">
                    <circle
                      cx={n.x}
                      cy={n.y}
                      r={14 + ring}
                      fill="none"
                      stroke={color}
                      stroke-opacity="0.35"
                      stroke-width={ring}
                    />
                    <circle cx={n.x} cy={n.y} r="14" fill={color} opacity="0.85" />
                    <text x={n.x + 20} y={n.y + 4} font-size="12" fill="currentColor">{n.label}</text>
                  </g>
                <% end %>
              </svg>
            </div>
          </section>
          <!-- 2. Inspector -->
          <section class="panel p-4 flex flex-col h-[420px]">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-emerald-400" />
              <h3 class="font-semibold">Inspector</h3>
              <span class="ml-auto text-xs text-surface-muted">
                {if @selected_map_node, do: @selected_map_node, else: "select a node"}
              </span>
            </div>
            <div class="flex-1 overflow-y-auto">
              <%= if @selected_map_node do %>
                <% h = @domain_map_health[@selected_map_node] %>
                <div class="space-y-3">
                  <div class="flex items-center gap-3">
                    <div class={"badge badge-outline " <> (case h.status do :healthy -> "badge-success"; :warning -> "badge-warning"; :critical -> "badge-error"; _ -> "" end)}>
                      {h.status}
                    </div>
                    <div class="text-base font-semibold">{@selected_map_node}</div>
                    <button
                      class="btn btn-ghost btn-xs ml-auto"
                      phx-click="select_map_node"
                      phx-value-id=""
                    >
                      x
                    </button>
                  </div>
                  <div class="grid grid-cols-3 gap-2 text-sm">
                    <div class="p-2 rounded-lg bg-white/5 border border-white/10">
                      <div class="text-xs text-surface-soft">Ops/min</div>
                      <div class="text-base text-surface-strong">{h.ops}</div>
                    </div>
                    <div class="p-2 rounded-lg bg-white/5 border border-white/10">
                      <div class="text-xs text-surface-soft">CPU%</div>
                      <div class="text-base text-surface-strong">{h.cpu}</div>
                    </div>
                    <div class="p-2 rounded-lg bg-white/5 border border-white/10">
                      <div class="text-xs text-surface-soft">p95</div>
                      <div class="text-base text-surface-strong">{h.p95}ms</div>
                    </div>
                  </div>
                  <div class="grid grid-cols-2 gap-2">
                    <button class="btn btn-sm btn-outline">Open Logs</button>
                    <button class="btn btn-sm btn-outline">Restart</button>
                    <button class="btn btn-sm btn-outline">Tail Metrics</button>
                    <button class="btn btn-sm btn-outline">Quarantine</button>
                  </div>
                  <p class="text-[10px] text-surface-soft">Errors: {h.errors}</p>
                </div>
              <% else %>
                <div class="text-sm text-surface-subtle">
                  Click a node to inspect health, metrics and actions.
                </div>
              <% end %>
            </div>
          </section>
        </div>
        
    <!-- Column 2: KPIs + Event Flow + Controls -->
        <div class="space-y-6">
          <!-- 3. KPIs -->
          <section class="panel p-4 flex flex-col">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-emerald-400" />
              <h3 class="font-semibold">KPIs</h3>
            </div>
            <div class="stats stats-vertical lg:stats-horizontal w-full">
              <%= for {label, value, delta} <- @kpis do %>
                <div class="stat">
                  <div class="stat-title">{label}</div>
                  <div class={"stat-value " <> (if label == "Ops/min", do: "text-emerald-300", else: "") }>
                    {value}
                  </div>
                  <%= if delta do %>
                    <div class={"stat-desc " <> (if String.starts_with?(delta, "+"), do: "text-emerald-400", else: "text-rose-300") }>
                      {delta}
                    </div>
                  <% end %>
                </div>
              <% end %>
              <%= if @ups_status do %>
                <div class="stat">
                  <div class="stat-title">UPS</div>
                  <div class={"stat-value text-xs " <> (case @ups_status do "online" -> "text-emerald-300"; "on_battery" -> "text-warning"; "low_battery" -> "text-error"; _ -> "" end)}>
                    {@ups_status}
                  </div>
                  <div class="stat-desc">power</div>
                </div>
              <% end %>
            </div>
          </section>
          <!-- 5. Event Flow (scrollable) -->
          <section class="panel p-4 flex flex-col panel-420 overflow-hidden min-h-0">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-violet-400" />
              <h3 class="font-semibold">Event Flow</h3>
              <span class="ml-2 text-xs text-surface-muted">last {length(@events)}</span>
              <button
                class="btn btn-ghost btn-xs"
                phx-click="select_domain"
                phx-value-id={@active_domain}
              >
                refresh
              </button>
              <button
                class={"btn btn-ghost btn-xs ml-2 " <> if @ndjson, do: "text-emerald-400", else: "opacity-60"}
                phx-click="toggle_ndjson"
              >
                NDJSON
              </button>
            </div>
            <div id="eventFeed" class="mt-1 flex-1 feed-scroll thin-scrollbar space-y-2 text-xs pr-1">
              <%= for e <- @events do %>
                <div class="p-2 rounded-lg bg-white/5 border border-white/10">
                  <div class="flex items-center gap-2 text-[10px] mb-0.5 text-surface-subtle">
                    <span class="badge badge-ghost badge-xs">{e.source}</span>
                    <%= if Map.get(e, :anomaly) do %>
                      <span class="badge badge-error badge-xs">anomaly</span>
                    <% end %>
                    <time class="text-surface-soft">{e.time}</time>
                  </div>
                  <div class="text-[11px] leading-snug text-surface-strong">{e.message}</div>
                </div>
              <% end %>
            </div>
          </section>
          <!-- 6. Controls -->
          <section class="panel p-4 flex flex-col">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-emerald-400" />
              <h3 class="font-semibold">Controls</h3>
            </div>
            <div class="grid grid-cols-2 gap-3 text-sm">
              <button class="btn btn-outline btn-sm" phx-click="checkpoint">Checkpoint</button>
              <button class="btn btn-outline btn-sm" phx-click="restore">Restore</button>
              <button class="btn btn-outline btn-sm">Deploy</button>
              <button class="btn btn-outline btn-sm">Restart</button>
              <button class="btn btn-primary btn-sm col-span-2" phx-click="inject_demo">
                Inject Demo Event
              </button>
            </div>
            <p class="mt-3 text-[10px] text-surface-soft">actions affect selected node (future)</p>
            <% summary = @cerebros_summary || %{} %>
            <div class="mt-4 rounded-xl border border-white/10 bg-white/5 p-4 space-y-4 text-sm">
              <div class="flex items-center gap-2">
                <div class="w-2 h-2 rounded-full bg-sky-400" />
                <h4 class="font-semibold">Cerebros NAS</h4>
                <span class="badge badge-outline badge-xs ml-auto">
                  {if Map.get(summary, :enabled?, false), do: "enabled", else: "disabled"}
                </span>
              </div>
              <%= if Map.get(summary, :enabled?, false) do %>
                <% active_run = Map.get(summary, :active_run) %>
                <div class="space-y-2">
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-surface-muted">Active run</span>
                    <%= if Map.get(summary, :mlflow_tracking_uri) do %>
                      <a
                        href={Map.get(summary, :mlflow_tracking_uri)}
                        target="_blank"
                        rel="noopener"
                        class="link text-[11px]"
                      >
                        MLflow
                      </a>
                    <% end %>
                  </div>
                  <%= if active_run do %>
                    <div class="rounded-lg border border-white/10 bg-black/20 p-3 text-xs">
                      <div class="flex items-center gap-2">
                        <span class="font-semibold text-surface-strong">
                          {cerebros_short_id(Map.get(active_run, :run_id))}
                        </span>
                        <span class={cerebros_badge_class(Map.get(active_run, :state))}>
                          {format_cerebros_state(Map.get(active_run, :state))}
                        </span>
                        <span class="ml-auto text-[10px] text-surface-muted">
                          started {format_cerebros_timestamp(Map.get(active_run, :started_at))}
                        </span>
                      </div>
                      <div class="mt-1 flex items-center justify-between text-[11px] text-surface-subtle">
                        <span>Trials {Map.get(active_run, :completed_trials, 0)}</span>
                        <span>Best {format_cerebros_metric(Map.get(active_run, :best_metric))}</span>
                      </div>
                      <%= if msg = Map.get(active_run, :error_message) do %>
                        <p class="mt-2 text-[11px] text-error">{msg}</p>
                      <% end %>
                    </div>
                  <% else %>
                    <p class="text-xs text-surface-subtle">
                      No active run. Launch one to populate live metrics.
                    </p>
                  <% end %>
                </div>
                <% runs = Map.get(summary, :runs, []) |> Enum.take(3) %>
                <div class="space-y-2">
                  <div class="text-xs font-semibold text-surface-strong">Recent runs</div>
                  <%= if runs == [] do %>
                    <p class="text-[11px] text-surface-subtle">No runs recorded yet.</p>
                  <% else %>
                    <ul class="space-y-2 text-[11px]">
                      <%= for run <- runs do %>
                        <li class="flex items-center gap-2">
                          <span class="font-medium text-surface-strong">
                            {cerebros_short_id(Map.get(run, :run_id))}
                          </span>
                          <span class={cerebros_badge_class(Map.get(run, :state))}>
                            {format_cerebros_state(Map.get(run, :state))}
                          </span>
                          <span class="ml-auto text-surface-muted">
                            best {format_cerebros_metric(Map.get(run, :best_metric))}
                          </span>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
                <% trials = Map.get(summary, :trials, []) |> Enum.take(3) %>
                <%= if trials != [] do %>
                  <div class="space-y-2">
                    <div class="text-xs font-semibold text-surface-strong">Latest trials</div>
                    <ul class="space-y-2 text-[11px]">
                      <%= for trial <- trials do %>
                        <li class="flex items-center gap-2">
                          <span class="font-medium text-surface-strong">
                            {cerebros_short_id(Map.get(trial, :trial_id))}
                          </span>
                          <span class={cerebros_badge_class(Map.get(trial, :status))}>
                            {format_cerebros_state(Map.get(trial, :status))}
                          </span>
                          <span class="text-surface-muted">
                            {format_cerebros_metric(Map.get(trial, :metric))}
                          </span>
                          <span class="ml-auto text-[10px] text-surface-soft">
                            {format_cerebros_timestamp(Map.get(trial, :inserted_at))}
                          </span>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
                <button
                  class={[
                    "btn btn-accent btn-sm w-full",
                    not Map.get(summary, :enabled?, false) && "btn-disabled opacity-50"
                  ]}
                  phx-click="launch_cerebros_run"
                  disabled={!Map.get(summary, :enabled?, false)}
                >
                  Launch quick NAS run
                </button>
                <p class="text-[10px] text-surface-soft">
                  Uses default spec via Cerebros bridge; switch to MLflow for deeper analytics.
                </p>
              <% else %>
                <p class="text-xs text-surface-subtle">
                  Cerebros bridge is disabled. Export <code>CEREBROS_ENABLED=1</code> and rerun the
                  dashboard to enable NAS orchestration.
                </p>
              <% end %>
            </div>
          </section>
        </div>
        
    <!-- Column 3: Peers + Trends (+ AI assistant) -->
        <div class="space-y-6">
          <!-- 4. Peers -->
          <section class="panel p-4 flex flex-col">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-emerald-400" />
              <h3 class="font-semibold">Peers</h3>
            </div>
            <ul class="space-y-1 text-sm flex-1 overflow-auto">
              <%= for f <- @friends do %>
                <li>
                  <button
                    phx-click="select_friend"
                    phx-value-id={f.id}
                    class={"w-full text-left px-3 py-2 rounded-xl transition border border-white/5 hover:bg-white/5 flex items-center gap-3 " <> (if @active_friend == f.id, do: "bg-white/10", else: "") }
                  >
                    <span class={"w-2 h-2 rounded-full " <> friend_dot(f.status)}></span>
                    <span class="truncate flex-1">{f.name}</span>
                    <span class="ml-auto text-xs text-surface-muted uppercase">{f.status}</span>
                    <%= if f.latency do %>
                      <span class="text-[10px] ml-2 text-primary">{f.latency}ms</span>
                    <% end %>
                  </button>
                </li>
              <% end %>
            </ul>
            <div class="mt-4 grid grid-cols-2 gap-2">
              <button class="btn btn-sm btn-ghost border border-white/10">New Chat</button>
              <button class="btn btn-sm btn-ghost border border-white/10">Create Room</button>
            </div>
            <p class="mt-4 text-[10px] text-surface-soft">peer status reflects last heartbeat</p>
          </section>
          <!-- 8. Agent Ops -->
          <section class="panel p-4 flex flex-col">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-amber-400" />
              <h3 class="font-semibold">Agent Ops</h3>
              <span class="ml-auto text-xs text-surface-muted">autonomy</span>
            </div>
            <div class="grid gap-3 lg:grid-cols-2">
              <div class="space-y-2">
                <%= for agent <- @agent_insights do %>
                  <button
                    phx-click="select_agent"
                    phx-value-id={agent.id}
                    class={"w-full text-left px-3 py-2 rounded-lg border transition-colors duration-200 " <>
                                  agent_button_classes(agent, @active_agent)}
                  >
                    <div class="flex items-center gap-2">
                      <span class="font-semibold text-surface-strong">{agent.name}</span>
                      <span class={"badge badge-xs " <> agent_status_badge(agent.status)}>
                        {agent.status}
                      </span>
                    </div>
                    <p class="text-[11px] text-surface-muted">{agent.summary}</p>
                  </button>
                <% end %>
              </div>
              <div class="rounded-lg border border-white/10 bg-white/5 p-3 space-y-3">
                <% active_agent = current_agent(@agent_insights, @active_agent) %>
                <%= if active_agent do %>
                  <div class="flex items-center gap-2">
                    <span class={"badge badge-sm " <> agent_status_badge(active_agent.status)}>
                      {active_agent.status}
                    </span>
                    <span class="panel-subtitle">{active_agent.depth}</span>
                  </div>
                  <p class="text-sm text-surface-strong">{active_agent.description}</p>
                  <div>
                    <h4 class="text-xs panel-subtitle mb-1">Next action</h4>
                    <p class="text-[11px] text-surface-subtle">{active_agent.next_action}</p>
                  </div>
                  <div>
                    <h4 class="text-xs panel-subtitle mb-1">Signals</h4>
                    <ul class="space-y-1 text-[11px] text-surface-muted">
                      <%= for sig <- active_agent.signals do %>
                        <li class="flex items-center gap-2">
                          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                          <span>{sig}</span>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% else %>
                  <p class="text-sm text-surface-subtle">
                    Select an agent to inspect its current mission.
                  </p>
                <% end %>
              </div>
            </div>
          </section>
          <!-- 7. Trends / Sparkline -->
          <section class="panel p-4 flex flex-col">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2 h-2 rounded-full bg-cyan-400" />
              <h3 class="font-semibold">Trends</h3>
              <span class="ml-auto text-xs text-surface-muted">preview</span>
            </div>
            <div class="flex-1 flex items-center justify-center">
              <svg viewBox="0 0 200 60" class="w-full h-16">
                <polyline
                  fill="none"
                  stroke="#22d3ee"
                  stroke-width="2"
                  stroke-linejoin="round"
                  stroke-linecap="round"
                  points={sparkline_points(@kpis)}
                />
              </svg>
            </div>
            <p class="text-[10px] text-surface-soft mt-2">derived sample sparkline of KPI values</p>
          </section>
          <%= if feature_enabled?(:ai_chat_panel) do %>
            <!-- 9. AI Chat Panel (experimental) -->
            <section class="panel p-4 flex flex-col h-[420px]">
              <div class="flex items-center gap-2 mb-2">
                <div class="w-2 h-2 rounded-full bg-fuchsia-400" />
                <h3 class="font-semibold">AI Assistant</h3>
                <span class="ml-auto text-xs text-surface-muted">experimental</span>
              </div>
              <div id="aiChatFeed" class="flex-1 overflow-y-auto space-y-2 pr-1 text-xs">
                <%= if @ai_messages == [] do %>
                  <div class="p-2 rounded bg-white/5 border border-white/10 text-surface-subtle">
                    No messages yet. Ask the system about recent events or type /help.
                  </div>
                <% end %>
                <%= for m <- (@ai_messages || []) |> Enum.reverse() do %>
                  <div class={"p-2 rounded-lg border text-[11px] leading-snug " <> (if m.role == :user, do: "bg-sky-500/10 border-sky-500/30", else: "bg-fuchsia-500/10 border-fuchsia-500/30")}>
                    <div class="flex items-center gap-2 mb-0.5 text-surface-subtle">
                      <span class="badge badge-ghost badge-xs">{m.role}</span>
                      <time class="text-surface-soft">{m.time}</time>
                    </div>
                    <div class="text-surface-strong">{m.text}</div>
                  </div>
                <% end %>
              </div>
              <form phx-submit="ai_send" class="mt-2 flex gap-2">
                <input
                  name="q"
                  autocomplete="off"
                  placeholder="Ask Thunderline..."
                  class="input input-sm input-bordered flex-1"
                />
                <button class="btn btn-sm" type="submit" disabled={@ai_busy}>
                  {if @ai_busy, do: "...", else: "Send"}
                </button>
              </form>
              <p class="mt-2 text-[10px] text-surface-soft">
                Backed by Ash AI (stub). Commands: /help, /kpis, /events [n]
              </p>
            </section>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Toggle Admin tab visibility
  @impl true
  def handle_event("toggle_admin_tab", _params, socket) do
    {:noreply, assign(socket, :admin_tab_open, !socket.assigns[:admin_tab_open])}
  end

  @impl true
  def handle_event("launch_cerebros_run", _params, socket) do
    summary = socket.assigns[:cerebros_summary] || CerebrosSummary.snapshot()

    if Map.get(summary, :enabled?, false) do
      operator = dashboard_operator(socket.assigns[:current_user])
      meta_override = %{"trigger" => "dashboard_quick_run"}
      spec = Validator.default_spec()

      case RunOptions.prepare(spec, source: "dashboard", operator: operator, meta: meta_override) do
        {:error, :invalid_spec} ->
          {:noreply, put_flash(socket, :error, "Unable to prepare NAS spec")}

        {run_id, prepared_spec, enqueue_opts} ->
          case CerebrosBridge.enqueue_run(prepared_spec, enqueue_opts) do
            {:ok, _job} ->
              {:noreply,
               socket
               |> put_flash(:info, "Queued NAS run #{cerebros_short_id(run_id)}")
               |> refresh_cerebros_summary()}

            {:error, :bridge_disabled} ->
              {:noreply, put_flash(socket, :error, "Cerebros bridge disabled")}

            {:error, reason} ->
              {:noreply,
               put_flash(socket, :error, "Failed to enqueue NAS run: #{inspect(reason)}")}
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Enable the ml_nas feature flag to run Cerebros")}
    end
  end

  @impl true
  def handle_event("select_map_node", %{"id" => id}, socket) do
    # Blank id clears selection. Ignore unknown ids gracefully.
    id = empty_to_nil(id)
    valid_ids = Map.keys(socket.assigns.domain_map_health)
    sel = if id in valid_ids, do: id, else: nil
    {:noreply, assign(socket, :selected_map_node, sel)}
  end

  @impl true
  def handle_event("select_domain", %{"id" => id}, socket) do
    # Refresh events & graph context for the chosen domain (or keep current if nil)
    id = empty_to_nil(id) || socket.assigns.active_domain
    events = live_events_snapshot(id) |> Enum.take(5)
    nodes = graph_nodes()
    edge_counts = compute_edge_counts(events, nodes)

    {:noreply,
     socket
     |> assign(:active_domain, id)
     |> assign(:events, events)
     |> assign(:graph_nodes, nodes)
     |> assign(:edge_counts, edge_counts)}
  end

  @impl true
  def handle_event("select_friend", %{"id" => id}, socket) do
    with {int_id, _} <- Integer.parse(to_string(id)),
         true <- Enum.any?(socket.assigns.friends, &(&1.id == int_id)) do
      {:noreply, assign(socket, :active_friend, int_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_agent", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.agent_insights, &(&1.id == id)) do
      nil -> {:noreply, socket}
      _ -> {:noreply, assign(socket, :active_agent, id)}
    end
  end

  # Defensive catch-all so unexpected events never crash the LiveView.
  @impl true
  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # ---- Assign refresh helpers ---------------------------------------------------
  defp refresh_events_assigns(socket) do
    events = live_events_snapshot(socket.assigns.active_domain) |> Enum.take(5)
    # Optional NDJSON logging
    if socket.assigns[:ndjson] do
      Enum.each(events, fn e ->
        safe_try(fn -> NDJSON.write(%{source: e.source, time: e.time, message: e.message}) end)
      end)
    end

    nodes = graph_nodes()
    edge_counts = compute_edge_counts(events, nodes)
    # Periodically recompute simulated health so UI isn't static (demo behavior)
    health = domain_map_health(socket.assigns[:domain_map_nodes] || [])

    socket
    |> assign(:events, events)
    |> assign(:graph_nodes, nodes)
    |> assign(:edge_counts, edge_counts)
    |> assign(:domain_map_health, health)
  end

  defp assign_cerebros_summary(socket) do
    summary = CerebrosSummary.snapshot()
    assign(socket, :cerebros_summary, summary)
  end

  defp refresh_cerebros_summary(socket), do: assign_cerebros_summary(socket)

  # ---- Data & formatting helpers ------------------------------------------------
  defp compute_kpis do
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

  # Build minimal KPIs directly from an incoming :metrics_update payload so we
  # don't need to perform another metrics fetch.
  defp build_kpis_from_metrics(%{system: sys} = payload) do
    events = Map.get(payload, :events, %{})
    agents = Map.get(payload, :agents, %{})
    _thunderlane = Map.get(payload, :thunderlane, %{})

    mem_total = get_in(sys, [:memory, :total]) || 0
    uptime = Map.get(sys, :uptime, 0)
    # events.processing_rate is per second -> per minute
    ops_per_min = (Map.get(events, :processing_rate, 0.0) * 60) |> round()
    active_users = Map.get(agents, :active_agents, 0)

    [
      {"Ops/min", format_number(ops_per_min), nil},
      {"Users", format_number(active_users), nil},
      {"Mem", format_number(div(mem_total, 1024 * 1024)) <> "M", nil},
      {"Uptime", "#{uptime}s", nil}
    ]
  end

  defp build_kpis_from_metrics(_), do: compute_kpis()

  defp live_events_snapshot(domain_id) do
    list =
      safe_call(
        fn ->
          # Guard against any unexpected blocking in EventBuffer by using a short timeout
          task = Task.async(fn -> EventBuffer.snapshot(50) end)

          try do
            Task.await(task, 250)
          catch
            :exit, _ -> []
          end
        end,
        []
      )

    case list do
      [] ->
        seed_events(domain_id)

      list ->
        list
        |> Enum.map(fn evt ->
          base = %{
            source: source_from_evt(evt),
            time: time_hhmmss(System.os_time(:second)),
            message: message_from_evt(evt, domain_id)
          }

          Map.put(base, :anomaly, anomaly?(base))
        end)
        |> Enum.reject(fn %{message: m} ->
          is_binary(m) and String.starts_with?(m, "system file changed")
        end)
        |> then(fn cleaned -> if cleaned == [], do: seed_events(domain_id), else: cleaned end)
    end
  end

  defp anomaly?(%{message: m} = e) do
    msg = String.downcase(to_string(m || ""))
    kw = ["error", "fail", "timeout", "panic", "battery", "overload"]
    kw_hit = Enum.any?(kw, &String.contains?(msg, &1))
    entropy = :erlang.phash2({e.source, e.time})
    kw_hit or rem(entropy, 20) == 0
  end

  # Topology (hex-ish row)
  defp graph_nodes do
    children = @sample_domains |> hd() |> Map.get(:children, [])
    base = 40

    Enum.with_index(children, fn c, idx ->
      cx = 80 + idx * 140
      cy = 90 + if rem(idx, 2) == 0, do: 0, else: 35

      %{
        id: c.id,
        label: c.title,
        status: c.status,
        cx: cx,
        cy: cy,
        size: base,
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

  # Domain map dynamic hex layout ------------------------------------------------
  # Build nodes from @sample_domains (root + children) placed on a hex spiral.
  defp domain_map_nodes do
    root = hd(@sample_domains)
    # flatten: root first, then its children; could extend to multiple domain trees later
    all = [root | root.children || []]
    coords = hex_spiral_positions(length(all))
    # scale & shift into viewBox (760x420)
    size = 46.0
    pts = Enum.map(coords, &hex_to_pixel(&1, size))
    min_x = pts |> Enum.map(& &1.x) |> Enum.min(fn -> 0 end)
    min_y = pts |> Enum.map(& &1.y) |> Enum.min(fn -> 0 end)
    # shift so everything is inside positive space with margins
    margin_x = 120 - min_x
    margin_y = 110 - min_y

    Enum.zip(all, pts)
    |> Enum.map(fn {dom, %{x: x, y: y}} ->
      id = Map.get(dom, :id) || Map.get(dom, "id")
      label = Map.get(dom, :title) || Map.get(dom, "title") || id
      # depth variance
      z = :erlang.phash2(id, 40) - 20
      %{id: id, label: label, x: x + margin_x, y: y + margin_y, z: z}
    end)
  end

  # Create edges: connect root to each child, plus ring between sequential children
  defp domain_map_edges(nodes) when is_list(nodes) do
    case nodes do
      [] ->
        []

      [root | children] ->
        star =
          Enum.map(children, fn c ->
            %{a: root.id, b: c.id, traffic: traffic_level(root.id, c.id)}
          end)

        ring =
          children
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> %{a: a.id, b: b.id, traffic: traffic_level(a.id, b.id)} end)
          |> then(fn r ->
            case children do
              [] ->
                r

              [_] ->
                r

              _ ->
                r ++
                  [
                    %{
                      a: List.last(children).id,
                      b: hd(children).id,
                      traffic: traffic_level(List.last(children).id, hd(children).id)
                    }
                  ]
            end
          end)

        star ++ ring
    end
  end

  defp domain_map_health(nodes) do
    Enum.reduce(nodes, %{}, fn n, acc ->
      seed = :erlang.phash2(n.id, 1000)

      status =
        cond do
          rem(seed, 23) == 0 -> :critical
          rem(seed, 9) == 0 -> :warning
          true -> :healthy
        end

      Map.put(acc, n.id, %{
        status: status,
        ops: 400 + rem(seed, 600),
        cpu: 10 + rem(div(seed, 7), 70),
        p95: 80 + rem(div(seed, 11), 220),
        errors: rem(div(seed, 13), 8)
      })
    end)
  end

  # Hex spiral axial coordinate generation (center (0,0), expanding rings)
  defp hex_spiral_positions(n) when n <= 1, do: [%{q: 0, r: 0}]

  defp hex_spiral_positions(n) do
    # directions in axial coords (pointy-top)
    dirs = [{1, 0}, {0, 1}, {-1, 1}, {-1, 0}, {0, -1}, {1, -1}]

    stream =
      Stream.unfold({1, []}, fn {radius, _} ->
        # start at (radius,0)
        start = {radius, 0}

        ring =
          Enum.reduce(dirs, {start, []}, fn {dq, dr}, {{cq, cr}, acc} ->
            steps =
              for _ <- 1..radius, reduce: {cq, cr, acc} do
                {sq, sr, acc2} ->
                  nq = sq + dq
                  nr = sr + dr
                  {nq, nr, [{nq, nr} | acc2]}
              end

            {lq, lr, acc_ring} = steps
            {{lq, lr}, acc_ring}
          end)
          |> elem(1)
          |> Enum.reverse()

        {ring, {radius + 1, []}}
      end)
      |> Enum.flat_map(& &1)
      |> Enum.take(n - 1)

    [%{q: 0, r: 0} | Enum.map(stream, fn {q, r} -> %{q: q, r: r} end)]
  end

  defp hex_to_pixel(%{q: q, r: r}, size) do
    x = size * (:math.sqrt(3) * q + :math.sqrt(3) / 2 * r)
    y = size * (3.0 / 2.0 * r)
    %{x: x, y: y}
  end

  defp traffic_level(a, b) do
    h = :erlang.phash2({a, b}, 1000)
    0.3 + rem(h, 500) / 1000
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

  # Duration for particle travel (inverse-ish to traffic level)
  defp edge_duration(t) when is_number(t) do
    cond do
      t >= 0.8 -> "2.8s"
      t >= 0.6 -> "3.6s"
      t >= 0.4 -> "4.5s"
      true -> "5.2s"
    end
  end

  defp edge_duration(_), do: "4s"

  defp friend_dot(:online), do: "dot-online"
  defp friend_dot(:away), do: "dot-away"
  defp friend_dot(:busy), do: "dot-busy animate-pulse"
  defp friend_dot(:offline), do: "dot-offline"
  defp friend_dot(_), do: "dot-offline"

  # Map health status to SVG color (match Tailwind palette-ish)
  # emerald-500
  defp domain_map_status_color(:healthy), do: "#10b981"
  # amber-500
  defp domain_map_status_color(:warning), do: "#f59e0b"
  # red-500
  defp domain_map_status_color(:critical), do: "#ef4444"
  # slate-500 fallback
  defp domain_map_status_color(_), do: "#64748b"

  defp ring_size(true, _conn), do: 4
  defp ring_size(false, true), do: 2
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

  defp source_from_evt(%{type: t}) when is_binary(t), do: t
  defp source_from_evt(%{source: s}) when is_binary(s), do: s
  defp source_from_evt(_), do: "thundergrid"

  defp message_from_evt(%{message: m}, _d) when is_binary(m), do: m

  defp message_from_evt(%{payload: p}, d) when is_map(p),
    do: "#{inspect(Map.take(p, [:id, :status]))} in #{d}"

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
      n >= 1_000 -> :io_lib.format("~.1fK", [n / 1_000]) |> IO.iodata_to_binary()
      true -> Integer.to_string(n)
    end
  end

  defp format_number(n) when is_float(n), do: format_number(round(n))
  defp format_number(other), do: to_string(other)

  defp toggle_set(%MapSet{} = set, id),
    do: if(MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp seed_events(domain_id) do
    now = System.os_time(:second)

    for i <- 0..4 do
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
  defp empty_to_nil(v), do: v

  # Build SVG polyline points for mini sparkline from KPI list
  # Expects list like [{label, value_string, _meta}]. We attempt to parse leading integer.
  defp sparkline_points(kpis) when is_list(kpis) do
    vals =
      kpis
      |> Enum.map(fn {_label, v, _meta} ->
        case Integer.parse(to_string(v)) do
          {n, _} -> n
          :error -> 10
        end
      end)

    smoothed = smooth(vals, 3)

    smoothed
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {val, i} ->
      y = 60 - rem(val, 50)
      "#{i * 40},#{y}"
    end)
  end

  defp sparkline_points(_), do: ""

  defp smooth(list, w) when is_list(list) and w > 1 do
    Enum.chunk_every(list, w, 1, :discard)
    |> Enum.map(fn chunk -> div(Enum.sum(chunk), length(chunk)) end)
  end

  defp smooth(list, _), do: list

  # Transform KPI tuples {label, value, delta} into maps for JSON encoding.
  defp json_kpis(list) when is_list(list) do
    Enum.map(list, fn
      {label, value, delta} -> %{label: label, value: value, delta: delta}
      %{label: _} = m -> m
      other -> %{label: to_string(inspect(other)), value: nil, delta: nil}
    end)
  end

  defp json_kpis(_), do: []

  @impl true
  def handle_event("toggle_ndjson", _params, socket) do
    {:noreply, assign(socket, :ndjson, !socket.assigns.ndjson)}
  end

  @impl true
  def handle_event("checkpoint", _params, socket) do
    data = %{
      kpis: socket.assigns.kpis,
      selected_map_node: socket.assigns.selected_map_node,
      timestamp: DateTime.utc_now()
    }

    safe_try(fn -> Checkpoint.write(data) end)
    {:noreply, socket}
  end

  @impl true
  def handle_event("restore", _params, socket) do
    case safe_call(fn -> Checkpoint.read() end, :error) do
      {:ok, map} ->
        {:noreply,
         socket
         |> assign(:kpis, Map.get(map, :kpis, socket.assigns.kpis))
         |> assign(
           :selected_map_node,
           Map.get(map, :selected_map_node, socket.assigns.selected_map_node)
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("inject_demo", _params, socket) do
    Logger.debug("[DashboardLive] manual inject_demo invoked")
    now = DateTime.utc_now()
    msg_text = "manual inject @ " <> time_hhmmss(System.os_time(:second))

    event = %{
      "event_type" => "dashboard_update",
      "data" => %{
        "component" => "demo_injector",
        "message" => msg_text,
        "key" => System.unique_integer([:positive])
      },
      "timestamp" => now
    }

    ui_event = %{
      source: "demo_injector",
      time: time_hhmmss(System.os_time(:second)),
      message: msg_text,
      anomaly: false
    }

    # Immediate optimistic UI update
    socket = assign(socket, :events, [ui_event | socket.assigns[:events] || []] |> Enum.take(50))

    # Persist & broadcast through the same batch path the pipeline uses
    safe_try(fn -> EventBuffer.put(event) end)

    safe_try(fn ->
      PubSub.broadcast(
        Thunderline.PubSub,
        "thunderline_web:dashboard",
        {:dashboard_batch_update, %{"updates" => [event]}}
      )
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("ai_send", %{"q" => raw}, socket) do
    if feature_enabled?(:ai_chat_panel) do
      q = String.trim(to_string(raw || ""))

      if q == "" do
        {:noreply, socket}
      else
        user_msg = %{role: :user, text: q, time: time_hhmmss(System.os_time(:second))}
        msgs = [user_msg | socket.assigns[:ai_messages] || []]
        {reply_role, reply_text} = ai_local_router(q, socket)
        ai_msg = %{role: reply_role, text: reply_text, time: time_hhmmss(System.os_time(:second))}

        {:noreply,
         socket |> assign(:ai_messages, [ai_msg | msgs]) |> assign_new(:ai_busy, fn -> false end)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:status, %{source: "ups"} = st}, socket) do
    status = to_string(Map.get(st, :stage, Map.get(st, :status, "unknown")))
    {:noreply, assign(socket, :ups_status, status)}
  end

  @impl true
  def handle_info({:run_update, _update}, socket) do
    {:noreply, refresh_cerebros_summary(socket)}
  end

  @impl true
  def handle_info({:trial_update, _update}, socket) do
    {:noreply, refresh_cerebros_summary(socket)}
  end

  @impl true
  def handle_info({:dashboard_batch_update, %{"updates" => updates} = payload}, socket) do
    # Convert realtime pipeline updates to UI-friendly events and append to feed
    Logger.debug(
      "[DashboardLive] batch_update count=#{length(updates)} keys=#{Enum.map(updates, &Map.keys/1) |> length}"
    )

    new_events =
      updates
      |> Enum.map(&to_ui_event/1)
      |> Enum.map(&Map.put(&1, :anomaly, anomaly?(&1)))

    events = (new_events ++ (socket.assigns[:events] || [])) |> Enum.take(50)

    # Persist raw updates into EventBuffer so periodic snapshot refreshes reflect them.
    Enum.each(updates, fn u -> safe_try(fn -> EventBuffer.put(u) end) end)

    # Refresh simulated domain map health so user sees dynamic change on batches
    refreshed_health = domain_map_health(socket.assigns[:domain_map_nodes] || [])

    # Optionally accept future kpi payload ("kpis" => list)
    socket =
      case Map.get(payload, "kpis") do
        kpis when is_list(kpis) and kpis != [] -> assign(socket, :kpis, kpis)
        _ -> socket
      end

    # If metrics are included elsewhere, we could refresh KPIs; keep lightweight for now
    {:noreply, socket |> assign(:events, events) |> assign(:domain_map_health, refreshed_health)}
  end

  @impl true
  def handle_info({:component_update, data}, socket) do
    # Component-specific updates; emit a succinct line in feed
    Logger.debug("[DashboardLive] component_update keys=#{data |> Map.keys() |> Enum.take(5)}")

    e = %{
      source: to_string(Map.get(data, "component", "component")),
      time: time_hhmmss(System.os_time(:second)),
      message: summarize_component(data)
    }

    {:noreply, assign(socket, :events, [e | socket.assigns.events || []] |> Enum.take(50))}
  end

  # Batch realtime updates from RealTimePipeline (topic: "thunderline_web:dashboard")

  @impl true
  def handle_info({:dashboard_event, evt}, socket) do
    # EventBuffer push path (fallback/compat)
    Logger.debug(
      "[DashboardLive] dashboard_event kind=#{Map.get(evt, :kind)} domain=#{Map.get(evt, :domain)}"
    )

    e = %{
      source: source_from_evt(evt),
      time: time_hhmmss(System.os_time(:second)),
      message: message_from_evt(evt, socket.assigns.active_domain)
    }

    {:noreply, assign(socket, :events, [e | socket.assigns.events || []] |> Enum.take(50))}
  end

  @impl true
  def handle_info(:refresh_events, socket) do
    {:noreply, refresh_events_assigns(socket)}
  end

  @impl true
  def handle_info(:refresh_kpis, socket) do
    {:noreply, assign(socket, :kpis, compute_kpis())}
  end

  @impl true
  def handle_info({:metrics_update, payload}, socket) when is_map(payload) do
    # Build KPIs straight from payload to reduce extra metric fetch calls
    kpis = build_kpis_from_metrics(payload)
    {:noreply, assign(socket, :kpis, kpis)}
  end

  # Defensive catch-all so unexpected messages don't crash the LiveView.
  @impl true
  def handle_info(_other, socket) do
    {:noreply, socket}
  end

  # ---- AI Panel helpers -------------------------------------------------------
  defp feature_enabled?(flag) do
    Application.get_env(:thunderline, :features, []) |> Keyword.get(flag, false)
  end

  defp ai_local_router("/help", _socket),
    do: {:assistant, "Commands: /help /kpis /events <n>. Ask natural questions about recent ops."}

  defp ai_local_router("/kpis", socket) do
    summary = socket.assigns.kpis |> Enum.map_join(", ", fn {l, v, _} -> "#{l}=#{v}" end)
    {:assistant, "Current KPIs: " <> summary}
  end

  defp ai_local_router(<<"/events", rest::binary>>, socket) do
    n =
      rest
      |> String.trim()
      |> case do
        <<>> ->
          3

        other ->
          case Integer.parse(other) do
            {i, _} -> max(1, min(i, 10))
            _ -> 3
          end
      end

    evs = socket.assigns.events |> Enum.take(n)

    text =
      evs
      |> Enum.map_join(" | ", fn e ->
        "#{e.time} #{e.source}: #{String.slice(e.message, 0, 40)}"
      end)

    {:assistant, "Recent events (#{n}): " <> text}
  end

  defp ai_local_router(q, socket) do
    {:assistant,
     "(stub) You said: '#{String.slice(q, 0, 140)}'. Events feed length=#{length(socket.assigns.events)}."}
  end

  defp to_ui_event(%{"event_type" => type, "data" => data} = ev) do
    %{
      source: to_string(type),
      time: time_hhmmss(System.os_time(:second)),
      message: summarize_realtime(ev, data)
    }
  end

  defp to_ui_event(other) when is_map(other) do
    %{
      source: to_string(Map.get(other, "event_type", Map.get(other, :event_type, "event"))),
      time: time_hhmmss(System.os_time(:second)),
      message: inspect(Map.get(other, "data", other))
    }
  end

  defp summarize_realtime(ev, data) do
    comp = get_in(ev, ["data", "component"]) || Map.get(data, "component")

    case comp do
      nil ->
        keys = data |> Map.keys() |> Enum.take(3)
        "#{Map.get(ev, "event_type")} #{Enum.map_join(keys, ",", &to_string/1)}"

      c ->
        "#{Map.get(ev, "event_type")} -> #{c}"
    end
  end

  defp summarize_component(data) do
    comp = Map.get(data, "component") || Map.get(data, :component)
    keys = data |> Map.delete("component") |> Map.delete(:component) |> Map.keys() |> Enum.take(3)
    (comp && to_string(comp) <> ": ") <> Enum.map_join(keys, ",", &to_string/1)
  end

  defp dashboard_operator(%{email: email}) when is_binary(email) and email != "", do: email
  defp dashboard_operator(%{name: name}) when is_binary(name) and name != "", do: name
  defp dashboard_operator(%{"email" => email}) when is_binary(email) and email != "", do: email
  defp dashboard_operator(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp dashboard_operator(_), do: "dashboard"

  defp cerebros_short_id(nil), do: "n/a"
  defp cerebros_short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp cerebros_short_id(id), do: to_string(id)

  defp cerebros_badge_class(:running), do: "badge badge-info badge-sm"
  defp cerebros_badge_class(:succeeded), do: "badge badge-success badge-sm"
  defp cerebros_badge_class(:failed), do: "badge badge-error badge-sm"
  defp cerebros_badge_class(:cancelled), do: "badge badge-ghost badge-sm"
  defp cerebros_badge_class(:initialized), do: "badge badge-outline badge-sm"
  defp cerebros_badge_class(_), do: "badge badge-outline badge-sm"

  defp format_cerebros_state(state) when is_atom(state),
    do: state |> Atom.to_string() |> String.upcase()

  defp format_cerebros_state(state) when is_binary(state), do: String.upcase(state)
  defp format_cerebros_state(state), do: state |> to_string() |> String.upcase()

  defp format_cerebros_metric(nil), do: "n/a"

  defp format_cerebros_metric(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 4)
  end

  defp format_cerebros_metric(value) when is_integer(value), do: Integer.to_string(value)
  defp format_cerebros_metric(value), do: to_string(value)

  defp format_cerebros_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  rescue
    _ -> DateTime.to_iso8601(dt)
  end

  defp format_cerebros_timestamp(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  rescue
    _ -> NaiveDateTime.to_iso8601(dt)
  end

  defp format_cerebros_timestamp(nil), do: "-"
  defp format_cerebros_timestamp(other), do: to_string(other)

  # Role-gated helper for Admin visibility
  defp can_admin?(%{role: role}) when role in [:owner, :steward, :system], do: true
  defp can_admin?(%{"role" => role}) when role in ["owner", "steward", "system"], do: true
  defp can_admin?(_), do: false
end
