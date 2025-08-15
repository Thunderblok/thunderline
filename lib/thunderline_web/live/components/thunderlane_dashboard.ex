defmodule ThunderlineWeb.Live.Components.ThunderlaneDashboard do
  @moduledoc """
  Thunderlane Dashboard - Matching the nested hexagonal and radial burst aesthetic

  Implements the multi-scale coordination visualization with:
  - Nested hexagonal lane patterns (like the first image)
  - Radial burst consensus visualization (like the third image)
  - Flowing gradient performance streams (like the fourth image)
  - Retro-future color schemes with depth and motion
  """

  use ThunderlineWeb, :live_view
  use Phoenix.Component

  # Color schemes matching the aesthetic
  @retro_gradients %{
    teal_burst: ["#00FFE1", "#00B8CC", "#007B8A", "#004A52"],
    sunset_flow: ["#FF6B35", "#F7931E", "#FFD23F", "#FFF1C1"],
    purple_depth: ["#8B5CF6", "#6366F1", "#3B82F6", "#0EA5E9"],
    neon_layers: ["#FF0080", "#FF4081", "#FF80AB", "#FFB3D1"]
  }

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time Thunderlane events
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderlane:dashboard")
      send(self(), :load_initial_data)
    end

    {:ok,
     assign(socket,
       lane_configurations: [],
       consensus_runs: [],
       performance_metrics: [],
       telemetry_snapshots: [],
       live_updates: true,
       visualization_mode: :nested_hexagon,
       loading: true,
       error: nil
     )}
  end

  def handle_info(:load_initial_data, socket) do
    # Load initial dashboard data with error handling
    try do
      lanes = load_lane_configurations()
      consensus = load_consensus_runs()
      performance = load_performance_metrics()
      telemetry = load_telemetry_snapshots()

      {:noreply,
       assign(socket,
         lane_configurations: lanes,
         consensus_runs: consensus,
         performance_metrics: performance,
         telemetry_snapshots: telemetry,
         loading: false,
         error: nil
       )}
    rescue
      error ->
        {:noreply,
         assign(socket,
           loading: false,
           error: "Failed to load dashboard data: #{inspect(error)}"
         )}
    end
  end

  def handle_info({:lane_updated, lane_data}, socket) do
    # Real-time lane updates - trigger hexagonal visualization refresh
    updated_lanes = update_lane_in_list(socket.assigns.lane_configurations, lane_data)
    {:noreply, assign(socket, lane_configurations: updated_lanes)}
  end

  def handle_info({:consensus_progress, consensus_data}, socket) do
    # Real-time consensus updates - trigger radial burst animation
    updated_consensus = update_consensus_in_list(socket.assigns.consensus_runs, consensus_data)
    {:noreply, assign(socket, consensus_runs: updated_consensus)}
  end

  def handle_info({:performance_metric, metric_data}, socket) do
    # Real-time performance updates - trigger flowing gradient animation
    updated_metrics = add_performance_metric(socket.assigns.performance_metrics, metric_data)
    {:noreply, assign(socket, performance_metrics: updated_metrics)}
  end

  def handle_event("retry_load", _params, socket) do
    # Retry loading dashboard data
    send(self(), :load_initial_data)
    {:noreply, assign(socket, loading: true, error: nil)}
  end

  def render(assigns) do
    ~H"""
    <div class="thunderlane-dashboard" id="thunderlane-dashboard">
      <%= if @loading do %>
        <!-- Loading State with Neon Aesthetic -->
        <div class="loading-overlay">
          <div class="loading-spinner pulse-glow">
            <div class="spinner-ring"></div>
            <div class="loading-text">Loading Thunderlane Dashboard...</div>
          </div>
        </div>
      <% else %>
        <%= if @error do %>
          <!-- Error State -->
          <div class="error-overlay">
            <div class="error-container pulse-glow">
              <div class="error-icon">⚠️</div>
              <div class="error-text">{@error}</div>
              <button phx-click="retry_load" class="retry-button">Retry</button>
            </div>
          </div>
        <% else %>
          <!-- Main Dashboard Container with Retro-Future Styling -->
          <div class="dashboard-container">
            
    <!-- Nested Hexagonal Lane Visualization -->
            <div class="panel hexagonal-lanes-panel">
              <.hexagonal_lane_grid lanes={@lane_configurations} />
            </div>
            
    <!-- Radial Burst Consensus Visualization -->
            <div class="panel radial-consensus-panel">
              <.radial_consensus_burst runs={@consensus_runs} />
            </div>
            
    <!-- Flowing Performance Streams -->
            <div class="panel performance-flow-panel">
              <.performance_gradient_flow metrics={@performance_metrics} />
            </div>
            
    <!-- Multi-Layer Telemetry Visualization -->
            <div class="panel telemetry-layers-panel">
              <.telemetry_nested_layers snapshots={@telemetry_snapshots} />
            </div>
          </div>
        <% end %>
      <% end %>
    </div>

    <style>
      /* Core Dashboard Styling - Matching the Aesthetic */
      .thunderlane-dashboard {
        background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 50%, #16213e 100%);
        min-height: 100vh;
        color: #00FFE1;
        font-family: 'Orbitron', monospace;
        overflow: hidden;
      }

      .dashboard-container {
        display: grid;
        grid-template-columns: 1fr 1fr;
        grid-template-rows: 1fr 1fr;
        gap: 2rem;
        padding: 2rem;
        height: 100vh;
      }

      .panel {
        background: rgba(0, 255, 225, 0.05);
        border: 1px solid rgba(0, 255, 225, 0.2);
        border-radius: 12px;
        padding: 1.5rem;
        position: relative;
        overflow: hidden;
        backdrop-filter: blur(10px);
      }

      .panel::before {
        content: '';
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: linear-gradient(45deg,
          rgba(0, 255, 225, 0.1) 0%,
          rgba(139, 92, 246, 0.1) 50%,
          rgba(255, 107, 53, 0.1) 100%);
        opacity: 0.3;
        z-index: -1;
      }

      /* Hexagonal Lane Grid Styling */
      .hexagonal-lanes-panel {
        background: radial-gradient(circle at center,
          rgba(0, 255, 225, 0.15) 0%,
          rgba(0, 184, 204, 0.1) 40%,
          rgba(0, 74, 82, 0.05) 80%);
      }

      /* Radial Burst Consensus Styling */
      .radial-consensus-panel {
        background: radial-gradient(circle at center,
          rgba(255, 107, 53, 0.15) 0%,
          rgba(247, 147, 30, 0.1) 40%,
          rgba(255, 210, 63, 0.05) 80%);
      }

      /* Performance Flow Styling */
      .performance-flow-panel {
        background: linear-gradient(90deg,
          rgba(139, 92, 246, 0.15) 0%,
          rgba(99, 102, 241, 0.1) 30%,
          rgba(59, 130, 246, 0.08) 60%,
          rgba(14, 165, 233, 0.05) 100%);
      }

      /* Telemetry Layers Styling */
      .telemetry-layers-panel {
        background: linear-gradient(135deg,
          rgba(255, 0, 128, 0.15) 0%,
          rgba(255, 64, 129, 0.1) 30%,
          rgba(255, 128, 171, 0.08) 60%,
          rgba(255, 179, 209, 0.05) 100%);
      }

      /* Animation Classes */
      .pulse-glow {
        animation: pulseGlow 2s ease-in-out infinite alternate;
      }

      .rotate-burst {
        animation: rotateBurst 8s linear infinite;
      }

      .flow-gradient {
        animation: flowGradient 3s ease-in-out infinite;
      }

      @keyframes pulseGlow {
        0% { opacity: 0.6; transform: scale(1); }
        100% { opacity: 1; transform: scale(1.05); }
      }

      @keyframes rotateBurst {
        0% { transform: rotate(0deg); }
        100% { transform: rotate(360deg); }
      }

      @keyframes flowGradient {
        0% { background-position: 0% 50%; }
        50% { background-position: 100% 50%; }
        100% { background-position: 0% 50%; }
      }

      /* Loading and Error State Styling */
      .loading-overlay, .error-overlay {
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0, 0, 0, 0.8);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 100;
      }

      .loading-spinner {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1rem;
      }

      .spinner-ring {
        width: 60px;
        height: 60px;
        border: 4px solid rgba(0, 255, 225, 0.2);
        border-top: 4px solid #00FFE1;
        border-radius: 50%;
        animation: spin 1s linear infinite;
      }

      .loading-text {
        color: #00FFE1;
        font-size: 1.1rem;
        text-shadow: 0 0 10px rgba(0, 255, 225, 0.5);
      }

      .error-container {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1rem;
        padding: 2rem;
        background: rgba(255, 0, 0, 0.1);
        border: 1px solid rgba(255, 0, 0, 0.3);
        border-radius: 12px;
      }

      .error-icon {
        font-size: 2rem;
        filter: hue-rotate(320deg);
      }

      .error-text {
        color: #FF6B6B;
        text-align: center;
        font-size: 1rem;
        text-shadow: 0 0 5px rgba(255, 107, 107, 0.5);
      }

      .retry-button {
        background: linear-gradient(45deg, #FF6B35, #F7931E);
        border: none;
        color: white;
        padding: 0.5rem 1rem;
        border-radius: 6px;
        cursor: pointer;
        font-weight: bold;
        transition: all 0.3s ease;
      }

      .retry-button:hover {
        transform: scale(1.05);
        box-shadow: 0 0 15px rgba(255, 107, 53, 0.6);
      }

      @keyframes spin {
        0% { transform: rotate(0deg); }
        100% { transform: rotate(360deg); }
      }
    </style>
    """
  end

  # Nested Hexagonal Lane Grid Component (matching first image aesthetic)
  def hexagonal_lane_grid(assigns) do
    ~H"""
    <div class="hexagonal-grid-container">
      <h3 class="panel-title">Multi-Scale Lane Coordination</h3>

      <div class="hexagon-layers">
        <!-- Outer hexagonal boundary -->
        <div class="hexagon-layer outer-boundary"></div>
        
    <!-- Lane family rings -->
        <div
          :for={{layer_index, lanes} <- Enum.with_index(group_lanes_by_family(@lanes))}
          class={"hexagon-layer lane-family-#{layer_index}"}
        >
          <div
            :for={lane <- lanes}
            class={"lane-node #{lane_status_class(lane)} #{lane_type_class(lane)}"}
            title={"Lane #{lane.id}: #{lane.name} (#{lane.state})"}
          >
            <div class="lane-inner-glow"></div>
            <span class="lane-label">{String.slice(lane.name, 0, 3)}</span>
          </div>
        </div>
        
    <!-- Central coordination hub -->
        <div class="coordination-hub pulse-glow">
          <div class="hub-center"></div>
          <div class="hub-label">CORE</div>
        </div>
      </div>
      
    <!-- Lane statistics overlay -->
      <div class="lane-stats">
        <div class="stat-item">
          <span class="stat-value">{Enum.count(@lanes, &(&1.state == :active))}</span>
          <span class="stat-label">Active Lanes</span>
        </div>
        <div class="stat-item">
          <span class="stat-value">{calculate_total_coupling(@lanes) |> Float.round(2)}</span>
          <span class="stat-label">α-Coupling</span>
        </div>
      </div>
    </div>

    <style>
      .hexagonal-grid-container {
        position: relative;
        height: 100%;
        display: flex;
        flex-direction: column;
      }

      .panel-title {
        color: #00FFE1;
        font-size: 1.2rem;
        margin-bottom: 1rem;
        text-align: center;
        text-shadow: 0 0 10px rgba(0, 255, 225, 0.5);
      }

      .hexagon-layers {
        position: relative;
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .hexagon-layer {
        position: absolute;
        border: 2px solid;
        transform: rotate(30deg);
        display: flex;
        align-items: center;
        justify-content: space-around;
      }

      .outer-boundary {
        width: 280px;
        height: 280px;
        border-color: rgba(0, 255, 225, 0.4);
        clip-path: polygon(30% 0%, 70% 0%, 100% 50%, 70% 100%, 30% 100%, 0% 50%);
      }

      .lane-family-0 {
        width: 220px;
        height: 220px;
        border-color: rgba(139, 92, 246, 0.6);
        clip-path: polygon(30% 0%, 70% 0%, 100% 50%, 70% 100%, 30% 100%, 0% 50%);
      }

      .lane-family-1 {
        width: 160px;
        height: 160px;
        border-color: rgba(255, 107, 53, 0.6);
        clip-path: polygon(30% 0%, 70% 0%, 100% 50%, 70% 100%, 30% 100%, 0% 50%);
      }

      .lane-node {
        width: 24px;
        height: 24px;
        border-radius: 50%;
        position: relative;
        transform: rotate(-30deg);
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        transition: all 0.3s ease;
      }

      .lane-node:hover {
        transform: rotate(-30deg) scale(1.3);
      }

      .lane-node.active {
        background: radial-gradient(circle, #00FFE1, #007B8A);
        box-shadow: 0 0 15px rgba(0, 255, 225, 0.8);
      }

      .lane-node.paused {
        background: radial-gradient(circle, #FFD23F, #F7931E);
        box-shadow: 0 0 15px rgba(255, 210, 63, 0.8);
      }

      .lane-node.initializing {
        background: radial-gradient(circle, #8B5CF6, #6366F1);
        box-shadow: 0 0 15px rgba(139, 92, 246, 0.8);
      }

      .coordination-hub {
        width: 60px;
        height: 60px;
        border-radius: 50%;
        background: radial-gradient(circle,
          rgba(0, 255, 225, 0.9) 0%,
          rgba(0, 184, 204, 0.7) 50%,
          rgba(0, 123, 138, 0.5) 100%);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        position: relative;
        z-index: 10;
        border: 3px solid rgba(0, 255, 225, 0.8);
      }

      .hub-label {
        font-size: 0.6rem;
        font-weight: bold;
        color: #003D42;
      }

      .lane-stats {
        position: absolute;
        bottom: 10px;
        left: 10px;
        display: flex;
        gap: 1rem;
      }

      .stat-item {
        display: flex;
        flex-direction: column;
        align-items: center;
      }

      .stat-value {
        font-size: 1.5rem;
        font-weight: bold;
        color: #00FFE1;
        text-shadow: 0 0 5px rgba(0, 255, 225, 0.5);
      }

      .stat-label {
        font-size: 0.7rem;
        color: rgba(0, 255, 225, 0.7);
      }
    </style>
    """
  end

  # Radial Burst Consensus Component (matching third image aesthetic)
  def radial_consensus_burst(assigns) do
    ~H"""
    <div class="consensus-burst-container">
      <h3 class="panel-title">Consensus Burst Dynamics</h3>

      <div class="burst-visualization">
        <div class="consensus-center">
          <div class="center-core pulse-glow"></div>
        </div>
        
    <!-- Radial consensus streams -->
        <div
          :for={{index, run} <- Enum.with_index(@runs)}
          class={"consensus-ray ray-#{rem(index, 8)} rotate-burst"}
          style={"--delay: #{index * 0.2}s"}
        >
          <div class={"ray-segment segment-1 #{consensus_intensity_class(run)}"}>
            <div class="ray-glow"></div>
          </div>
          <div class={"ray-segment segment-2 #{consensus_intensity_class(run)}"}>
            <div class="ray-glow"></div>
          </div>
          <div class={"ray-segment segment-3 #{consensus_intensity_class(run)}"}>
            <div class="ray-glow"></div>
          </div>
        </div>
        
    <!-- Orbital consensus indicators -->
        <div class="consensus-orbits">
          <div
            :for={run <- @runs}
            class={"orbital-indicator #{consensus_status_class(run)}"}
            title={"Matrix #{run.matrix_size}x#{run.matrix_size} - #{run.status}"}
          >
          </div>
        </div>
      </div>
      
    <!-- Consensus metrics -->
      <div class="consensus-metrics">
        <div class="metric-bar">
          <span class="metric-label">Success Rate</span>
          <div class="metric-progress">
            <div class="progress-fill" style={"width: #{calculate_success_rate(@runs)}%"}></div>
          </div>
          <span class="metric-value">{calculate_success_rate(@runs)}%</span>
        </div>
      </div>
    </div>

    <style>
      .consensus-burst-container {
        position: relative;
        height: 100%;
        display: flex;
        flex-direction: column;
      }

      .burst-visualization {
        position: relative;
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
      }

      .consensus-center {
        position: absolute;
        width: 80px;
        height: 80px;
        z-index: 10;
      }

      .center-core {
        width: 100%;
        height: 100%;
        border-radius: 50%;
        background: radial-gradient(circle,
          #FF6B35 0%,
          #F7931E 30%,
          #FFD23F  60%,
          #FFF1C1 100%);
        border: 4px solid rgba(255, 107, 53, 0.8);
      }

      .consensus-ray {
        position: absolute;
        width: 200px;
        height: 8px;
        transform-origin: left center;
        animation-duration: 4s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-delay: var(--delay);
      }

      .ray-0 { transform: rotate(0deg); }
      .ray-1 { transform: rotate(45deg); }
      .ray-2 { transform: rotate(90deg); }
      .ray-3 { transform: rotate(135deg); }
      .ray-4 { transform: rotate(180deg); }
      .ray-5 { transform: rotate(225deg); }
      .ray-6 { transform: rotate(270deg); }
      .ray-7 { transform: rotate(315deg); }

      .ray-segment {
        height: 100%;
        margin-left: 2px;
        position: relative;
        border-radius: 4px;
      }

      .segment-1 {
        width: 60px;
        background: linear-gradient(to right, #00FFE1, #00B8CC);
      }

      .segment-2 {
        width: 80px;
        background: linear-gradient(to right, #FFD23F, #F7931E);
        margin-left: 65px;
      }

      .segment-3 {
        width: 50px;
        background: linear-gradient(to right, #FF6B35, #FF4500);
        margin-left: 150px;
      }

      .ray-glow {
        position: absolute;
        top: -2px;
        left: -2px;
        right: -2px;
        bottom: -2px;
        background: inherit;
        border-radius: inherit;
        filter: blur(4px);
        opacity: 0.6;
        z-index: -1;
      }

      .consensus-metrics {
        padding: 1rem 0;
      }

      .metric-bar {
        display: flex;
        align-items: center;
        gap: 1rem;
      }

      .metric-label {
        min-width: 80px;
        font-size: 0.8rem;
        color: rgba(255, 107, 53, 0.9);
      }

      .metric-progress {
        flex: 1;
        height: 8px;
        background: rgba(255, 107, 53, 0.2);
        border-radius: 4px;
        overflow: hidden;
      }

      .progress-fill {
        height: 100%;
        background: linear-gradient(to right, #FF6B35, #FFD23F);
        transition: width 0.5s ease;
      }

      .metric-value {
        min-width: 40px;
        text-align: right;
        font-weight: bold;
        color: #FFD23F;
      }
    </style>
    """
  end

  # Performance Gradient Flow Component (matching fourth image aesthetic)
  def performance_gradient_flow(assigns) do
    ~H"""
    <div class="performance-flow-container">
      <h3 class="panel-title">Performance Flow Dynamics</h3>

      <div class="flow-visualization">
        <!-- Flowing performance streams -->
        <div
          :for={{scale, metrics} <- group_metrics_by_scale(@metrics)}
          class={"performance-stream #{scale}-scale flow-gradient"}
        >
          <div class="stream-path">
            <div class="flow-segments">
              <div
                :for={metric <- Enum.take(metrics, 5)}
                class={"flow-segment #{performance_intensity_class(metric.value)}"}
                style={"--flow-delay: #{metric.step_number * 0.1}s"}
              >
              </div>
            </div>
          </div>

          <div class="stream-label">
            <span class="scale-name">{String.upcase(to_string(scale))}</span>
            <span class="scale-value">{calculate_avg_performance(metrics) |> Float.round(3)}</span>
          </div>
        </div>
        
    <!-- Central performance nexus -->
        <div class="performance-nexus">
          <div class="nexus-core pulse-glow"></div>
          <div class="performance-rings">
            <div class="perf-ring ring-1"></div>
            <div class="perf-ring ring-2"></div>
            <div class="perf-ring ring-3"></div>
          </div>
        </div>
      </div>
    </div>

    <style>
      .performance-flow-container {
        position: relative;
        height: 100%;
        display: flex;
        flex-direction: column;
      }

      .flow-visualization {
        position: relative;
        flex: 1;
        overflow: hidden;
      }

      .performance-stream {
        position: absolute;
        height: 24px;
        border-radius: 12px;
        background-size: 200% 100%;
      }

      .micro-scale {
        top: 20%;
        left: 10%;
        width: 70%;
        background: linear-gradient(90deg, #8B5CF6, #6366F1, #3B82F6, #0EA5E9);
      }

      .meso-scale {
        top: 40%;
        left: 5%;
        width: 80%;
        background: linear-gradient(90deg, #FF6B35, #F7931E, #FFD23F, #FFF1C1);
      }

      .macro-scale {
        top: 60%;
        left: 15%;
        width: 75%;
        background: linear-gradient(90deg, #00FFE1, #00B8CC, #007B8A, #004A52);
      }

      .fusion-scale {
        top: 80%;
        left: 8%;
        width: 85%;
        background: linear-gradient(90deg, #FF0080, #FF4081, #FF80AB, #FFB3D1);
      }

      .flow-segments {
        display: flex;
        height: 100%;
        gap: 4px;
        padding: 4px;
      }

      .flow-segment {
        height: 16px;
        width: 40px;
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.9);
        animation: flowPulse 1.5s ease-in-out infinite;
        animation-delay: var(--flow-delay);
      }

      .performance-nexus {
        position: absolute;
        right: 5%;
        top: 50%;
        transform: translateY(-50%);
        width: 120px;
        height: 120px;
      }

      .nexus-core {
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        width: 40px;
        height: 40px;
        border-radius: 50%;
        background: radial-gradient(circle, #FFD23F, #F7931E);
        z-index: 5;
      }

      .performance-rings {
        position: relative;
        width: 100%;
        height: 100%;
      }

      .perf-ring {
        position: absolute;
        border-radius: 50%;
        border: 2px solid;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
      }

      .ring-1 {
        width: 60px;
        height: 60px;
        border-color: rgba(139, 92, 246, 0.6);
        animation: ringPulse 2s ease-in-out infinite;
      }

      .ring-2 {
        width: 80px;
        height: 80px;
        border-color: rgba(0, 255, 225, 0.5);
        animation: ringPulse 2s ease-in-out infinite 0.5s;
      }

      .ring-3 {
        width: 100px;
        height: 100px;
        border-color: rgba(255, 107, 53, 0.4);
        animation: ringPulse 2s ease-in-out infinite 1s;
      }

      .stream-label {
        position: absolute;
        right: -60px;
        top: 50%;
        transform: translateY(-50%);
        display: flex;
        flex-direction: column;
        align-items: center;
        font-size: 0.7rem;
      }

      .scale-name {
        font-weight: bold;
        color: rgba(255, 255, 255, 0.9);
      }

      .scale-value {
        color: rgba(255, 210, 63, 0.8);
      }

      @keyframes flowPulse {
        0%, 100% { opacity: 0.3; transform: scaleX(1); }
        50% { opacity: 1; transform: scaleX(1.2); }
      }

      @keyframes ringPulse {
        0%, 100% { opacity: 0.3; transform: translate(-50%, -50%) scale(1); }
        50% { opacity: 0.8; transform: translate(-50%, -50%) scale(1.1); }
      }
    </style>
    """
  end

  # Telemetry Nested Layers Component (matching first image's nested structure)
  def telemetry_nested_layers(assigns) do
    ~H"""
    <div class="telemetry-layers-container">
      <h3 class="panel-title">Telemetry Layer Analysis</h3>

      <div class="nested-layers-viz">
        <!-- Multi-layer nested structure -->
        <div
          :for={{layer_index, snapshots} <- Enum.with_index(group_snapshots_by_type(@snapshots))}
          class={"telemetry-layer layer-#{layer_index} pulse-glow"}
          style={"--layer-delay: #{layer_index * 0.3}s"}
        >
          <div class="layer-border"></div>
          <div class="layer-content">
            <div class="layer-metrics">
              <span class="metric-count">{Enum.count(snapshots)}</span>
              <span class="metric-type">{get_snapshot_type_name(layer_index)}</span>
            </div>
          </div>
        </div>
        
    <!-- Central telemetry core -->
        <div class="telemetry-core">
          <div class="core-pulse pulse-glow"></div>
          <div class="core-stats">
            <div class="stat-line">
              <span class="stat-value">{calculate_total_events(@snapshots)}</span>
              <span class="stat-unit">events/sec</span>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Real-time telemetry stream -->
      <div class="telemetry-stream">
        <div
          :for={snapshot <- Enum.take(@snapshots, 10)}
          class={"stream-dot #{snapshot_priority_class(snapshot)}"}
          style={"--stream-delay: #{snapshot.window_start_ms * 0.001}s"}
        >
        </div>
      </div>
    </div>

    <style>
      .telemetry-layers-container {
        position: relative;
        height: 100%;
        display: flex;
        flex-direction: column;
      }

      .nested-layers-viz {
        position: relative;
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .telemetry-layer {
        position: absolute;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        animation: layerPulse 3s ease-in-out infinite;
        animation-delay: var(--layer-delay);
      }

      .layer-0 {
        width: 280px;
        height: 280px;
        border: 3px solid rgba(255, 0, 128, 0.6);
      }

      .layer-1 {
        width: 220px;
        height: 220px;
        border: 3px solid rgba(255, 64, 129, 0.7);
      }

      .layer-2 {
        width: 160px;
        height: 160px;
        border: 3px solid rgba(255, 128, 171, 0.8);
      }

      .layer-3 {
        width: 100px;
        height: 100px;
        border: 3px solid rgba(255, 179, 209, 0.9);
      }

      .telemetry-core {
        position: absolute;
        width: 60px;
        height: 60px;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        z-index: 10;
      }

      .core-pulse {
        width: 100%;
        height: 100%;
        border-radius: 50%;
        background: radial-gradient(circle,
          rgba(255, 0, 128, 0.9) 0%,
          rgba(255, 64, 129, 0.7) 50%,
          rgba(255, 128, 171, 0.5) 100%);
        border: 2px solid rgba(255, 0, 128, 0.8);
      }

      .core-stats {
        position: absolute;
        bottom: -30px;
        text-align: center;
      }

      .stat-line {
        display: flex;
        flex-direction: column;
        font-size: 0.7rem;
      }

      .stat-value {
        font-weight: bold;
        color: #FF0080;
      }

      .stat-unit {
        color: rgba(255, 128, 171, 0.8);
      }

      .telemetry-stream {
        display: flex;
        gap: 8px;
        padding: 1rem 0;
        overflow-x: auto;
      }

      .stream-dot {
        width: 12px;
        height: 12px;
        border-radius: 50%;
        flex-shrink: 0;
        animation: streamFlow 2s ease-in-out infinite;
        animation-delay: var(--stream-delay);
      }

      .stream-dot.window {
        background: radial-gradient(circle, #00FFE1, #007B8A);
      }

      .stream-dot.burst {
        background: radial-gradient(circle, #FF6B35, #F7931E);
      }

      .stream-dot.anomaly {
        background: radial-gradient(circle, #FF0080, #FF4081);
      }

      .stream-dot.baseline {
        background: radial-gradient(circle, #8B5CF6, #6366F1);
      }

      @keyframes layerPulse {
        0%, 100% { opacity: 0.4; transform: scale(1); }
        50% { opacity: 0.8; transform: scale(1.02); }
      }

      @keyframes streamFlow {
        0% { opacity: 0.3; transform: translateY(0); }
        50% { opacity: 1; transform: translateY(-4px); }
        100% { opacity: 0.3; transform: translateY(0); }
      }
    </style>
    """
  end

  # Helper functions for data processing and styling
  defp load_lane_configurations do
    # Real API data fetching via ApiClient
    ThunderlineWeb.Live.ApiClient.fetch_lane_configurations()
  end

  defp load_consensus_runs do
    # Real API data fetching via ApiClient
    ThunderlineWeb.Live.ApiClient.fetch_consensus_runs()
  end

  defp load_performance_metrics do
    # Real API data fetching via ApiClient
    ThunderlineWeb.Live.ApiClient.fetch_performance_metrics()
  end

  defp load_telemetry_snapshots do
    # Real API data fetching via ApiClient
    ThunderlineWeb.Live.ApiClient.fetch_telemetry_snapshots()
  end

  defp group_lanes_by_family(lanes) do
    lanes
    |> Enum.group_by(& &1.family)
    |> Map.values()
  end

  defp group_metrics_by_scale(metrics) do
    Enum.group_by(metrics, & &1.metric_type)
  end

  defp group_snapshots_by_type(snapshots) do
    snapshots
    |> Enum.group_by(& &1.snapshot_type)
    |> Map.values()
  end

  defp lane_status_class(%{state: state}), do: to_string(state)
  defp lane_type_class(%{lane_type: type}), do: "type-#{type}"

  defp consensus_intensity_class(%{matrix_size: size}) when size > 100, do: "high-intensity"
  defp consensus_intensity_class(%{matrix_size: size}) when size > 50, do: "medium-intensity"
  defp consensus_intensity_class(_), do: "low-intensity"

  defp consensus_status_class(%{success: true}), do: "consensus-success"
  defp consensus_status_class(%{success: false}), do: "consensus-failed"
  defp consensus_status_class(_), do: "consensus-running"

  defp performance_intensity_class(value) when value > 0.8, do: "high-performance"
  defp performance_intensity_class(value) when value > 0.5, do: "medium-performance"
  defp performance_intensity_class(_), do: "low-performance"

  defp snapshot_priority_class(%{snapshot_type: type}), do: to_string(type)

  defp calculate_total_coupling(lanes) do
    lanes
    |> Enum.map(& &1.coupling_strength)
    |> Enum.sum()
  end

  defp calculate_success_rate(runs) do
    successful = Enum.count(runs, &(&1.success == true))
    total = Enum.count(runs)
    if total > 0, do: (successful / total * 100) |> round(), else: 0
  end

  defp calculate_avg_performance(metrics) do
    if Enum.count(metrics) > 0 do
      metrics
      |> Enum.map(& &1.value)
      |> Enum.sum()
      |> Kernel./(Enum.count(metrics))
    else
      0.0
    end
  end

  defp calculate_total_events(snapshots) do
    snapshots
    |> Enum.map(& &1.total_events)
    |> Enum.sum()
  end

  defp get_snapshot_type_name(0), do: "WINDOW"
  defp get_snapshot_type_name(1), do: "BURST"
  defp get_snapshot_type_name(2), do: "ANOMALY"
  defp get_snapshot_type_name(3), do: "BASELINE"
  defp get_snapshot_type_name(_), do: "UNKNOWN"

  # Placeholder helper functions for real-time updates
  defp update_lane_in_list(lanes, new_lane_data) do
    # Update lane in the list with new data
    lanes
  end

  defp update_consensus_in_list(runs, new_consensus_data) do
    # Update consensus run in the list with new data
    runs
  end

  defp add_performance_metric(metrics, new_metric) do
    # Add new performance metric to the list
    # Keep last 100 metrics
    [new_metric | metrics] |> Enum.take(100)
  end
end
