defmodule Thunderline.ErlangBridge do
  @moduledoc """
  Bridge module for integrating Elixir Thunderline platform with Erlang CA system.

  This module provides:
  - Real-time communication with Erlang ThunderBolt/ThunderBit modules
  - Event streaming and subscription management
  - Command interface for CA control operations
  - Data transformation between Erlang and Elixir formats

  ## Usage

      # Start the bridge
      {:ok, pid} = ErlangBridge.start_link()

      # Get system state
      {:ok, state} = ErlangBridge.get_system_state()

      # Subscribe to events
      :ok = ErlangBridge.subscribe_events(self())

      # Send commands
      :ok = ErlangBridge.execute_command(:start_evolution, bolt_id)
  """

  use GenServer
  require Logger

  alias Thunderline.EventBus

  # Client API

  @doc "Start the Erlang bridge GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Backward Compatibility Layer (Legacy Test & API Expectations)
  # These wrappers map old function names (still referenced in tests/docs)
  # to the new, explicit API. Marked @deprecated so callers can migrate.
  # ---------------------------------------------------------------------------

  @deprecated "Use get_system_state/0 or get_node_status/0 instead"
  def get_status do
    with {:ok, state} <- get_system_state() do
      state
    end
  end

  @deprecated "Use create_thunderbolt_stream/2 instead"
  def start_thunderbolt_streaming(bolt_id), do: create_thunderbolt_stream(bolt_id, %{})

  @deprecated "Use start_thunderbolt_evolution/2 instead"
  def evolve_thunderbolt(bolt_id, evolution_params \\ %{}),
    do: start_thunderbolt_evolution(bolt_id, evolution_params)

  @deprecated "Use execute_command(:destroy_thunderbolt, [bolt_id]) or direct registry call"
  def destroy_thunderbolt(bolt_id) do
    case execute_command(:destroy_thunderbolt, [bolt_id]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @deprecated "Use apply_neural_connections/2 instead"
  def inject_neural_patterns(bolt_id, connections),
    do: apply_neural_connections(bolt_id, connections)

  @doc "Create a new ThunderBolt cube using Erlang team's API"
  def create_thunderbolt(bolt_config) do
    GenServer.call(__MODULE__, {:create_thunderbolt, bolt_config}, 5000)
  end

  @doc "Get ThunderBolt state snapshot using their streaming API"
  def get_thunderbolt_snapshot(bolt_id) do
    GenServer.call(__MODULE__, {:get_thunderbolt_snapshot, bolt_id}, 5000)
  end

  @doc "Start evolution control on a ThunderBolt"
  def start_thunderbolt_evolution(bolt_id, evolution_config \\ %{}) do
    GenServer.call(__MODULE__, {:start_evolution, bolt_id, evolution_config}, 5000)
  end

  @doc "Create real-time stream using Erlang team's thunderbolt_stream.erl"
  def create_thunderbolt_stream(bolt_id, stream_config) do
    GenServer.call(__MODULE__, {:create_stream, bolt_id, stream_config}, 5000)
  end

  @doc "Inject neural patterns into ThunderBolt using their pattern injection API"
  def inject_neural_pattern(bolt_id, pattern_type, coords, pattern_data) do
    GenServer.call(
      __MODULE__,
      {:inject_pattern, bolt_id, pattern_type, coords, pattern_data},
      5000
    )
  end

  @doc "Connect to Cerebros neural architecture (for neural integration)"
  def connect_cerebros(config) do
    GenServer.call(__MODULE__, {:connect_cerebros, config}, 5000)
  end

  @doc "Apply neural connections to ThunderBolt via Cerebros integration"
  def apply_neural_connections(bolt_id, connections) do
    GenServer.call(__MODULE__, {:apply_neural_connections, bolt_id, connections}, 5000)
  end

  @doc "Get current system state from Erlang CA modules"
  def get_system_state do
    GenServer.call(__MODULE__, :get_system_state, 5000)
  end

  @doc "Get ThunderBolt registry information using their completed registry API"
  def get_thunderbolt_registry do
    GenServer.call(__MODULE__, :get_thunderbolt_registry, 5000)
  end

  @doc "Get ThunderBit observer data using their observer module"
  def get_thunderbit_data do
    GenServer.call(__MODULE__, :get_thunderbit_data, 5000)
  end

  @doc "Get current node status for topology distribution"
  def get_node_status do
    GenServer.call(__MODULE__, :get_node_status, 5000)
  end

  @doc "Get aggregated metrics from Erlang CA system"
  def get_aggregated_metrics do
    GenServer.call(__MODULE__, :get_aggregated_metrics, 5000)
  end

  @doc "Deploy ruleset to Thundercell nodes"
  def deploy_ruleset(ruleset) do
    GenServer.call(__MODULE__, {:deploy_ruleset, ruleset}, 5000)
  end

  @doc "Start cluster with configuration"
  def start_cluster(cluster_config) do
    GenServer.call(__MODULE__, {:start_cluster, cluster_config}, 5000)
  end

  @doc "Execute a command on the Erlang CA system"
  def execute_command(command, params \\ []) do
    GenServer.call(__MODULE__, {:execute_command, command, params}, 5000)
  end

  @doc "Subscribe to real-time events from Erlang system"
  def subscribe_events(subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe_events, subscriber_pid})
  end

  @doc "Start streaming CA data to dashboard"
  def start_streaming(opts \\ []) do
    GenServer.call(__MODULE__, {:start_streaming, opts})
  end

  @doc "Stop streaming CA data"
  def stop_streaming do
    GenServer.call(__MODULE__, :stop_streaming)
  end

  @doc "Pause lane processing on a specific node"
  def pause_lane_processing(node, lane_dimension) do
    GenServer.call(__MODULE__, {:pause_lane_processing, node, lane_dimension}, 5000)
  end

  # ============================================================================
  # Cerebros Neural API - New neural functionality from Erlang team
  # ============================================================================

  @doc "Create neural architecture for a ThunderBolt using Cerebros-style connectivity"
  def create_neural_architecture(bolt_id, config) do
    GenServer.call(__MODULE__, {:create_neural_architecture, bolt_id, config}, 5000)
  end

  @doc "Create neural level from a ThunderBolt"
  def create_neural_level(bolt_id, level_number, config) do
    GenServer.call(__MODULE__, {:create_neural_level, bolt_id, level_number, config}, 5000)
  end

  @doc "Create connection between neural levels"
  def create_neural_connection(source_level, target_level, config) do
    GenServer.call(
      __MODULE__,
      {:create_neural_connection, source_level, target_level, config},
      5000
    )
  end

  @doc "Create skip connection (bypass layers) - Cerebros feature"
  def create_skip_connection(source_level, target_level, skip_depth, config) do
    GenServer.call(
      __MODULE__,
      {:create_skip_connection, source_level, target_level, skip_depth, config},
      5000
    )
  end

  @doc "Propagate neural signal through the network"
  def propagate_neural_signal(source_level, signal, timestamp) do
    GenServer.cast(__MODULE__, {:propagate_neural_signal, source_level, signal, timestamp})
  end

  @doc "Get current neural topology"
  def get_neural_topology do
    GenServer.call(__MODULE__, :get_neural_topology, 5000)
  end

  @doc "Optimize neural connectivity patterns"
  def optimize_connectivity(strategy) do
    GenServer.call(__MODULE__, {:optimize_connectivity, strategy}, 5000)
  end

  # Non-Ising GA evolution is gated behind a compile-time flag to keep Ising-only focus by default
  if Application.compile_env(:thunderline, [:thunderbolt, :enable_non_ising], false) do
    @doc "Evolve neural architecture using genetic algorithms"
    def evolve_architecture(generations, fitness_function) do
      GenServer.call(__MODULE__, {:evolve_architecture, generations, fitness_function}, 10000)
    end
  else
    @doc "Evolve neural architecture using genetic algorithms (disabled: non-Ising path)"
    @deprecated "Non-Ising evolution is disabled unless :thunderbolt.enable_non_ising=true"
    def evolve_architecture(_generations, _fitness_function), do: {:error, :feature_disabled}
  end

  # ============================================================================
  # ThunderBit Neuron API - Individual cell neural behavior
  # ============================================================================

  @doc "Create a neuron from a ThunderBit cell"
  def create_neuron(bolt_id, coordinates, config) do
    GenServer.call(__MODULE__, {:create_neuron, bolt_id, coordinates, config}, 5000)
  end

  @doc "Connect two neurons with a synapse"
  def connect_neurons(source_neuron, target_neuron, synapse_config) do
    GenServer.call(
      __MODULE__,
      {:connect_neurons, source_neuron, target_neuron, synapse_config},
      5000
    )
  end

  @doc "Fire a neuron (generate action potential)"
  def fire_neuron(neuron_id, intensity) do
    GenServer.cast(__MODULE__, {:fire_neuron, neuron_id, intensity})
  end

  @doc "Get current state of a neuron"
  def get_neuron_state(neuron_id) do
    GenServer.call(__MODULE__, {:get_neuron_state, neuron_id}, 5000)
  end

  @doc "Enable spike-timing dependent plasticity"
  def enable_spike_timing_plasticity(neuron_id) do
    GenServer.call(__MODULE__, {:enable_stdp, neuron_id}, 5000)
  end

  @doc "Get neural network topology for a ThunderBolt"
  def get_neuron_network(bolt_id) do
    GenServer.call(__MODULE__, {:get_neuron_network, bolt_id}, 5000)
  end

  @doc "Simulate one neural time step"
  def simulate_neural_step(bolt_id) do
    GenServer.cast(__MODULE__, {:simulate_neural_step, bolt_id})
  end

  # ============================================================================
  # Multi-Scale Neural Processing API - Hierarchical computation
  # ============================================================================

  @doc "Create scale hierarchy for multi-scale neural processing"
  def create_scale_hierarchy(bolt_id, config) do
    GenServer.call(__MODULE__, {:create_scale_hierarchy, bolt_id, config}, 5000)
  end

  @doc "Process information across all scales"
  def process_across_scales(hierarchy_id, input_data) do
    GenServer.call(__MODULE__, {:process_across_scales, hierarchy_id, input_data}, 5000)
  end

  @doc "Get representation at a specific scale"
  def get_scale_representation(hierarchy_id, scale_level) do
    GenServer.call(__MODULE__, {:get_scale_representation, hierarchy_id, scale_level}, 5000)
  end

  @doc "Propagate information upward (to coarser scales)"
  def propagate_upward(hierarchy_id, source_scale, data) do
    GenServer.cast(__MODULE__, {:propagate_upward, hierarchy_id, source_scale, data})
  end

  @doc "Propagate information downward (to finer scales)"
  def propagate_downward(hierarchy_id, source_scale, data) do
    GenServer.cast(__MODULE__, {:propagate_downward, hierarchy_id, source_scale, data})
  end

  @doc "Add a new scale level to hierarchy"
  def add_scale_level(hierarchy_id, scale_factor, config) do
    GenServer.call(__MODULE__, {:add_scale_level, hierarchy_id, scale_factor, config}, 5000)
  end

  @doc "Get information about scale hierarchy"
  def get_hierarchy_info(hierarchy_id) do
    GenServer.call(__MODULE__, {:get_hierarchy_info, hierarchy_id}, 5000)
  end

  @doc "Enable cross-scale learning"
  def enable_cross_scale_learning(hierarchy_id) do
    GenServer.call(__MODULE__, {:enable_cross_scale_learning, hierarchy_id}, 5000)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting Erlang Bridge...")

    state = %{
      erlang_connected: false,
      subscribers: MapSet.new(),
      streaming: false,
      stream_timer: nil,
      last_state: %{},
      opts: opts
    }

    # Attempt to connect to Erlang system
    send(self(), :connect_erlang)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_system_state, _from, state) do
    case get_erlang_system_state() do
      {:ok, system_state} ->
        {:reply, {:ok, system_state}, %{state | last_state: system_state}}

      {:error, reason} ->
        Logger.warning("Failed to get Erlang system state: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_thunderbolt_registry, _from, state) do
    case call_erlang_safe(:thunderbolt_registry, :list_thunderbolts, []) do
      {:ok, thunderbolts} ->
        formatted_bolts = format_thunderbolts(thunderbolts)
        {:reply, {:ok, formatted_bolts}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_thunderbit_data, _from, state) do
    case call_erlang_safe(:thunderbit_observer, :get_current_state, []) do
      {:ok, bit_data} ->
        formatted_data = format_thunderbit_data(bit_data)
        {:reply, {:ok, formatted_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_node_status, _from, state) do
    case get_thundercell_node_status() do
      {:ok, node_status} ->
        {:reply, {:ok, node_status}, state}

      {:error, reason} ->
        Logger.warning("Failed to get node status: #{inspect(reason)}")
        {:reply, {:error, :node_status_unavailable}, state}
    end
  end

  def handle_call(:get_aggregated_metrics, _from, state) do
    case get_thundercell_aggregated_metrics() do
      {:ok, metrics} ->
        {:reply, {:ok, metrics}, state}

      {:error, reason} ->
        Logger.warning("Failed to get aggregated metrics: #{inspect(reason)}")
        {:reply, {:error, :metrics_unavailable}, state}
    end
  end

  def handle_call({:deploy_ruleset, ruleset}, _from, state) do
    case call_erlang_safe(:thundercell_deployer, :deploy_ruleset, [ruleset]) do
      {:ok, deployment_result} ->
        {:reply, {:ok, deployment_result}, state}

      {:error, reason} ->
        Logger.warning("Failed to deploy ruleset: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_cluster, cluster_config}, _from, state) do
    case start_thundercell_cluster(cluster_config) do
      {:ok, cluster_result} ->
        {:reply, {:ok, cluster_result}, state}

      {:error, reason} ->
        Logger.warning("Failed to start cluster: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:execute_command, command, params}, _from, state) do
    result = execute_erlang_command(command, params)

    # Publish command execution event (general pipeline)
    publish_bridge_event("erlang_commands", :erlang_command_executed, %{
      command: command,
      params: params,
      result: result
    })

    {:reply, result, state}
  end

  def handle_call({:subscribe_events, subscriber_pid}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, subscriber_pid)
    Process.monitor(subscriber_pid)
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  def handle_call({:create_thunderbolt, bolt_config}, _from, state) do
    # Use Erlang team's thunderbolt_registry:create_thunderbolt/2
    case :rpc.call(state.erlang_node, :thunderbolt_registry, :create_thunderbolt, [
           bolt_config.bolt_id,
           %{
             dimensions: bolt_config.dimensions || {32, 32, 32},
             rules: bolt_config.rules || :conway,
             initial_pattern: bolt_config.initial_pattern || :random
           }
         ]) do
      {:ok, bolt_pid} ->
        Logger.info("✅ Created ThunderBolt #{bolt_config.bolt_id}")
        {:reply, {:ok, %{bolt_id: bolt_config.bolt_id, pid: bolt_pid}}, state}

      {:error, reason} ->
        Logger.error("❌ Failed to create ThunderBolt: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_thunderbolt_snapshot, bolt_id}, _from, state) do
    # Use Erlang team's thunderbolt_state:get_bolt_snapshot/1
    case :rpc.call(state.erlang_node, :thunderbolt_state, :get_bolt_snapshot, [bolt_id]) do
      snapshot when is_map(snapshot) ->
        Logger.debug("📸 Got ThunderBolt snapshot for #{bolt_id}")
        {:reply, {:ok, snapshot}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_evolution, bolt_id, evolution_config}, _from, state) do
    # Use Erlang team's thunderbolt_evolution:start_evolution/1
    case :rpc.call(state.erlang_node, :thunderbolt_evolution, :start_evolution, [bolt_id]) do
      :ok ->
        # Also set evolution speed if provided
        if Map.has_key?(evolution_config, :generations_per_second) do
          :rpc.call(state.erlang_node, :thunderbolt_evolution, :set_evolution_speed, [
            bolt_id,
            evolution_config.generations_per_second
          ])
        end

        Logger.info("🚀 Started evolution for ThunderBolt #{bolt_id}")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_stream, bolt_id, stream_config}, _from, state) do
    # Use Erlang team's thunderbolt_stream:create_stream_subscription/2
    erlang_stream_config = %{
      quality: Map.get(stream_config, :quality, :medium),
      max_fps: Map.get(stream_config, :max_fps, 30),
      slice_axis: Map.get(stream_config, :slice_axis, :auto),
      compression: Map.get(stream_config, :compression, :lz4)
    }

    case :rpc.call(state.erlang_node, :thunderbolt_stream, :create_stream_subscription, [
           bolt_id,
           erlang_stream_config
         ]) do
      {:ok, stream_id} ->
        Logger.info("📡 Created stream #{stream_id} for ThunderBolt #{bolt_id}")
        {:reply, {:ok, %{stream_id: stream_id, bolt_id: bolt_id}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:inject_pattern, bolt_id, pattern_type, coords, pattern_data}, _from, state) do
    # Use Erlang team's thunderbolt_evolution:inject_pattern/4
    case :rpc.call(state.erlang_node, :thunderbolt_evolution, :inject_pattern, [
           bolt_id,
           pattern_type,
           coords,
           pattern_data
         ]) do
      :ok ->
        Logger.info("🧬 Injected #{pattern_type} pattern into ThunderBolt #{bolt_id}")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:connect_cerebros, _config}, _from, state) do
    # For now, return success with mock Cerebros topology
    # In the future, this would connect to actual Cerebros neural architecture
    mock_topology = %{
      levels: [:micro, :meso, :macro],
      connections: [
        %{from: :micro, to: :meso, strength: 0.7, delay: 2},
        %{from: :meso, to: :macro, strength: 0.5, delay: 3},
        %{from: :macro, to: :micro, strength: 0.3, delay: 1}
      ],
      neural_units: 1000,
      skip_connections: 50
    }

    Logger.info("🧠 Connected to Cerebros neural architecture (mock)")
    {:reply, {:ok, mock_topology}, state}
  end

  def handle_call({:apply_neural_connections, bolt_id, connections}, _from, state) do
    # Apply neural connections to ThunderBolt via pattern injection
    # Convert neural connections to CA patterns
    patterns = convert_neural_connections_to_patterns(connections)

    results =
      for pattern <- patterns do
        :rpc.call(state.erlang_node, :thunderbolt_evolution, :inject_pattern, [
          bolt_id,
          :neural_connection,
          pattern.coords,
          pattern.data
        ])
      end

    case Enum.all?(results, &(&1 == :ok)) do
      true ->
        Logger.info("🔗 Applied #{length(patterns)} neural connections to ThunderBolt #{bolt_id}")
        {:reply, :ok, state}

      false ->
        failed_patterns = Enum.count(results, &(&1 != :ok))
        Logger.warning("⚠️ Failed to apply #{failed_patterns} neural connections")

        {:reply,
         {:partial_success,
          %{applied: length(patterns) - failed_patterns, failed: failed_patterns}}, state}
    end
  end

  def handle_call({:start_streaming, opts}, _from, state) do
    if state.streaming do
      {:reply, {:error, :already_streaming}, state}
    else
      interval = Keyword.get(opts, :interval, 1000)
      timer = Process.send_after(self(), :stream_update, interval)

      Logger.info("Started Erlang CA streaming with #{interval}ms interval")
      {:reply, :ok, %{state | streaming: true, stream_timer: timer}}
    end
  end

  def handle_call(:stop_streaming, _from, state) do
    if state.stream_timer do
      Process.cancel_timer(state.stream_timer)
    end

    Logger.info("Stopped Erlang CA streaming")
    {:reply, :ok, %{state | streaming: false, stream_timer: nil}}
  end

  def handle_call({:pause_lane_processing, node, lane_dimension}, _from, state) do
    case pause_thundercell_lane(node, lane_dimension) do
      :ok ->
        Logger.info("Paused lane processing on node #{node} for dimension #{lane_dimension}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning("Failed to pause lane processing: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Neural API Handlers - Cerebros-style functionality
  # ============================================================================

  def handle_call({:create_neural_architecture, bolt_id, config}, _from, state) do
    case call_erlang_safe(:thunderbolt_neural, :create_neural_level, [bolt_id, 1, config]) do
      {:ok, level_id} ->
        Logger.info("🧠 Created neural architecture for bolt #{bolt_id}")
        {:reply, {:ok, level_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_neural_level, bolt_id, level_number, config}, _from, state) do
    case call_erlang_safe(:thunderbolt_neural, :create_neural_level, [
           bolt_id,
           level_number,
           config
         ]) do
      {:ok, level_id} ->
        Logger.info("🧠 Created neural level #{level_number} for bolt #{bolt_id}")
        {:reply, {:ok, level_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_neural_connection, source_level, target_level, config}, _from, state) do
    case call_erlang_safe(:thunderbolt_neural, :create_neural_connection, [
           source_level,
           target_level,
           config
         ]) do
      {:ok, connection_id} ->
        Logger.info("🔗 Created neural connection #{source_level} -> #{target_level}")
        {:reply, {:ok, connection_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:create_skip_connection, source_level, target_level, skip_depth, config},
        _from,
        state
      ) do
    case call_erlang_safe(:thunderbolt_neural, :create_skip_connection, [
           source_level,
           target_level,
           skip_depth,
           config
         ]) do
      {:ok, connection_id} ->
        Logger.info(
          "🔗 Created skip connection #{source_level} -> #{target_level} (depth: #{skip_depth})"
        )

        {:reply, {:ok, connection_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_neural_topology, _from, state) do
    case call_erlang_safe(:thunderbolt_neural, :get_neural_topology, []) do
      {:ok, topology} ->
        {:reply, {:ok, topology}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:optimize_connectivity, strategy}, _from, state) do
    case call_erlang_safe(:thunderbolt_neural, :optimize_connectivity, [strategy]) do
      {:ok, _} ->
        Logger.info("🧠 Optimized neural connectivity using strategy: #{strategy}")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:evolve_architecture, generations, fitness_function}, _from, state) do
    case call_erlang_safe(:thunderbolt_neural, :evolve_architecture, [
           generations,
           fitness_function
         ]) do
      {:ok, best_architecture} ->
        Logger.info("🧬 Evolved neural architecture over #{generations} generations")
        {:reply, {:ok, best_architecture}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ThunderBit Neuron API Handlers

  def handle_call({:create_neuron, bolt_id, coordinates, config}, _from, state) do
    case call_erlang_safe(:thunderbit_neuron, :create_neuron, [bolt_id, coordinates, config]) do
      {:ok, neuron_id} ->
        Logger.info("🧠 Created neuron #{neuron_id} at #{inspect(coordinates)}")
        {:reply, {:ok, neuron_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:connect_neurons, source_neuron, target_neuron, synapse_config}, _from, state) do
    case call_erlang_safe(:thunderbit_neuron, :connect_neurons, [
           source_neuron,
           target_neuron,
           synapse_config
         ]) do
      {:ok, synapse_id} ->
        Logger.info("🔗 Connected neurons #{source_neuron} -> #{target_neuron}")
        {:reply, {:ok, synapse_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_neuron_state, neuron_id}, _from, state) do
    case call_erlang_safe(:thunderbit_neuron, :get_neuron_state, [neuron_id]) do
      {:ok, neuron_state} ->
        {:reply, {:ok, neuron_state}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:enable_stdp, neuron_id}, _from, state) do
    case call_erlang_safe(:thunderbit_neuron, :enable_spike_timing_plasticity, [neuron_id]) do
      {:ok, _} ->
        Logger.info("🧠 Enabled STDP for neuron #{neuron_id}")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_neuron_network, bolt_id}, _from, state) do
    case call_erlang_safe(:thunderbit_neuron, :get_neuron_network, [bolt_id]) do
      {:ok, network} ->
        {:reply, {:ok, network}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Multi-Scale Processing API Handlers

  def handle_call({:create_scale_hierarchy, bolt_id, config}, _from, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :create_scale_hierarchy, [bolt_id, config]) do
      {:ok, hierarchy_id} ->
        Logger.info("🏗️ Created scale hierarchy #{hierarchy_id} for bolt #{bolt_id}")
        {:reply, {:ok, hierarchy_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:process_across_scales, hierarchy_id, input_data}, _from, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :process_across_scales, [
           hierarchy_id,
           input_data
         ]) do
      {:ok, processed_data} ->
        {:reply, {:ok, processed_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_scale_representation, hierarchy_id, scale_level}, _from, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :get_scale_representation, [
           hierarchy_id,
           scale_level
         ]) do
      {:ok, representation} ->
        {:reply, {:ok, representation}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_scale_level, hierarchy_id, scale_factor, config}, _from, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :add_scale_level, [
           hierarchy_id,
           scale_factor,
           config
         ]) do
      {:ok, level_id} ->
        Logger.info("🏗️ Added scale level #{scale_factor} to hierarchy #{hierarchy_id}")
        {:reply, {:ok, level_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_hierarchy_info, hierarchy_id}, _from, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :get_hierarchy_info, [hierarchy_id]) do
      {:ok, info} ->
        {:reply, {:ok, info}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:enable_cross_scale_learning, hierarchy_id}, _from, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :enable_cross_scale_learning, [hierarchy_id]) do
      {:ok, _} ->
        Logger.info("🏗️ Enabled cross-scale learning for hierarchy #{hierarchy_id}")
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Cast Handlers - Asynchronous neural operations
  # ============================================================================

  @impl true
  def handle_cast({:propagate_neural_signal, source_level, signal, timestamp}, state) do
    case call_erlang_safe(:thunderbolt_neural, :propagate_neural_signal, [
           source_level,
           signal,
           timestamp
         ]) do
      {:ok, _} ->
        Logger.debug("🔄 Propagated neural signal from level #{source_level}")

      {:error, reason} ->
        Logger.warning("Failed to propagate neural signal: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_cast({:fire_neuron, neuron_id, intensity}, state) do
    case call_erlang_safe(:thunderbit_neuron, :fire_neuron, [neuron_id, intensity]) do
      {:ok, _} ->
        Logger.debug("⚡ Fired neuron #{neuron_id} with intensity #{intensity}")

      {:error, reason} ->
        Logger.warning("Failed to fire neuron: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_cast({:simulate_neural_step, bolt_id}, state) do
    case call_erlang_safe(:thunderbit_neuron, :simulate_neural_step, [bolt_id]) do
      {:ok, _} ->
        Logger.debug("🧠 Simulated neural step for bolt #{bolt_id}")

      {:error, reason} ->
        Logger.warning("Failed to simulate neural step: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_cast({:propagate_upward, hierarchy_id, source_scale, data}, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :propagate_upward, [
           hierarchy_id,
           source_scale,
           data
         ]) do
      {:ok, _} ->
        Logger.debug("🔼 Propagated upward from scale #{source_scale}")

      {:error, reason} ->
        Logger.warning("Failed upward propagation: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_cast({:propagate_downward, hierarchy_id, source_scale, data}, state) do
    case call_erlang_safe(:thunderbolt_multiscale, :propagate_downward, [
           hierarchy_id,
           source_scale,
           data
         ]) do
      {:ok, _} ->
        Logger.debug("🔽 Propagated downward from scale #{source_scale}")

      {:error, reason} ->
        Logger.warning("Failed downward propagation: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:connect_erlang, state) do
    case connect_to_erlang() do
      :ok ->
        Logger.info("Successfully connected to Erlang CA system")
        {:noreply, %{state | erlang_connected: true}}

      # Removed unreachable :erlang_modules_unavailable clause

      {:error, reason} ->
        Logger.warning("Failed to connect to Erlang: #{inspect(reason)}")
        # Retry connection in 5 seconds for other errors
        Process.send_after(self(), :connect_erlang, 5000)
        {:noreply, state}
    end
  end

  def handle_info(:stream_update, %{streaming: true} = state) do
    # Get current state and broadcast to subscribers
    case get_erlang_system_state() do
      {:ok, new_state} ->
        # Check for changes and broadcast
        if new_state != state.last_state do
          broadcast_to_subscribers(state.subscribers, {:erlang_state_update, new_state})

          # Also broadcast to EventBus for dashboard
          publish_bridge_event("system_metrics", :system_metrics, new_state)
        end

        # Schedule next update
        timer = Process.send_after(self(), :stream_update, 1000)
        {:noreply, %{state | stream_timer: timer, last_state: new_state}}

      {:error, reason} ->
        Logger.warning("Stream update failed: #{inspect(reason)}")
        timer = Process.send_after(self(), :stream_update, 2000)
        {:noreply, %{state | stream_timer: timer}}
    end
  end

  def handle_info(:stream_update, state) do
    # Streaming is disabled, don't schedule next update
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  def handle_info(msg, state) do
    Logger.debug("Unknown message in ErlangBridge: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp publish_bridge_event(topic, type, payload) do
    attrs = %{
      name: "system.bridge." <> Atom.to_string(type),
      type: type,
      source: :bridge,
      payload: Map.merge(payload, %{topic: topic, timestamp: DateTime.utc_now()}),
      meta: %{pipeline: infer_pipeline_from_topic(topic)}
    }

    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[ErlangBridge] publish failed: #{inspect(reason)} topic=#{topic} type=#{type}"
          )
      end
    end
  end

  defp infer_pipeline_from_topic(topic) do
    cond do
      String.contains?(topic, "agent") or String.contains?(topic, "live") -> :realtime
      String.contains?(topic, "domain") -> :cross_domain
      true -> :general
    end
  end

  defp connect_to_erlang do
    # Check if ThunderCell Elixir modules are available
    case check_thundercell_availability() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_erlang_system_state do
    try do
      # Collect data from ThunderCell Elixir modules
      bridge_data = get_thundercell_bridge_data()
      cluster_data = get_thundercell_cluster_data()
      telemetry_data = get_thundercell_telemetry_data()

      system_state = %{
        timestamp: DateTime.utc_now(),
        thundercell_bridge: format_result(bridge_data),
        thundercell_cluster: format_result(cluster_data),
        thundercell_telemetry: format_result(telemetry_data),
        connection_status: :connected
      }

      {:ok, system_state}
    rescue
      error ->
        Logger.error("Error getting ThunderCell system state: #{inspect(error)}")
        {:error, error}
    end
  end

  defp call_erlang_safe(module, function, args) do
    try do
      result = apply(module, function, args)
      {:ok, result}
    rescue
      error -> {:error, error}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      error -> {:error, error}
    end
  end

  defp format_result({:ok, data}), do: data
  defp format_result({:error, _reason} = error), do: error
  defp format_result(data), do: data

  defp format_thunderbolts(thunderbolts) when is_list(thunderbolts) do
    Enum.map(thunderbolts, &format_thunderbolt/1)
  end

  defp format_thunderbolts(data), do: data

  defp format_thunderbolt({bolt_id, bolt_state}) do
    %{
      id: bolt_id,
      state: bolt_state,
      status: Map.get(bolt_state, :status, :unknown),
      energy: Map.get(bolt_state, :energy, 0),
      generation: Map.get(bolt_state, :generation, 0),
      last_update: DateTime.utc_now()
    }
  end

  defp format_thunderbit_data({:observer_state, state}) do
    %{
      active_observations: Map.get(state, :observations, 0),
      monitoring_zones: Map.get(state, :zones, []),
      data_quality: Map.get(state, :quality, 1.0),
      last_scan: DateTime.utc_now()
    }
  end

  defp format_thunderbit_data(data), do: data

  defp execute_erlang_command(:start_evolution, [bolt_id]) do
    call_erlang_safe(:thunderbolt_evolution, :start_evolution, [bolt_id])
  end

  defp execute_erlang_command(:pause_evolution, [bolt_id]) do
    call_erlang_safe(:thunderbolt_evolution, :pause_evolution, [bolt_id])
  end

  defp execute_erlang_command(:reset_evolution, [bolt_id]) do
    call_erlang_safe(:thunderbolt_evolution, :reset_evolution, [bolt_id])
  end

  defp execute_erlang_command(:create_thunderbolt, params) do
    call_erlang_safe(:thunderbolt_registry, :create_thunderbolt, params)
  end

  defp execute_erlang_command(:destroy_thunderbolt, [bolt_id]) do
    call_erlang_safe(:thunderbolt_registry, :remove_thunderbolt, [bolt_id])
  end

  defp execute_erlang_command(:start_streaming, opts) do
    call_erlang_safe(:thunderbolt_stream, :start_stream, [opts])
  end

  defp execute_erlang_command(:stop_streaming, _params) do
    call_erlang_safe(:thunderbolt_stream, :stop_stream, [])
  end

  defp execute_erlang_command(command, params) do
    Logger.warning("Unknown Erlang command: #{command} with params: #{inspect(params)}")
    {:error, :unknown_command}
  end

  defp broadcast_to_subscribers(subscribers, message) do
    Enum.each(subscribers, fn subscriber_pid ->
      send(subscriber_pid, message)
    end)
  end

  # Helper function to convert neural connections to CA patterns
  defp convert_neural_connections_to_patterns(connections) do
    connections
    |> Enum.with_index()
    |> Enum.map(fn {connection, index} ->
      # Convert neural connection to spatial CA pattern
      %{
        coords: calculate_neural_position(index, connection),
        data: %{
          strength: Map.get(connection, :strength, 0.5),
          delay: Map.get(connection, :delay, 1),
          connection_type: Map.get(connection, :connection_type, :excitatory),
          pattern_type: :neural_synapse
        }
      }
    end)
  end

  defp calculate_neural_position(index, connection) do
    # Convert neural connection index to 3D coordinates
    # This creates a spatial mapping of neural connections in the CA space
    x = rem(index, 32)
    y = div(index, 32) |> rem(32)
    z = div(index, 1024)

    # Add some randomness based on connection strength
    strength_offset = trunc(Map.get(connection, :strength, 0.5) * 10)

    {x + strength_offset, y, z}
  end

  # Add new function to get real-time ThunderBolt metrics

  # ====================================================================
  # ThunderCell Elixir Integration Functions
  # ====================================================================

  defp check_thundercell_availability do
    try do
      # Check if ThunderCell supervisor is running
      case Process.whereis(Thunderline.Thunderbolt.ThunderCell.Supervisor) do
        nil -> {:error, :thundercell_supervisor_not_running}
        _pid -> :ok
      end
    rescue
      error -> {:error, error}
    end
  end

  defp get_thundercell_bridge_data do
    try do
      case GenServer.call(Thunderline.Thunderbolt.ThunderCell.Bridge, :get_status, 1000) do
        {:ok, status} -> {:ok, status}
        error -> error
      end
    rescue
      error -> {:error, error}
    end
  end

  defp get_thundercell_cluster_data do
    try do
      clusters = Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor.list_clusters()
      {:ok, %{clusters: clusters, cluster_count: length(clusters)}}
    rescue
      error -> {:error, error}
    end
  end

  defp get_thundercell_telemetry_data do
    try do
      case Thunderline.Thunderbolt.ThunderCell.Telemetry.get_compute_metrics() do
        {:ok, metrics} -> {:ok, metrics}
        error -> error
      end
    rescue
      error -> {:error, error}
    end
  end

  defp get_thundercell_node_status do
    try do
      cluster_count = Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor.get_cluster_count()

      {:ok,
       %{
         node: Node.self(),
         cluster_count: cluster_count,
         status: :active,
         timestamp: DateTime.utc_now()
       }}
    rescue
      error -> {:error, error}
    end
  end

  defp get_thundercell_aggregated_metrics do
    try do
      case Thunderline.Thunderbolt.ThunderCell.Telemetry.get_performance_report() do
        {:ok, report} -> {:ok, report}
        error -> error
      end
    rescue
      error -> {:error, error}
    end
  end

  defp start_thundercell_cluster(cluster_config) do
    try do
      # Convert cluster config to proper format
      thundercell_config = %{
        cluster_id: Map.get(cluster_config, :cluster_id, :default_cluster),
        dimensions: Map.get(cluster_config, :dimensions, {10, 10, 10}),
        ca_rules: Map.get(cluster_config, :ca_rules, default_ca_rules()),
        evolution_interval: Map.get(cluster_config, :evolution_interval, 100)
      }

      case Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor.start_cluster(thundercell_config) do
        {:ok, pid} -> {:ok, %{cluster_id: thundercell_config.cluster_id, pid: pid}}
        error -> error
      end
    rescue
      error -> {:error, error}
    end
  end

  defp pause_thundercell_lane(_node, _lane_dimension) do
    try do
      # For now, pause all clusters on this node
      # In a full implementation, this would pause specific lane dimensions
      clusters = Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor.list_clusters()

      results =
        for cluster <- clusters do
          cluster_id = Map.get(cluster, :cluster_id)

          if cluster_id do
            Thunderline.Thunderbolt.ThunderCell.Cluster.pause_evolution(cluster_id)
          else
            :ok
          end
        end

      case Enum.all?(results, &(&1 == :ok)) do
        true -> :ok
        false -> {:error, :partial_pause}
      end
    rescue
      error -> {:error, error}
    end
  end

  defp default_ca_rules do
    %{
      name: "Conway's Game of Life 3D",
      # Neighbors needed for birth
      birth_neighbors: [5, 6, 7],
      # Neighbors needed for survival
      survival_neighbors: [4, 5, 6],
      # 26-neighbor Moore neighborhood
      neighbor_type: :moore_3d
    }
  end
end
