defmodule ThunderlineWeb.ReflexPanelLive do
  @moduledoc """
  Thunderprism Reflex Panel LiveView (HC-Ω-3).

  Real-time visualization of the self-optimizing CA system:
  - Voxel automata grid with live state updates
  - PLV, entropy, λ̂ metrics charts
  - PAC evolution graphs and lineage tracking
  - Reflex event stream

  ## Features

  - **Voxel Grid**: 3D view of Thunderbit states (active, dormant, chaotic)
  - **Metrics Dashboard**: Real-time PLV, entropy, λ̂, Lyapunov charts
  - **Evolution Panel**: PAC fitness over generations, profile comparison
  - **Event Stream**: Live reflex events (stability, chaos, trust)
  - **Control Panel**: CA parameters, evolution profile selection

  ## Architecture

      ┌─────────────────────────────────────────────────────────────────┐
      │                    REFLEX PANEL LIVEVIEW                        │
      │                                                                 │
      │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
      │  │ Voxel Grid       │  │ Metrics Charts   │  │ Evolution    │  │
      │  │ (Three.js)       │  │ (Chart.js)       │  │ Panel        │  │
      │  └──────────────────┘  └──────────────────┘  └──────────────┘  │
      │           ↑                    ↑                    ↑          │
      │           └────────────────────┴────────────────────┘          │
      │                               │                                 │
      │                     PubSub: reflex_panel:updates               │
      │                               ↑                                 │
      │  ┌─────────────────────────────┴───────────────────────────┐   │
      │  │ Data Sources:                                            │   │
      │  │ - Thunderbit.Reflex (voxel states, events)              │   │
      │  │ - LoopMonitor (PLV, entropy, λ̂, Lyapunov)              │   │
      │  │ - Thunderpac.Evolution (fitness, generations)           │   │
      │  │ - TPEBridge (optimization trials)                       │   │
      │  └─────────────────────────────────────────────────────────┘   │
      └─────────────────────────────────────────────────────────────────┘

  ## PubSub Topics

  - `reflex_panel:metrics` - LoopMonitor metrics updates
  - `reflex_panel:voxels` - Voxel state changes
  - `reflex_panel:evolution` - PAC evolution events
  - `reflex_panel:reflexes` - Reflex event stream
  """

  use ThunderlineWeb, :live_view

  require Logger

  alias Thunderline.Thunderpac.Evolution
  alias Thunderline.Thunderbolt.Cerebros.LoopMonitor

  @pubsub_topic "reflex_panel"
  @tick_interval_ms 100

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to updates
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "#{@pubsub_topic}:metrics")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "#{@pubsub_topic}:voxels")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "#{@pubsub_topic}:evolution")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "bolt.thunderbit.reflex.*")

      # Start tick timer for demo mode
      Process.send_after(self(), :tick, @tick_interval_ms)
    end

    current_scope = Map.get(socket.assigns, :current_scope)

    socket =
      socket
      |> assign_new(:current_scope, fn -> current_scope end)
      |> assign(:page_title, "Reflex Panel")
      |> assign(:demo_mode, true)
      |> assign(:tick, 0)
      |> assign(:paused, false)
      # Metrics
      |> assign(:plv, 0.5)
      |> assign(:entropy, 0.5)
      |> assign(:lambda_hat, 0.273)
      |> assign(:lyapunov, 0.0)
      |> assign(:edge_of_chaos_score, 0.5)
      # Metric history (for charts)
      |> assign(:plv_history, ring_buffer(50))
      |> assign(:entropy_history, ring_buffer(50))
      |> assign(:lambda_history, ring_buffer(50))
      |> assign(:lyapunov_history, ring_buffer(50))
      # Evolution
      |> assign(:evolution_profile, :balanced)
      |> assign(:evolution_generation, 0)
      |> assign(:evolution_fitness, 0.0)
      |> assign(:fitness_history, ring_buffer(100))
      |> assign(:selected_pac, nil)
      |> assign(:pac_list, [])
      # Voxel grid
      |> assign(:grid_size, {10, 10, 10})
      |> assign(:voxel_count, 0)
      |> assign(:active_count, 0)
      |> assign(:chaotic_count, 0)
      # Events
      |> assign(:reflex_events, [])
      |> assign(:event_count, 0)
      # Controls
      |> assign(:lambda_modulation, 0.5)
      |> assign(:bias, 0.3)
      |> assign(:decay_rate, 0.99)
      |> assign(:chaos_threshold, 0.8)
      |> load_pac_list()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-base-300 via-base-200 to-base-300">
        <!-- Header -->
        <div class="navbar bg-base-300/80 backdrop-blur-sm border-b border-white/10 sticky top-0 z-50">
          <div class="flex-1">
            <div class="flex items-center gap-3">
              <div class={[
                "w-3 h-3 rounded-full",
                if(@paused, do: "bg-amber-400", else: "bg-cyan-400 animate-pulse")
              ]} />
              <h1 class="text-lg font-semibold">⚡ Reflex Panel</h1>
              <span class="badge badge-ghost badge-sm">HC-Ω-3</span>
              <span :if={@demo_mode} class="badge badge-warning badge-sm">Demo</span>
            </div>
          </div>
          <div class="flex-none gap-2">
            <button phx-click="toggle_pause" class={["btn btn-sm", if(@paused, do: "btn-warning", else: "btn-ghost")]}>
              <.icon name={if(@paused, do: "hero-play", else: "hero-pause")} class="w-4 h-4" />
              {if @paused, do: "Resume", else: "Pause"}
            </button>
            <button phx-click="reset_simulation" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-path" class="w-4 h-4" /> Reset
            </button>
            <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Dashboard
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-12 gap-4 p-4">
          <!-- Left Column: Controls & Evolution -->
          <div class="lg:col-span-3 space-y-4">
            <!-- Evolution Profile -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm flex justify-between">
                  <span><.icon name="hero-sparkles" class="w-4 h-4 inline" /> Evolution</span>
                  <span class="badge badge-primary badge-sm">Gen {@evolution_generation}</span>
                </h2>

                <div class="form-control">
                  <label class="label py-1">
                    <span class="label-text text-xs">Profile</span>
                  </label>
                  <select phx-change="change_profile" name="profile" class="select select-bordered select-sm w-full">
                    <option value="explorer" selected={@evolution_profile == :explorer}>🔭 Explorer</option>
                    <option value="exploiter" selected={@evolution_profile == :exploiter}>⚡ Exploiter</option>
                    <option value="balanced" selected={@evolution_profile == :balanced}>⚖️ Balanced</option>
                    <option value="resilient" selected={@evolution_profile == :resilient}>🛡️ Resilient</option>
                    <option value="aggressive" selected={@evolution_profile == :aggressive}>🔥 Aggressive</option>
                  </select>
                </div>

                <div class="stats stats-vertical bg-base-200 mt-2">
                  <div class="stat py-2 px-3">
                    <div class="stat-title text-xs">Fitness</div>
                    <div class="stat-value text-lg text-emerald-400">{Float.round(@evolution_fitness, 3)}</div>
                    <div class="stat-desc text-xs">
                      <.fitness_bar value={@evolution_fitness} />
                    </div>
                  </div>
                </div>

                <div class="form-control mt-2">
                  <label class="label py-1">
                    <span class="label-text text-xs">Select PAC</span>
                  </label>
                  <select phx-change="select_pac" name="pac_id" class="select select-bordered select-sm w-full">
                    <option value="">-- None --</option>
                    <%= for pac <- @pac_list do %>
                      <option value={pac.id} selected={@selected_pac == pac.id}>{pac.name}</option>
                    <% end %>
                  </select>
                </div>

                <button phx-click="evolve_step" class="btn btn-primary btn-sm mt-2 w-full" disabled={@paused}>
                  <.icon name="hero-arrow-trending-up" class="w-4 h-4" /> Evolve
                </button>
              </div>
            </div>

            <!-- CA Controls -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-adjustments-horizontal" class="w-4 h-4" /> CA Parameters
                </h2>

                <div class="space-y-3">
                  <div class="form-control">
                    <label class="label py-0">
                      <span class="label-text text-xs">λ Modulation</span>
                      <span class="label-text-alt text-xs">{Float.round(@lambda_modulation, 2)}</span>
                    </label>
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value={round(@lambda_modulation * 100)}
                      phx-change="param_changed"
                      name="lambda_modulation"
                      class="range range-xs range-primary"
                    />
                  </div>

                  <div class="form-control">
                    <label class="label py-0">
                      <span class="label-text text-xs">Bias</span>
                      <span class="label-text-alt text-xs">{Float.round(@bias, 2)}</span>
                    </label>
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value={round(@bias * 100)}
                      phx-change="param_changed"
                      name="bias"
                      class="range range-xs range-secondary"
                    />
                  </div>

                  <div class="form-control">
                    <label class="label py-0">
                      <span class="label-text text-xs">Chaos Threshold</span>
                      <span class="label-text-alt text-xs">{Float.round(@chaos_threshold, 2)}</span>
                    </label>
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value={round(@chaos_threshold * 100)}
                      phx-change="param_changed"
                      name="chaos_threshold"
                      class="range range-xs range-warning"
                    />
                  </div>
                </div>
              </div>
            </div>

            <!-- Voxel Stats -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-cube" class="w-4 h-4" /> Voxel Grid
                </h2>
                <div class="stats stats-vertical bg-base-200">
                  <div class="stat py-2 px-3">
                    <div class="stat-title text-xs">Total</div>
                    <div class="stat-value text-sm">{@voxel_count}</div>
                  </div>
                  <div class="stat py-2 px-3">
                    <div class="stat-title text-xs">Active</div>
                    <div class="stat-value text-sm text-emerald-400">{@active_count}</div>
                  </div>
                  <div class="stat py-2 px-3">
                    <div class="stat-title text-xs">Chaotic</div>
                    <div class="stat-value text-sm text-red-400">{@chaotic_count}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Center Column: Metrics & Visualization -->
          <div class="lg:col-span-6 space-y-4">
            <!-- Criticality Metrics -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm mb-2">
                  <.icon name="hero-chart-bar" class="w-4 h-4" /> Criticality Metrics
                </h2>

                <div class="grid grid-cols-4 gap-3 mb-4">
                  <.metric_card
                    label="PLV"
                    value={@plv}
                    target={0.4}
                    color="cyan"
                    tooltip="Phase-Locking Value (coherence)"
                  />
                  <.metric_card
                    label="Entropy"
                    value={@entropy}
                    target={0.5}
                    color="amber"
                    tooltip="Permutation entropy (disorder)"
                  />
                  <.metric_card
                    label="λ̂"
                    value={@lambda_hat}
                    target={0.273}
                    color="emerald"
                    tooltip="Langton's lambda (edge-of-chaos ≈ 0.273)"
                  />
                  <.metric_card
                    label="Lyapunov"
                    value={@lyapunov}
                    target={0.0}
                    color="violet"
                    tooltip="Lyapunov exponent (chaos indicator)"
                  />
                </div>

                <!-- Edge of Chaos Score -->
                <div class="bg-base-200 rounded-lg p-3">
                  <div class="flex justify-between items-center mb-2">
                    <span class="text-xs font-semibold">Edge-of-Chaos Score</span>
                    <span class={[
                      "badge badge-sm",
                      edge_of_chaos_badge(@edge_of_chaos_score)
                    ]}>
                      {edge_of_chaos_label(@edge_of_chaos_score)}
                    </span>
                  </div>
                  <progress
                    class={["progress w-full h-3", edge_of_chaos_progress(@edge_of_chaos_score)]}
                    value={round(@edge_of_chaos_score * 100)}
                    max="100"
                  />
                  <div class="flex justify-between text-xs mt-1 opacity-60">
                    <span>Ordered</span>
                    <span>Critical</span>
                    <span>Chaotic</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Charts Container -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-presentation-chart-line" class="w-4 h-4" /> Live Metrics
                </h2>

                <div
                  id="metrics-chart-container"
                  phx-hook="ReflexMetricsChart"
                  phx-update="ignore"
                  data-plv={Jason.encode!(@plv_history)}
                  data-entropy={Jason.encode!(@entropy_history)}
                  data-lambda={Jason.encode!(@lambda_history)}
                  data-lyapunov={Jason.encode!(@lyapunov_history)}
                  class="h-64"
                >
                  <canvas id="metrics-chart" class="w-full h-full"></canvas>
                </div>
              </div>
            </div>

            <!-- Voxel Visualization -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-cube-transparent" class="w-4 h-4" /> Voxel Automata
                </h2>

                <div
                  id="voxel-grid-container"
                  phx-hook="VoxelGrid"
                  phx-update="ignore"
                  data-size={Jason.encode!(@grid_size |> Tuple.to_list())}
                  class="h-80 bg-base-200 rounded-lg overflow-hidden"
                >
                  <!-- Three.js canvas will be injected here -->
                </div>
              </div>
            </div>
          </div>

          <!-- Right Column: Events & Fitness -->
          <div class="lg:col-span-3 space-y-4">
            <!-- Fitness History -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-arrow-trending-up" class="w-4 h-4" /> Fitness History
                </h2>

                <div
                  id="fitness-chart-container"
                  phx-hook="FitnessChart"
                  phx-update="ignore"
                  data-history={Jason.encode!(@fitness_history)}
                  class="h-40"
                >
                  <canvas id="fitness-chart" class="w-full h-full"></canvas>
                </div>

                <div class="divider my-2" />

                <div class="text-xs space-y-1 opacity-70">
                  <div class="flex justify-between">
                    <span>Best Fitness</span>
                    <span class="font-mono text-emerald-400">
                      {Float.round(Enum.max(@fitness_history ++ [0.0]), 3)}
                    </span>
                  </div>
                  <div class="flex justify-between">
                    <span>Avg Fitness</span>
                    <span class="font-mono">
                      {Float.round(safe_average(@fitness_history), 3)}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Reflex Events Stream -->
            <div class="card bg-base-300 shadow-xl max-h-96 overflow-hidden">
              <div class="card-body p-4">
                <h2 class="card-title text-sm flex justify-between">
                  <span><.icon name="hero-bolt" class="w-4 h-4" /> Reflex Events</span>
                  <span class="badge badge-ghost badge-sm">{@event_count}</span>
                </h2>

                <div class="overflow-y-auto max-h-64 space-y-2" id="event-stream">
                  <%= if @reflex_events == [] do %>
                    <div class="text-center py-8 opacity-50">
                      <.icon name="hero-signal" class="w-8 h-8 mx-auto mb-2" />
                      <p class="text-xs">Waiting for reflex events...</p>
                    </div>
                  <% else %>
                    <%= for event <- Enum.take(@reflex_events, 20) do %>
                      <.event_card event={event} />
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>

            <!-- Quick Actions -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-command-line" class="w-4 h-4" /> Actions
                </h2>

                <div class="grid grid-cols-2 gap-2">
                  <button phx-click="trigger_chaos" class="btn btn-error btn-sm">
                    <.icon name="hero-fire" class="w-4 h-4" /> Chaos
                  </button>
                  <button phx-click="trigger_stability" class="btn btn-success btn-sm">
                    <.icon name="hero-shield-check" class="w-4 h-4" /> Stabilize
                  </button>
                  <button phx-click="spawn_pac" class="btn btn-info btn-sm">
                    <.icon name="hero-user-plus" class="w-4 h-4" /> Spawn PAC
                  </button>
                  <button phx-click="clear_events" class="btn btn-ghost btn-sm">
                    <.icon name="hero-trash" class="w-4 h-4" /> Clear
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ═══════════════════════════════════════════════════════════════
  # Function Components
  # ═══════════════════════════════════════════════════════════════

  attr :label, :string, required: true
  attr :value, :float, required: true
  attr :target, :float, required: true
  attr :color, :string, default: "cyan"
  attr :tooltip, :string, default: ""

  defp metric_card(assigns) do
    distance = abs(assigns.value - assigns.target)
    status = if distance < 0.1, do: "optimal", else: if(distance < 0.3, do: "good", else: "off")

    assigns = assign(assigns, distance: distance, status: status)

    ~H"""
    <div class="bg-base-200 rounded-lg p-3 relative group" title={@tooltip}>
      <div class="text-xs opacity-60 mb-1">{@label}</div>
      <div class={["text-xl font-bold", "text-#{@color}-400"]}>{Float.round(@value, 3)}</div>
      <div class="text-xs opacity-40">target: {@target}</div>
      <div class={[
        "absolute top-2 right-2 w-2 h-2 rounded-full",
        status_color(@status)
      ]} />
    </div>
    """
  end

  attr :value, :float, required: true

  defp fitness_bar(assigns) do
    ~H"""
    <div class="w-full bg-base-100 rounded-full h-2">
      <div
        class="bg-gradient-to-r from-red-500 via-amber-500 to-emerald-500 h-2 rounded-full transition-all duration-300"
        style={"width: #{round(@value * 100)}%"}
      />
    </div>
    """
  end

  attr :event, :map, required: true

  defp event_card(assigns) do
    ~H"""
    <div class={[
      "p-2 rounded-lg text-xs border-l-2",
      event_color(@event.type)
    ]}>
      <div class="flex justify-between items-start">
        <span class="font-semibold">{event_icon(@event.type)} {@event.type}</span>
        <span class="opacity-50">{format_time(@event.timestamp)}</span>
      </div>
      <div class="mt-1 opacity-70">
        <span class="font-mono">{short_id(@event.bit_id)}</span>
        <span> — {@event.trigger}</span>
      </div>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Handlers
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  def handle_event("reset_simulation", _params, socket) do
    socket =
      socket
      |> assign(:tick, 0)
      |> assign(:plv, 0.5)
      |> assign(:entropy, 0.5)
      |> assign(:lambda_hat, 0.273)
      |> assign(:lyapunov, 0.0)
      |> assign(:edge_of_chaos_score, 0.5)
      |> assign(:plv_history, ring_buffer(50))
      |> assign(:entropy_history, ring_buffer(50))
      |> assign(:lambda_history, ring_buffer(50))
      |> assign(:lyapunov_history, ring_buffer(50))
      |> assign(:evolution_generation, 0)
      |> assign(:evolution_fitness, 0.0)
      |> assign(:fitness_history, ring_buffer(100))
      |> assign(:reflex_events, [])
      |> assign(:event_count, 0)
      |> push_event("reset_charts", %{})
      |> push_event("reset_voxels", %{})

    {:noreply, socket}
  end

  def handle_event("change_profile", %{"profile" => profile_str}, socket) do
    profile = String.to_existing_atom(profile_str)
    {:noreply, assign(socket, :evolution_profile, profile)}
  end

  def handle_event("select_pac", %{"pac_id" => ""}, socket) do
    {:noreply, assign(socket, :selected_pac, nil)}
  end

  def handle_event("select_pac", %{"pac_id" => pac_id}, socket) do
    {:noreply, assign(socket, :selected_pac, pac_id)}
  end

  def handle_event("param_changed", %{"lambda_modulation" => val}, socket) do
    {:noreply, assign(socket, :lambda_modulation, String.to_integer(val) / 100)}
  end

  def handle_event("param_changed", %{"bias" => val}, socket) do
    {:noreply, assign(socket, :bias, String.to_integer(val) / 100)}
  end

  def handle_event("param_changed", %{"chaos_threshold" => val}, socket) do
    {:noreply, assign(socket, :chaos_threshold, String.to_integer(val) / 100)}
  end

  def handle_event("evolve_step", _params, socket) do
    # Manual evolution step
    socket = do_evolution_step(socket)
    {:noreply, socket}
  end

  def handle_event("trigger_chaos", _params, socket) do
    event = %{
      type: :chaos,
      bit_id: "manual_trigger",
      trigger: :user_initiated,
      timestamp: DateTime.utc_now(),
      data: %{lambda_hat: 0.95}
    }

    socket =
      socket
      |> assign(:lambda_hat, 0.9)
      |> assign(:entropy, 0.85)
      |> assign(:edge_of_chaos_score, 0.9)
      |> add_reflex_event(event)
      |> push_event("chaos_pulse", %{intensity: 0.9})

    {:noreply, socket}
  end

  def handle_event("trigger_stability", _params, socket) do
    event = %{
      type: :stability,
      bit_id: "manual_trigger",
      trigger: :user_initiated,
      timestamp: DateTime.utc_now(),
      data: %{sigma_flow: 0.8}
    }

    socket =
      socket
      |> assign(:lambda_hat, 0.273)
      |> assign(:entropy, 0.3)
      |> assign(:plv, 0.7)
      |> assign(:edge_of_chaos_score, 0.5)
      |> add_reflex_event(event)
      |> push_event("stability_wave", %{})

    {:noreply, socket}
  end

  def handle_event("spawn_pac", _params, socket) do
    pac_name = "PAC_#{System.unique_integer([:positive])}"

    socket =
      socket
      |> put_flash(:info, "Spawned #{pac_name}")
      |> load_pac_list()

    {:noreply, socket}
  end

  def handle_event("clear_events", _params, socket) do
    {:noreply, assign(socket, reflex_events: [], event_count: 0)}
  end

  # ═══════════════════════════════════════════════════════════════
  # Info Handlers (PubSub)
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def handle_info(:tick, socket) do
    socket =
      if socket.assigns.paused do
        socket
      else
        tick = socket.assigns.tick + 1

        # Demo mode: simulate metrics
        if socket.assigns.demo_mode do
          simulate_tick(socket, tick)
        else
          socket
        end
        |> assign(:tick, tick)
      end

    Process.send_after(self(), :tick, @tick_interval_ms)
    {:noreply, socket}
  end

  def handle_info({:metrics_update, metrics}, socket) do
    socket =
      socket
      |> assign(:plv, metrics.plv)
      |> assign(:entropy, metrics.entropy)
      |> assign(:lambda_hat, metrics.lambda_hat)
      |> assign(:lyapunov, metrics.lyapunov)
      |> assign(:edge_of_chaos_score, metrics.edge_of_chaos_score)
      |> update_metric_history(:plv, metrics.plv)
      |> update_metric_history(:entropy, metrics.entropy)
      |> update_metric_history(:lambda_hat, metrics.lambda_hat)
      |> update_metric_history(:lyapunov, metrics.lyapunov)
      |> push_event("metrics_updated", metrics)

    {:noreply, socket}
  end

  def handle_info({:reflex_event, event}, socket) do
    {:noreply, add_reflex_event(socket, event)}
  end

  def handle_info({:voxel_update, voxels}, socket) do
    active = Enum.count(voxels, &(&1.state == :active))
    chaotic = Enum.count(voxels, &(&1.state == :chaotic))

    socket =
      socket
      |> assign(:voxel_count, length(voxels))
      |> assign(:active_count, active)
      |> assign(:chaotic_count, chaotic)
      |> push_event("voxels_updated", %{voxels: voxels})

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ═══════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════

  defp load_pac_list(socket) do
    # In real mode, load from Thunderpac
    # For demo, use empty list
    assign(socket, :pac_list, [])
  end

  defp simulate_tick(socket, tick) do
    # Simulate oscillating metrics with noise
    base_plv = 0.4 + 0.1 * :math.sin(tick * 0.05)
    base_entropy = 0.5 + 0.15 * :math.cos(tick * 0.03)
    base_lambda = 0.273 + 0.05 * :math.sin(tick * 0.02)
    base_lyapunov = 0.05 * :math.sin(tick * 0.04)

    noise = fn -> (:rand.uniform() - 0.5) * 0.05 end

    plv = clamp(base_plv + noise.())
    entropy = clamp(base_entropy + noise.())
    lambda_hat = clamp(base_lambda + noise.())
    lyapunov = base_lyapunov + noise.() * 0.1

    edge_score = compute_edge_of_chaos_score(plv, entropy, lambda_hat, lyapunov)

    # Voxel stats
    {w, h, d} = socket.assigns.grid_size
    total = w * h * d
    active_ratio = 0.3 + 0.1 * :math.sin(tick * 0.02)
    chaotic_ratio = max(0, (lambda_hat - 0.5) * 0.4)

    # Random reflex events
    socket =
      if :rand.uniform() < 0.02 do
        event_type = Enum.random([:stability, :chaos, :trust, :decay])

        event = %{
          type: event_type,
          bit_id: "bit_#{:rand.uniform(999)}",
          trigger: Enum.random([:low_stability, :chaos_spike, :trust_boost, :idle_decay]),
          timestamp: DateTime.utc_now(),
          data: %{}
        }

        add_reflex_event(socket, event)
      else
        socket
      end

    socket
    |> assign(:plv, plv)
    |> assign(:entropy, entropy)
    |> assign(:lambda_hat, lambda_hat)
    |> assign(:lyapunov, lyapunov)
    |> assign(:edge_of_chaos_score, edge_score)
    |> assign(:voxel_count, total)
    |> assign(:active_count, round(total * active_ratio))
    |> assign(:chaotic_count, round(total * chaotic_ratio))
    |> update_metric_history(:plv, plv)
    |> update_metric_history(:entropy, entropy)
    |> update_metric_history(:lambda_hat, lambda_hat)
    |> update_metric_history(:lyapunov, lyapunov)
    |> push_event("metrics_tick", %{
      plv: plv,
      entropy: entropy,
      lambda_hat: lambda_hat,
      lyapunov: lyapunov,
      edge_score: edge_score
    })
  end

  defp do_evolution_step(socket) do
    gen = socket.assigns.evolution_generation + 1
    profile = socket.assigns.evolution_profile

    # Simulate fitness based on current metrics
    plv = socket.assigns.plv
    entropy = socket.assigns.entropy
    lambda = socket.assigns.lambda_hat

    fitness =
      case profile do
        :explorer -> 0.4 * (1.0 - entropy) + 0.3 * lambda + 0.3 * :rand.uniform()
        :exploiter -> 0.5 * plv + 0.3 * (1.0 - entropy) + 0.2 * :rand.uniform()
        :balanced -> 0.25 * plv + 0.25 * (1.0 - abs(lambda - 0.273) * 3) + 0.25 * (1.0 - entropy) + 0.25 * :rand.uniform()
        :resilient -> 0.5 * (1.0 - entropy) + 0.3 * plv + 0.2 * :rand.uniform()
        :aggressive -> 0.4 * lambda + 0.3 * (entropy) + 0.3 * :rand.uniform()
        _ -> 0.5
      end

    fitness = clamp(fitness)

    socket
    |> assign(:evolution_generation, gen)
    |> assign(:evolution_fitness, fitness)
    |> update(:fitness_history, fn history -> ring_push(history, fitness) end)
    |> push_event("fitness_updated", %{generation: gen, fitness: fitness})
  end

  defp add_reflex_event(socket, event) do
    events = [event | socket.assigns.reflex_events] |> Enum.take(100)
    count = socket.assigns.event_count + 1

    socket
    |> assign(:reflex_events, events)
    |> assign(:event_count, count)
  end

  defp update_metric_history(socket, key, value) do
    history_key = :"#{key}_history"
    update(socket, history_key, fn history -> ring_push(history, value) end)
  end

  defp compute_edge_of_chaos_score(plv, entropy, lambda_hat, lyapunov) do
    # Score is highest when λ̂ ≈ 0.273, PLV moderate, entropy moderate, Lyapunov ≈ 0
    lambda_score = 1.0 - abs(lambda_hat - 0.273) * 3
    plv_score = 1.0 - abs(plv - 0.4) * 2
    entropy_score = 1.0 - abs(entropy - 0.5) * 2
    lyapunov_score = 1.0 - min(1.0, abs(lyapunov) * 5)

    score = (lambda_score * 0.4 + plv_score * 0.2 + entropy_score * 0.2 + lyapunov_score * 0.2)
    clamp(score)
  end

  defp ring_buffer(size), do: List.duplicate(0.0, size)

  defp ring_push(buffer, value) do
    [value | Enum.take(buffer, length(buffer) - 1)]
  end

  defp clamp(v), do: max(0.0, min(1.0, v))

  defp safe_average([]), do: 0.0
  defp safe_average(list), do: Enum.sum(list) / length(list)

  defp short_id(nil), do: "n/a"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(id), do: to_string(id)

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "--:--:--"

  defp status_color("optimal"), do: "bg-emerald-400"
  defp status_color("good"), do: "bg-amber-400"
  defp status_color(_), do: "bg-red-400"

  defp event_color(:stability), do: "border-amber-400 bg-amber-400/10"
  defp event_color(:chaos), do: "border-red-400 bg-red-400/10"
  defp event_color(:trust), do: "border-emerald-400 bg-emerald-400/10"
  defp event_color(:decay), do: "border-gray-400 bg-gray-400/10"
  defp event_color(_), do: "border-cyan-400 bg-cyan-400/10"

  defp event_icon(:stability), do: "⚠️"
  defp event_icon(:chaos), do: "🔥"
  defp event_icon(:trust), do: "✅"
  defp event_icon(:decay), do: "⏳"
  defp event_icon(_), do: "⚡"

  defp edge_of_chaos_badge(score) when score > 0.7, do: "badge-error"
  defp edge_of_chaos_badge(score) when score > 0.4, do: "badge-success"
  defp edge_of_chaos_badge(_), do: "badge-info"

  defp edge_of_chaos_label(score) when score > 0.7, do: "Chaotic"
  defp edge_of_chaos_label(score) when score > 0.4, do: "Critical"
  defp edge_of_chaos_label(_), do: "Ordered"

  defp edge_of_chaos_progress(score) when score > 0.7, do: "progress-error"
  defp edge_of_chaos_progress(score) when score > 0.4, do: "progress-success"
  defp edge_of_chaos_progress(_), do: "progress-info"
end
