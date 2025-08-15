defmodule ThunderlineWeb.CaVisualizationLive do
  @moduledoc """
  3D Cellular Automata Visualization using Phoenix LiveView
  """

  use ThunderlineWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to CA updates from ThunderBridge
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "ca_updates")
      # Subscribe to neural updates from NeuralBridge 🧠
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "neural_updates")
    end

    initial_state = %{
      generation: 0,
      alive_cells: 0,
      pattern: "random",
      streaming: false,
      grid: [],
      update_interval: 500,
      view_mode: "cubes",
      fps: 0,
      rendered_objects: 0,
      # Neural integration state 🧠⚡
      neural_enabled: false,
      neural_activity: %{micro: 0.0, meso: 0.0, macro: 0.0, total: 0.0},
      cerebros_connected: false,
      learning_active: false,
      gpu_enabled: false
    }

    {:ok, assign(socket, initial_state)}
  end

  def render(assigns) do
    ~H"""
    <div id="ca-3d-container" phx-hook="CaVisualization" style="width: 100%; height: 100vh;">
      <div id="ca-3d-canvas" style="width: 100%; height: 100%;"></div>

      <div
        class="ca-controls"
        style="position: absolute; top: 20px; left: 20px; z-index: 100; background: rgba(0,0,0,0.8); padding: 15px; border-radius: 8px; color: white;"
      >
        <h3>3D CA Visualization</h3>
        <div class="control-group">
          <label>Generation: {@generation}</label>
          <br />
          <label>Alive Cells: {@alive_cells}</label>
          <br />
          <label>Pattern: {@pattern}</label>
        </div>

        <div class="control-group" style="margin-top: 10px;">
          <button phx-click="toggle_animation" class="btn">
            {if @streaming, do: "Pause", else: "Play"}
          </button>
          <button phx-click="reset_ca" class="btn">Reset</button>
          <button phx-click="randomize_ca" class="btn">Randomize</button>
        </div>

        <div class="control-group" style="margin-top: 10px;">
          <label>Speed:</label>
          <input
            type="range"
            min="50"
            max="2000"
            value={@update_interval}
            phx-change="change_speed"
            style="width: 100px;"
          />
          <span>{@update_interval}ms</span>
        </div>

        <div class="control-group" style="margin-top: 10px;">
          <label>View Mode:</label>
          <select phx-change="change_view_mode" value={@view_mode}>
            <option value="cubes">Cubes</option>
            <option value="spheres">Spheres</option>
            <option value="points">Points</option>
          </select>
        </div>
        
    <!-- Neural Controls 🧠⚡ -->
        <div
          class="neural-controls"
          style="margin-top: 15px; border-top: 1px solid #444; padding-top: 10px;"
        >
          <h4 style="color: #00ff88;">🧠 Neural Integration</h4>
          <div class="control-group">
            <button
              phx-click="toggle_neural"
              class={"btn neural-btn #{if @neural_enabled, do: "active", else: ""}"}
            >
              {if @neural_enabled, do: "Neural ON", else: "Neural OFF"}
            </button>
            <button phx-click="initialize_cerebros" class="btn">Init Cerebros</button>
            <button phx-click="start_learning" class="btn">Start Learning</button>
          </div>

          <div class="neural-status" style="margin-top: 10px; font-size: 12px;">
            <div>Cerebros: {if @cerebros_connected, do: "✅ Connected", else: "❌ Disconnected"}</div>
            <div>Learning: {if @learning_active, do: "🎯 Active", else: "⏸️ Inactive"}</div>
            <div>GPU: {if @gpu_enabled, do: "🚀 Enabled", else: "💻 CPU Only"}</div>
          </div>
        </div>
      </div>
      
    <!-- Neural Activity Visualization -->
      <div
        class="neural-activity"
        style="position: absolute; top: 20px; right: 200px; z-index: 100; background: rgba(0,0,0,0.8); padding: 15px; border-radius: 8px; color: white;"
      >
        <h4 style="color: #00ff88;">🧠 Neural Activity</h4>
        <div style="font-family: monospace; font-size: 12px;">
          <div>
            Micro:
            <span style="color: #00ffff;">{Float.round(@neural_activity.micro || 0.0, 3)}</span>
          </div>
          <div>
            Meso: <span style="color: #88ff00;">{Float.round(@neural_activity.meso || 0.0, 3)}</span>
          </div>
          <div>
            Macro:
            <span style="color: #ff8800;">{Float.round(@neural_activity.macro || 0.0, 3)}</span>
          </div>
          <div style="border-top: 1px solid #444; margin-top: 5px; padding-top: 5px;">
            Total:
            <span style="color: #ff00ff; font-weight: bold;">
              {Float.round(@neural_activity.total || 0.0, 3)}
            </span>
          </div>
        </div>
      </div>
      
    <!-- Performance Stats -->
      <div
        class="performance-stats"
        style="position: absolute; bottom: 20px; right: 20px; z-index: 100; background: rgba(0,0,0,0.8); padding: 10px; border-radius: 8px; color: white; font-family: monospace; font-size: 12px;"
      >
        <div>FPS: {@fps}</div>
        <div>Cells: {length(@grid)}</div>
        <div>Rendered: {@rendered_objects}</div>
      </div>
    </div>
    """
  end

  def handle_event("toggle_animation", _params, socket) do
    new_streaming = !socket.assigns.streaming

    # Send message to JS hook to start/stop animation
    {:noreply,
     push_event(socket, "ca_toggle_animation", %{streaming: new_streaming})
     |> assign(streaming: new_streaming)}
  end

  def handle_event("reset_ca", _params, socket) do
    # Send reset command to JS hook
    socket = push_event(socket, "ca_reset", %{})

    {:noreply,
     assign(socket,
       generation: 0,
       alive_cells: 0,
       pattern: "empty"
     )}
  end

  def handle_event("randomize_ca", _params, socket) do
    # Generate random initial state
    random_grid = generate_random_grid(20, 20, 20)

    # Send to JS hook
    socket = push_event(socket, "ca_randomize", %{grid: random_grid})

    {:noreply,
     assign(socket,
       generation: 0,
       alive_cells: count_alive_cells(random_grid),
       pattern: "random",
       grid: random_grid
     )}
  end

  def handle_event("change_speed", %{"value" => speed_str}, socket) do
    speed = String.to_integer(speed_str)

    # Send speed change to JS hook
    socket = push_event(socket, "ca_change_speed", %{interval: speed})

    {:noreply, assign(socket, update_interval: speed)}
  end

  def handle_event("change_view_mode", %{"value" => mode}, socket) do
    # Send view mode change to JS hook
    socket = push_event(socket, "ca_change_view_mode", %{mode: mode})

    {:noreply, assign(socket, view_mode: mode)}
  end

  # Neural integration event handlers 🧠⚡
  def handle_event("toggle_neural", _params, socket) do
    new_neural_enabled = !socket.assigns.neural_enabled

    if new_neural_enabled do
      # Initialize neural system
      case Thunderline.NeuralBridge.initialize_neural_system() do
        {:ok, :initialized} ->
          socket =
            assign(socket, neural_enabled: true)
            |> put_flash(:info, "🧠 Neural system initialized!")

        {:error, reason} ->
          socket = put_flash(socket, :error, "❌ Neural init failed: #{inspect(reason)}")
      end
    else
      socket =
        assign(socket, neural_enabled: false)
        |> put_flash(:info, "🧠 Neural system disabled")
    end

    {:noreply, socket}
  end

  def handle_event("initialize_cerebros", _params, socket) do
    case Thunderline.NeuralBridge.create_cerebros_architecture() do
      {:ok, architecture_summary} ->
        socket =
          assign(socket,
            cerebros_connected: true,
            gpu_enabled: Map.get(architecture_summary, :gpu_enabled, false)
          )
          |> put_flash(
            :info,
            "🚀 Cerebros architecture created! #{architecture_summary.total_parameters} parameters"
          )

      {:error, reason} ->
        socket = put_flash(socket, :error, "❌ Cerebros init failed: #{inspect(reason)}")
    end

    {:noreply, socket}
  end

  def handle_event("start_learning", _params, socket) do
    training_config = %{
      learning_rate: 0.001,
      batch_size: 32,
      epochs: 100
    }

    case Thunderline.NeuralBridge.start_neural_training(training_config) do
      {:ok, :training_started} ->
        socket =
          assign(socket, learning_active: true)
          |> put_flash(:info, "🎯 Neural training started!")

      {:error, reason} ->
        socket = put_flash(socket, :error, "❌ Training failed: #{inspect(reason)}")
    end

    {:noreply, socket}
  end

  # Handle updates from the JavaScript hook
  def handle_event("ca_update", params, socket) do
    %{
      "generation" => generation,
      "alive_cells" => alive_cells,
      "grid" => grid,
      "fps" => fps,
      "rendered_objects" => rendered_objects
    } = params

    {:noreply,
     assign(socket,
       generation: generation,
       alive_cells: alive_cells,
       grid: grid,
       fps: fps,
       rendered_objects: rendered_objects
     )}
  end

  # Handle real-time data from the backend
  def handle_info({:ca_data, data}, socket) do
    # This receives data from Thunderline.ThunderBridge
    case data do
      %{grid: grid, generation: gen, stats: stats} ->
        # Send real data to JS hook
        socket =
          push_event(socket, "ca_real_data", %{
            grid: grid,
            generation: gen,
            stats: stats
          })

        {:noreply,
         assign(socket,
           generation: gen,
           alive_cells: stats[:alive_cells] || 0,
           grid: grid,
           pattern: "real-time"
         )}

      _ ->
        {:noreply, socket}
    end
  end

  # Handle neural updates from NeuralBridge 🧠⚡
  def handle_info({:neural_update, neural_data}, socket) do
    # Update neural activity visualization
    socket =
      assign(socket,
        neural_activity: neural_data.neural_activity || socket.assigns.neural_activity,
        generation: neural_data.generation || socket.assigns.generation
      )

    # Send neural data to JS hook for 3D visualization
    socket =
      push_event(socket, "neural_update", %{
        activity: neural_data.neural_activity,
        generation: neural_data.generation,
        tensors: format_tensors_for_js(neural_data.tensors)
      })

    {:noreply, socket}
  end

  # Private helper functions
  defp generate_random_grid(width, height, depth) do
    for x <- 0..(width - 1),
        y <- 0..(height - 1),
        z <- 0..(depth - 1) do
      %{
        x: x,
        y: y,
        z: z,
        # 30% chance of being alive
        alive: :rand.uniform() > 0.7,
        age: 0,
        neighbors: 0
      }
    end
  end

  defp count_alive_cells(grid) when is_list(grid) do
    Enum.count(grid, fn cell -> cell.alive end)
  end

  defp count_alive_cells(_), do: 0

  # Neural helper functions 🧠⚡
  defp format_tensors_for_js(tensors) when is_map(tensors) do
    tensors
    |> Enum.map(fn {key, tensor} ->
      try do
        # Convert Nx tensor to list for JSON serialization
        tensor_data =
          case tensor do
            %Nx.Tensor{} -> Nx.to_list(tensor)
            _ -> []
          end

        {key, tensor_data}
      rescue
        _ -> {key, []}
      end
    end)
    |> Map.new()
  end

  defp format_tensors_for_js(_), do: %{}
end
