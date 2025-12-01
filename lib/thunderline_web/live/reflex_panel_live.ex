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
  @slow_motion_interval_ms 500

  # Heatmap modes
  @heatmap_modes [:none, :coherence, :plv, :entropy, :lambda]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to updates
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "#{@pubsub_topic}:metrics")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "#{@pubsub_topic}:voxels")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "#{@pubsub_topic}:evolution")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "reflex:triggered")
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
      # HC-Ω-7 Phase 2: New controls
      |> assign(:slow_motion, false)
      |> assign(:heatmap_mode, :none)
      |> assign(:show_bit_inspector, false)
      |> assign(:inspected_bit, nil)
      |> assign(:stimulus_type, :pulse)
      |> assign(:stimulus_coord, {5, 5, 5})
      |> assign(:bit_logs, [])
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
      |> assign(:voxel_data, %{})
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
              <span class="badge badge-ghost badge-sm">HC-Ω-7</span>
              <span :if={@demo_mode} class="badge badge-warning badge-sm">Demo</span>
              <span :if={@slow_motion} class="badge badge-info badge-sm animate-pulse">Slow-Mo</span>
            </div>
          </div>
          <div class="flex-none gap-2">
            <!-- Playback Controls -->
            <div class="btn-group">
              <button
                phx-click="toggle_pause"
                class={["btn btn-sm", if(@paused, do: "btn-warning", else: "btn-ghost")]}
              >
                <.icon name={if(@paused, do: "hero-play", else: "hero-pause")} class="w-4 h-4" />
              </button>
              <button
                phx-click="toggle_slow_motion"
                class={["btn btn-sm", if(@slow_motion, do: "btn-info", else: "btn-ghost")]}
              >
                <.icon name="hero-backward" class="w-4 h-4" />
              </button>
              <button phx-click="step_tick" class="btn btn-ghost btn-sm" disabled={!@paused}>
                <.icon name="hero-forward" class="w-4 h-4" />
              </button>
            </div>
            
    <!-- Heatmap Toggle -->
            <div class="dropdown dropdown-end">
              <label
                tabindex="0"
                class={[
                  "btn btn-sm",
                  if(@heatmap_mode != :none, do: "btn-secondary", else: "btn-ghost")
                ]}
              >
                <.icon name="hero-fire" class="w-4 h-4" />
                <span class="hidden sm:inline">Heatmap</span>
              </label>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow bg-base-300 rounded-box w-40"
              >
                <li>
                  <a
                    phx-click="set_heatmap"
                    phx-value-mode="none"
                    class={if(@heatmap_mode == :none, do: "active", else: "")}
                  >
                    Off
                  </a>
                </li>
                <li>
                  <a
                    phx-click="set_heatmap"
                    phx-value-mode="coherence"
                    class={if(@heatmap_mode == :coherence, do: "active", else: "")}
                  >
                    Coherence
                  </a>
                </li>
                <li>
                  <a
                    phx-click="set_heatmap"
                    phx-value-mode="plv"
                    class={if(@heatmap_mode == :plv, do: "active", else: "")}
                  >
                    PLV
                  </a>
                </li>
                <li>
                  <a
                    phx-click="set_heatmap"
                    phx-value-mode="entropy"
                    class={if(@heatmap_mode == :entropy, do: "active", else: "")}
                  >
                    Entropy
                  </a>
                </li>
                <li>
                  <a
                    phx-click="set_heatmap"
                    phx-value-mode="lambda"
                    class={if(@heatmap_mode == :lambda, do: "active", else: "")}
                  >
                    Lambda
                  </a>
                </li>
              </ul>
            </div>

            <button phx-click="reset_simulation" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-path" class="w-4 h-4" />
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
                  <select
                    phx-change="change_profile"
                    name="profile"
                    class="select select-bordered select-sm w-full"
                  >
                    <option value="explorer" selected={@evolution_profile == :explorer}>
                      🔭 Explorer
                    </option>
                    <option value="exploiter" selected={@evolution_profile == :exploiter}>
                      ⚡ Exploiter
                    </option>
                    <option value="balanced" selected={@evolution_profile == :balanced}>
                      ⚖️ Balanced
                    </option>
                    <option value="resilient" selected={@evolution_profile == :resilient}>
                      🛡️ Resilient
                    </option>
                    <option value="aggressive" selected={@evolution_profile == :aggressive}>
                      🔥 Aggressive
                    </option>
                  </select>
                </div>

                <div class="stats stats-vertical bg-base-200 mt-2">
                  <div class="stat py-2 px-3">
                    <div class="stat-title text-xs">Fitness</div>
                    <div class="stat-value text-lg text-emerald-400">
                      {Float.round(@evolution_fitness, 3)}
                    </div>
                    <div class="stat-desc text-xs">
                      <.fitness_bar value={@evolution_fitness} />
                    </div>
                  </div>
                </div>

                <div class="form-control mt-2">
                  <label class="label py-1">
                    <span class="label-text text-xs">Select PAC</span>
                  </label>
                  <select
                    phx-change="select_pac"
                    name="pac_id"
                    class="select select-bordered select-sm w-full"
                  >
                    <option value="">-- None --</option>
                    <%= for pac <- @pac_list do %>
                      <option value={pac.id} selected={@selected_pac == pac.id}>{pac.name}</option>
                    <% end %>
                  </select>
                </div>

                <button
                  phx-click="evolve_step"
                  class="btn btn-primary btn-sm mt-2 w-full"
                  disabled={@paused}
                >
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
                <div class="flex justify-between items-center">
                  <h2 class="card-title text-sm">
                    <.icon name="hero-cube-transparent" class="w-4 h-4" /> Voxel Automata
                  </h2>
                  <span :if={@heatmap_mode != :none} class="badge badge-secondary badge-sm">
                    Heatmap: {@heatmap_mode}
                  </span>
                </div>

                <div
                  id="voxel-grid-container"
                  phx-hook="VoxelGrid"
                  phx-update="ignore"
                  phx-click="voxel_clicked"
                  data-size={Jason.encode!(@grid_size |> Tuple.to_list())}
                  data-heatmap-mode={@heatmap_mode}
                  class="h-80 bg-base-200 rounded-lg overflow-hidden cursor-crosshair"
                >
                  <!-- Three.js canvas will be injected here -->
                  <div class="flex items-center justify-center h-full text-xs opacity-50">
                    Click a voxel to inspect
                  </div>
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
                  <button phx-click="open_stimulus_modal" class="btn btn-warning btn-sm col-span-2">
                    <.icon name="hero-bolt" class="w-4 h-4" /> Inject Stimulus
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
        
    <!-- HC-Ω-7 Phase 2: Bit Inspector Modal -->
        <.bit_inspector_modal
          :if={@show_bit_inspector}
          bit={@inspected_bit}
          logs={@bit_logs}
          voxel_data={@voxel_data}
        />
        
    <!-- HC-Ω-7 Phase 2: Stimulus Injection Modal -->
        <.stimulus_modal
          :if={assigns[:show_stimulus_modal]}
          stimulus_type={@stimulus_type}
          stimulus_coord={@stimulus_coord}
          grid_size={@grid_size}
        />
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
        <span class="mx-1">|</span>
        <span>{@event.trigger}</span>
      </div>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════
  # HC-Ω-7 Phase 2: Modal Components
  # ═══════════════════════════════════════════════════════════════

  attr :bit, :map, default: nil
  attr :logs, :list, default: []
  attr :voxel_data, :map, default: %{}

  defp bit_inspector_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl bg-base-300">
        <button
          phx-click="close_bit_inspector"
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
        >
          ✕
        </button>

        <h3 class="font-bold text-lg mb-4">
          <.icon name="hero-magnifying-glass" class="w-5 h-5 inline" /> Bit Inspector
        </h3>

        <%= if @bit do %>
          <div class="grid grid-cols-2 gap-4">
            <!-- Bit Info -->
            <div class="space-y-3">
              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60">Bit ID</div>
                <div class="font-mono text-sm">{@bit.id || "N/A"}</div>
              </div>

              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60">Coordinate</div>
                <div class="font-mono text-sm">{inspect(@bit.coord || "N/A")}</div>
              </div>

              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60">State</div>
                <div class={["badge", bit_state_badge(@bit.state)]}>
                  {@bit.state || :unknown}
                </div>
              </div>

              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60">σ Flow</div>
                <div class="font-mono text-lg">{Float.round(@bit.sigma_flow || 0.0, 4)}</div>
              </div>

              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60">φ Phase</div>
                <div class="font-mono text-lg">{Float.round(@bit.phi_phase || 0.0, 4)}</div>
              </div>

              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60">λ Sensitivity</div>
                <div class="font-mono text-lg">{Float.round(@bit.lambda_sensitivity || 0.0, 4)}</div>
              </div>
            </div>
            
    <!-- Neighbors & Logs -->
            <div class="space-y-3">
              <div class="bg-base-200 p-3 rounded-lg">
                <div class="text-xs opacity-60 mb-2">Nearest Neighbors</div>
                <div class="flex flex-wrap gap-1">
                  <%= for neighbor <- (@bit.neighbors || []) |> Enum.take(8) do %>
                    <span class="badge badge-ghost badge-sm font-mono">{inspect(neighbor)}</span>
                  <% end %>
                  <%= if (@bit.neighbors || []) == [] do %>
                    <span class="text-xs opacity-50">No neighbors</span>
                  <% end %>
                </div>
              </div>

              <div class="bg-base-200 p-3 rounded-lg max-h-48 overflow-y-auto">
                <div class="text-xs opacity-60 mb-2">Reflex Trigger Log</div>
                <%= if @logs == [] do %>
                  <div class="text-xs opacity-50">No triggers recorded</div>
                <% else %>
                  <div class="space-y-1">
                    <%= for log <- Enum.take(@logs, 10) do %>
                      <div class="text-xs font-mono p-1 bg-base-100 rounded">
                        <span class={trigger_color(log.trigger)}>{log.trigger}</span>
                        <span class="opacity-50 ml-2">{format_time(log.timestamp)}</span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <div class="modal-action">
            <button
              phx-click="inject_at_bit"
              phx-value-coord={inspect(@bit.coord)}
              class="btn btn-warning btn-sm"
            >
              <.icon name="hero-bolt" class="w-4 h-4" /> Inject Here
            </button>
            <button phx-click="close_bit_inspector" class="btn btn-ghost btn-sm">Close</button>
          </div>
        <% else %>
          <div class="text-center py-8 opacity-50">
            <.icon name="hero-cube" class="w-12 h-12 mx-auto mb-2" />
            <p>Click a voxel in the grid to inspect</p>
          </div>
        <% end %>
      </div>
      <div class="modal-backdrop" phx-click="close_bit_inspector"></div>
    </div>
    """
  end

  attr :stimulus_type, :atom, default: :pulse
  attr :stimulus_coord, :any, default: {5, 5, 5}
  attr :grid_size, :any, default: {10, 10, 10}

  defp stimulus_modal(assigns) do
    {max_x, max_y, max_z} = assigns.grid_size
    {x, y, z} = assigns.stimulus_coord
    assigns = assign(assigns, max_x: max_x, max_y: max_y, max_z: max_z, x: x, y: y, z: z)

    ~H"""
    <div class="modal modal-open">
      <div class="modal-box bg-base-300">
        <button
          phx-click="close_stimulus_modal"
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
        >
          ✕
        </button>

        <h3 class="font-bold text-lg mb-4">
          <.icon name="hero-bolt" class="w-5 h-5 inline" /> Inject Stimulus
        </h3>

        <form phx-submit="inject_stimulus" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Stimulus Type</span>
            </label>
            <select name="type" class="select select-bordered w-full">
              <option value="pulse" selected={@stimulus_type == :pulse}>
                ⚡ Pulse (single activation)
              </option>
              <option value="wave" selected={@stimulus_type == :wave}>🌊 Wave (radial spread)</option>
              <option value="chaos" selected={@stimulus_type == :chaos}>🔥 Chaos (destabilize)</option>
              <option value="freeze" selected={@stimulus_type == :freeze}>
                ❄️ Freeze (halt activity)
              </option>
              <option value="reset" selected={@stimulus_type == :reset}>
                🔄 Reset (restore defaults)
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Target Coordinate</span>
            </label>
            <div class="grid grid-cols-3 gap-2">
              <div>
                <label class="label py-0"><span class="label-text-alt">X</span></label>
                <input
                  type="number"
                  name="x"
                  value={@x}
                  min="0"
                  max={@max_x - 1}
                  class="input input-bordered w-full"
                />
              </div>
              <div>
                <label class="label py-0"><span class="label-text-alt">Y</span></label>
                <input
                  type="number"
                  name="y"
                  value={@y}
                  min="0"
                  max={@max_y - 1}
                  class="input input-bordered w-full"
                />
              </div>
              <div>
                <label class="label py-0"><span class="label-text-alt">Z</span></label>
                <input
                  type="number"
                  name="z"
                  value={@z}
                  min="0"
                  max={@max_z - 1}
                  class="input input-bordered w-full"
                />
              </div>
            </div>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Intensity</span>
            </label>
            <input
              type="range"
              name="intensity"
              min="0"
              max="100"
              value="50"
              class="range range-warning"
            />
          </div>

          <div class="modal-action">
            <button type="submit" class="btn btn-warning">
              <.icon name="hero-bolt" class="w-4 h-4" /> Inject
            </button>
            <button type="button" phx-click="close_stimulus_modal" class="btn btn-ghost">
              Cancel
            </button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="close_stimulus_modal"></div>
    </div>
    """
  end

  defp bit_state_badge(:active), do: "badge-success"
  defp bit_state_badge(:chaotic), do: "badge-error"
  defp bit_state_badge(:dormant), do: "badge-warning"
  defp bit_state_badge(:stable), do: "badge-info"
  defp bit_state_badge(_), do: "badge-ghost"

  defp trigger_color(:chaos_spike), do: "text-red-400"
  defp trigger_color(:low_stability), do: "text-amber-400"
  defp trigger_color(:trust_boost), do: "text-emerald-400"
  defp trigger_color(:idle_decay), do: "text-gray-400"
  defp trigger_color(_), do: "text-cyan-400"

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

  # ───────────────────────────────────────────────────────────────
  # Phase 2: Heatmap Mode, Slow-Motion, Bit Inspector, Stimulus
  # ───────────────────────────────────────────────────────────────

  def handle_event("toggle_slow_motion", _params, socket) do
    new_slow_motion = not socket.assigns.slow_motion

    # Adjust tick interval: slow-motion = 500ms, normal = 100ms
    tick_interval = if new_slow_motion, do: 500, else: 100

    socket =
      socket
      |> assign(:slow_motion, new_slow_motion)
      |> assign(:tick_interval, tick_interval)

    {:noreply, socket}
  end

  def handle_event("change_heatmap_mode", %{"mode" => mode}, socket) do
    mode_atom =
      case mode do
        "coherence" -> :coherence
        "plv" -> :plv
        "entropy" -> :entropy
        "lambda" -> :lambda
        "state" -> :state
        _ -> :coherence
      end

    {:noreply, assign(socket, :heatmap_mode, mode_atom)}
  end

  def handle_event("open_bit_inspector", _params, socket) do
    # Load recent bit logs for the inspector
    bit_logs = fetch_recent_bit_logs(socket, 20)
    {:noreply, assign(socket, show_bit_inspector: true, bit_logs: bit_logs)}
  end

  def handle_event("close_bit_inspector", _params, socket) do
    {:noreply, assign(socket, show_bit_inspector: false, inspected_bit: nil, bit_logs: [])}
  end

  def handle_event("inspect_bit", %{"bit_id" => bit_id}, socket) do
    # Fetch detailed info for a specific bit
    bit_info = fetch_bit_details(socket, bit_id)
    {:noreply, assign(socket, inspected_bit: bit_info)}
  end

  def handle_event("open_stimulus_modal", _params, socket) do
    {:noreply, assign(socket, show_stimulus_modal: true, stimulus_coord: nil)}
  end

  def handle_event("close_stimulus_modal", _params, socket) do
    {:noreply,
     assign(socket, show_stimulus_modal: false, stimulus_type: :chaos, stimulus_coord: nil)}
  end

  def handle_event("inject_stimulus", params, socket) do
    type = String.to_existing_atom(params["type"] || "chaos")
    x = String.to_integer(params["x"] || "0")
    y = String.to_integer(params["y"] || "0")
    z = String.to_integer(params["z"] || "0")
    intensity = String.to_float(params["intensity"] || "0.5")

    coord = {x, y, z}

    # Emit stimulus event through EventBus
    stimulus_event = %{
      type: :stimulus_injected,
      bit_id: "stimulus_#{x}_#{y}_#{z}",
      trigger: type,
      timestamp: DateTime.utc_now(),
      data: %{
        coord: coord,
        stimulus_type: type,
        intensity: intensity,
        injected_by: :user
      }
    }

    # Apply stimulus effect based on type
    socket =
      case type do
        :chaos ->
          socket
          |> assign(:lambda_hat, min(1.0, socket.assigns.lambda_hat + intensity * 0.2))
          |> assign(:entropy, min(1.0, socket.assigns.entropy + intensity * 0.3))
          |> push_event("chaos_pulse", %{intensity: intensity, coord: coord})

        :stability ->
          socket
          |> assign(:lambda_hat, max(0.0, socket.assigns.lambda_hat - intensity * 0.15))
          |> assign(:entropy, max(0.0, socket.assigns.entropy - intensity * 0.2))
          |> assign(:plv, min(1.0, socket.assigns.plv + intensity * 0.1))
          |> push_event("stability_wave", %{intensity: intensity, coord: coord})

        :freeze ->
          # Freeze temporarily reduces all dynamics
          socket
          |> assign(:lambda_hat, 0.0)
          |> assign(:entropy, 0.1)
          |> push_event("freeze_effect", %{coord: coord, duration: intensity * 10})

        :activate ->
          # Activate boosts activity
          socket
          |> assign(:lambda_hat, 0.5 + intensity * 0.3)
          |> assign(:entropy, 0.5)
          |> assign(
            :edge_of_chaos_score,
            min(1.0, socket.assigns.edge_of_chaos_score + intensity * 0.2)
          )
          |> push_event("activation_burst", %{coord: coord, intensity: intensity})

        _ ->
          socket
      end

    socket =
      socket
      |> add_reflex_event(stimulus_event)
      |> assign(:show_stimulus_modal, false)
      |> put_flash(:info, "Stimulus #{type} injected at #{inspect(coord)}")

    {:noreply, socket}
  end

  def handle_event("select_voxel", %{"coord" => coord_str}, socket) do
    # Parse coord from JS hook (e.g., "1,2,3")
    coord =
      case String.split(coord_str, ",") do
        [x, y, z] ->
          {String.to_integer(x), String.to_integer(y), String.to_integer(z)}

        _ ->
          {0, 0, 0}
      end

    {:noreply, assign(socket, stimulus_coord: coord, show_stimulus_modal: true)}
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
        :explorer ->
          0.4 * (1.0 - entropy) + 0.3 * lambda + 0.3 * :rand.uniform()

        :exploiter ->
          0.5 * plv + 0.3 * (1.0 - entropy) + 0.2 * :rand.uniform()

        :balanced ->
          0.25 * plv + 0.25 * (1.0 - abs(lambda - 0.273) * 3) + 0.25 * (1.0 - entropy) +
            0.25 * :rand.uniform()

        :resilient ->
          0.5 * (1.0 - entropy) + 0.3 * plv + 0.2 * :rand.uniform()

        :aggressive ->
          0.4 * lambda + 0.3 * entropy + 0.3 * :rand.uniform()

        _ ->
          0.5
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

    score = lambda_score * 0.4 + plv_score * 0.2 + entropy_score * 0.2 + lyapunov_score * 0.2
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

  # ───────────────────────────────────────────────────────────────
  # Phase 2: Bit Inspector Helpers
  # ───────────────────────────────────────────────────────────────

  defp fetch_recent_bit_logs(socket, limit) do
    # In demo mode, generate sample bit logs
    # In production, this would query from Thunderflow events
    if socket.assigns.demo_mode do
      for i <- 1..min(limit, 10) do
        %{
          bit_id: "bit_#{:rand.uniform(999)}",
          timestamp: DateTime.add(DateTime.utc_now(), -i * 60, :second),
          state: Enum.random([:active, :dormant, :chaotic, :stable]),
          lambda: 0.2 + :rand.uniform() * 0.3,
          entropy: :rand.uniform(),
          last_reflex: Enum.random([:stability, :chaos, :trust, :decay, nil])
        }
      end
    else
      # Production: Query from reflex events
      socket.assigns.reflex_events
      |> Enum.map(fn event ->
        %{
          bit_id: event[:bit_id] || "unknown",
          timestamp: event[:timestamp] || DateTime.utc_now(),
          state: event[:data][:state] || :unknown,
          lambda: event[:data][:lambda_hat] || 0.0,
          entropy: event[:data][:entropy] || 0.0,
          last_reflex: event[:type]
        }
      end)
      |> Enum.take(limit)
    end
  end

  defp fetch_bit_details(_socket, bit_id) do
    # Fetch detailed information about a specific bit
    # In production, this would query Thunderbit state
    %{
      bit_id: bit_id,
      position: {0, 0, 0},
      state: :active,
      lambda_hat: 0.273 + (:rand.uniform() - 0.5) * 0.1,
      entropy: :rand.uniform(),
      plv: 0.4 + :rand.uniform() * 0.3,
      lyapunov: (:rand.uniform() - 0.5) * 0.1,
      last_updated: DateTime.utc_now(),
      reflex_history: [
        %{type: :stability, timestamp: DateTime.add(DateTime.utc_now(), -120, :second)},
        %{type: :chaos, timestamp: DateTime.add(DateTime.utc_now(), -60, :second)}
      ],
      neighbors: 6,
      connectivity: 0.8
    }
  end

  defp heatmap_mode_label(:coherence), do: "Coherence"
  defp heatmap_mode_label(:plv), do: "PLV"
  defp heatmap_mode_label(:entropy), do: "Entropy"
  defp heatmap_mode_label(:lambda), do: "Lambda"
  defp heatmap_mode_label(:state), do: "State"
  defp heatmap_mode_label(_), do: "Unknown"

  defp state_color(:active), do: "text-emerald-400"
  defp state_color(:chaotic), do: "text-red-400"
  defp state_color(:dormant), do: "text-gray-400"
  defp state_color(:stable), do: "text-amber-400"
  defp state_color(_), do: "text-cyan-400"
end
