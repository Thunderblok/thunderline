defmodule ThunderlineWeb.AutomataLive do
  @moduledoc """
  AutomataLive - Real-time Cellular Automata Visualization and Control

  Provides interactive visualization and control for:
  - 2D/3D Cellular Automata patterns
  - Neural Cellular Automata experiments
  - Rule evolution and pattern analysis
  - Real-time parameter adjustment
  """

  use ThunderlineWeb, :live_view

  alias Thunderline.DashboardMetrics
  alias Thunderline.Automata.Blackboard
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DashboardMetrics.subscribe()
      # Subscribe to automata-specific updates
      PubSub.subscribe(Thunderline.PubSub, "automata:updates")
      # Subscribe to blackboard updates (future reactive panels)
      Blackboard.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Cellular Automata")
     |> assign(:automata_state, load_automata_state())
     |> assign(:active_rule, :rule_30)
     |> assign(:generation, 0)
     |> assign(:pattern_buffer, [])
     |> assign(:running, false)
     # milliseconds between generations
     |> assign(:speed, 100)}
  end

  @impl true
  def handle_info({:metrics_update, metrics}, socket) do
    automata_data = Map.get(metrics, :automata, %{})

    {:noreply, assign(socket, :automata_state, automata_data)}
  end

  @impl true
  def handle_info({:automata_update, data}, socket) do
    {:noreply,
     socket
     |> assign(:generation, data.generation)
     |> assign(:pattern_buffer, data.pattern)
     |> assign(:automata_state, Map.merge(socket.assigns.automata_state, data))}
  end

  # Ignore/optionally react to blackboard updates for now.
  @impl true
  def handle_info({:blackboard_update, %{key: {:automata, _k}} = update}, socket) do
    # For future: we could merge derived stats. For now, no state change to keep deterministic test.
    _ = update
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_simulation", _params, socket) do
    new_running = not socket.assigns.running

    if new_running do
      schedule_next_generation()
    end

    {:noreply, assign(socket, :running, new_running)}
  end

  @impl true
  def handle_event("reset_simulation", _params, socket) do
    {:noreply,
     socket
     |> assign(:generation, 0)
     |> assign(:pattern_buffer, [])
     |> assign(:running, false)}
  end

  @impl true
  def handle_event("change_rule", %{"rule" => rule}, socket) do
    rule_atom = String.to_atom(rule)

    {:noreply,
     socket
     |> assign(:active_rule, rule_atom)
     |> assign(:generation, 0)
     |> assign(:pattern_buffer, [])}
  end

  @impl true
  def handle_event("adjust_speed", %{"speed" => speed}, socket) do
    speed_value = String.to_integer(speed)
    {:noreply, assign(socket, :speed, speed_value)}
  end

  @impl true
  def handle_info(:next_generation, socket) do
    if socket.assigns.running do
      new_generation = socket.assigns.generation + 1

      new_pattern =
        generate_next_pattern(socket.assigns.active_rule, socket.assigns.pattern_buffer)

      # Schedule next generation
      schedule_next_generation(socket.assigns.speed)

      {:noreply,
       socket
       |> assign(:generation, new_generation)
       |> assign(:pattern_buffer, new_pattern)
       |> tap(fn _ ->
         # Update shared blackboard state for other processes / dashboards
         Blackboard.put({:automata, :latest_generation}, new_generation)
         Blackboard.put({:automata, :active_rule}, socket.assigns.active_rule)
         Blackboard.put({:automata, :density}, calculate_density(new_pattern))
       end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="automata-dashboard">
      <div class="header-section">
        <h1 class="text-3xl font-bold text-gray-900 mb-6">Cellular Automata Lab</h1>

        <div class="controls-panel bg-white rounded-lg shadow p-6 mb-6">
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <!-- Rule Selection -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Active Rule</label>
              <select
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                phx-change="change_rule"
                name="rule"
              >
                <option value="rule_30" selected={@active_rule == :rule_30}>Rule 30</option>
                <option value="rule_90" selected={@active_rule == :rule_90}>Rule 90</option>
                <option value="rule_110" selected={@active_rule == :rule_110}>Rule 110</option>
                <option value="rule_184" selected={@active_rule == :rule_184}>Rule 184</option>
              </select>
            </div>

    <!-- Speed Control -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Speed (ms)</label>
              <input
                type="range"
                min="10"
                max="1000"
                value={@speed}
                class="w-full"
                phx-change="adjust_speed"
                name="speed"
              />
              <span class="text-sm text-gray-500">{@speed}ms</span>
            </div>

    <!-- Generation Counter -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Generation</label>
              <div class="text-2xl font-mono text-blue-600">{@generation}</div>
            </div>

    <!-- Control Buttons -->
            <div class="flex space-x-2">
              <button
                phx-click="toggle_simulation"
                class={"px-4 py-2 rounded-md font-medium text-white #{if @running, do: "bg-red-500 hover:bg-red-600", else: "bg-green-500 hover:bg-green-600"}"}
              >
                {if @running, do: "Stop", else: "Start"}
              </button>
              <button
                phx-click="reset_simulation"
                class="px-4 py-2 bg-gray-500 hover:bg-gray-600 text-white rounded-md font-medium"
              >
                Reset
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Main Visualization -->
        <div class="lg:col-span-2">
          <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Pattern Evolution</h2>
            <div class="automata-canvas bg-black rounded border-2 border-gray-300 p-4">
              <!-- Canvas will be rendered here -->
              <div class="pattern-display font-mono text-green-400 text-xs leading-none">
                <%= for {row, idx} <- Enum.with_index(Enum.take(@pattern_buffer, -50)) do %>
                  <div class="pattern-row">
                    <span class="generation-num text-gray-500 mr-2">
                      {String.pad_leading("#{length(@pattern_buffer) - 50 + idx}", 3, "0")}
                    </span>
                    <%= for cell <- row do %>
                      <span class={if cell == 1, do: "text-green-400", else: "text-gray-800"}>
                        {if cell == 1, do: "█", else: "·"}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

    <!-- Stats and Info -->
        <div class="space-y-6">
          <!-- Current State -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Current State</h3>
            <div class="space-y-3">
              <div class="flex justify-between">
                <span class="text-gray-600">Rule:</span>
                <span class="font-mono text-blue-600">{@active_rule}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Generation:</span>
                <span class="font-mono text-green-600">{@generation}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Status:</span>
                <span class={"font-medium #{if @running, do: "text-green-600", else: "text-gray-500"}"}>
                  {if @running, do: "Running", else: "Stopped"}
                </span>
              </div>
            </div>
          </div>

    <!-- Automata Metrics -->
          <%= if @automata_state != %{} do %>
            <div class="bg-white rounded-lg shadow p-6">
              <h3 class="text-lg font-semibold text-gray-800 mb-4">System Metrics</h3>
              <div class="space-y-3">
                <%= if cellular_automata = Map.get(@automata_state, :cellular_automata) do %>
                  <div>
                    <div class="text-sm text-gray-600">Active Rules</div>
                    <div class="text-sm font-mono text-blue-600">
                      {Enum.join(Map.get(cellular_automata, :active_rules, []), ", ")}
                    </div>
                  </div>
                  <div>
                    <div class="text-sm text-gray-600">Complexity</div>
                    <div class="text-sm font-mono text-purple-600">
                      {Map.get(cellular_automata, :complexity_measure, 0)
                      |> :erlang.float_to_binary(decimals: 3)}
                    </div>
                  </div>
                <% end %>

                <%= if neural_ca = Map.get(@automata_state, :neural_ca) do %>
                  <div>
                    <div class="text-sm text-gray-600">Learning Rate</div>
                    <div class="text-sm font-mono text-orange-600">
                      {Map.get(neural_ca, :learning_rate, 0) |> :erlang.float_to_binary(decimals: 4)}
                    </div>
                  </div>
                  <div>
                    <div class="text-sm text-gray-600">Convergence</div>
                    <div class="text-sm font-mono text-green-600">
                      {Map.get(neural_ca, :convergence, 0) |> :erlang.float_to_binary(decimals: 3)}
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

    <!-- Pattern Analysis -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Pattern Analysis</h3>
            <div class="space-y-3">
              <div class="flex justify-between">
                <span class="text-gray-600">Buffer Size:</span>
                <span class="font-mono text-gray-900">{length(@pattern_buffer)}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Pattern Width:</span>
                <span class="font-mono text-gray-900">
                  {if length(@pattern_buffer) > 0, do: length(hd(@pattern_buffer)), else: 0}
                </span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Density:</span>
                <span class="font-mono text-blue-600">
                  {calculate_density(@pattern_buffer) |> :erlang.float_to_binary(decimals: 3)}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## Private Functions

  defp load_automata_state do
    case DashboardMetrics.automata_state() do
      state when is_map(state) -> state
      _ -> %{}
    end
  end

  defp schedule_next_generation(delay \\ 100) do
    Process.send_after(self(), :next_generation, delay)
  end

  defp generate_next_pattern(rule, pattern_buffer) when length(pattern_buffer) == 0 do
    # Initialize with a single central cell
    initial_width = 80
    center = div(initial_width, 2)

    initial_row =
      0..(initial_width - 1)
      |> Enum.map(fn i -> if i == center, do: 1, else: 0 end)

    [initial_row]
  end

  defp generate_next_pattern(rule, pattern_buffer) when length(pattern_buffer) > 0 do
    last_row = List.last(pattern_buffer)
    new_row = apply_ca_rule(rule, last_row)

    # Keep only the last 100 generations for memory efficiency
    updated_buffer =
      if length(pattern_buffer) >= 100 do
        tl(pattern_buffer) ++ [new_row]
      else
        pattern_buffer ++ [new_row]
      end

    updated_buffer
  end

  defp apply_ca_rule(rule, row) do
    width = length(row)

    0..(width - 1)
    |> Enum.map(fn i ->
      left = Enum.at(row, rem(i - 1 + width, width))
      center = Enum.at(row, i)
      right = Enum.at(row, rem(i + 1, width))

      apply_rule_logic(rule, {left, center, right})
    end)
  end

  defp apply_rule_logic(:rule_30, {left, center, right}) do
    # Rule 30: 00110010 in binary
    case {left, center, right} do
      {1, 1, 1} -> 0
      {1, 1, 0} -> 0
      {1, 0, 1} -> 0
      {1, 0, 0} -> 1
      {0, 1, 1} -> 1
      {0, 1, 0} -> 1
      {0, 0, 1} -> 1
      {0, 0, 0} -> 0
    end
  end

  defp apply_rule_logic(:rule_90, {left, center, right}) do
    # Rule 90: XOR rule
    case {left, center, right} do
      {1, 1, 1} -> 0
      {1, 1, 0} -> 1
      {1, 0, 1} -> 0
      {1, 0, 0} -> 1
      {0, 1, 1} -> 1
      {0, 1, 0} -> 0
      {0, 0, 1} -> 1
      {0, 0, 0} -> 0
    end
  end

  defp apply_rule_logic(:rule_110, {left, center, right}) do
    # Rule 110: Famous Turing-complete rule
    case {left, center, right} do
      {1, 1, 1} -> 0
      {1, 1, 0} -> 1
      {1, 0, 1} -> 1
      {1, 0, 0} -> 0
      {0, 1, 1} -> 1
      {0, 1, 0} -> 1
      {0, 0, 1} -> 1
      {0, 0, 0} -> 0
    end
  end

  defp apply_rule_logic(:rule_184, {left, center, right}) do
    # Rule 184: Traffic flow model
    case {left, center, right} do
      {1, 1, 1} -> 1
      {1, 1, 0} -> 0
      {1, 0, 1} -> 1
      {1, 0, 0} -> 1
      {0, 1, 1} -> 1
      {0, 1, 0} -> 0
      {0, 0, 1} -> 0
      {0, 0, 0} -> 0
    end
  end

  # Default fallback
  defp apply_rule_logic(_, _), do: 0

  defp calculate_density([]), do: 0.0

  defp calculate_density(pattern_buffer) do
    total_cells =
      pattern_buffer
      |> Enum.map(&length/1)
      |> Enum.sum()

    if total_cells == 0 do
      0.0
    else
      alive_cells =
        pattern_buffer
        |> List.flatten()
        |> Enum.sum()

      alive_cells / total_cells
    end
  end
end
