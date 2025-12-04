defmodule Thunderline.Thunderbolt.Cerebros.DiffLogicCA do
  @moduledoc """
  DiffLogic-Controlled Self-Optimizing Cellular Automata (HC-38).

  Integrates DiffLogic differentiable gates with Cerebros TPE optimization
  and LoopMonitor criticality metrics to create a CA that automatically
  tunes itself toward the edge of chaos.

  ## Architecture

      ┌────────────────────────────────────────────────────────────────┐
      │                     DiffLogic CA System                        │
      │                                                                │
      │  ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐   │
      │  │   DiffLogic  │ → │  CA Stepper  │ → │  LoopMonitor     │   │
      │  │   Gates      │   │  (Grid Tick) │   │  (PLV,H,λ̂,λ_L)  │   │
      │  └──────────────┘   └──────────────┘   └──────────────────┘   │
      │        ↑                                       │              │
      │        │            ┌──────────────┐           │              │
      │        └────────────│  TPE Bridge  │←──────────┘              │
      │                     │  (Optuna)    │                          │
      │                     └──────────────┘                          │
      └────────────────────────────────────────────────────────────────┘

  ## Self-Optimization Loop

  1. TPE suggests DiffLogic gate parameters (λ, bias, temperature)
  2. DiffLogicRule applies these to compute CA state transitions
  3. LoopMonitor measures criticality metrics after N ticks
  4. Edge-of-chaos score is computed and fed back to TPE
  5. TPE updates its Parzen estimators with the observation
  6. Repeat until convergence or budget exhausted

  ## Usage

      # Start self-optimizing CA
      {:ok, ca} = DiffLogicCA.start_link(
        run_id: "difflogic_ca_001",
        bounds: {32, 32, 8},
        optimization: %{
          n_trials: 50,
          ticks_per_eval: 100
        }
      )

      # Run optimization
      {:ok, best_params, fitness} = DiffLogicCA.optimize(ca)

      # Run with optimized parameters
      :ok = DiffLogicCA.run(ca, best_params, ticks: 1000)

  ## Reference

  - HC-38: Integrate Thunderbolt voxel automata + Cerebros TPE + DiffLogic
  - Petersen et al. (2022) "DiffLogic: Differentiable Logic Gate Networks"
  - Langton (1990) "Computation at the Edge of Chaos"
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.DiffLogic.Gates
  alias Thunderline.Thunderbolt.CA.Stepper
  alias Thunderline.Thunderbolt.Cerebros.{LoopMonitor, TPEBridge, PACCompute}
  alias Thunderline.Thunderflow.EventBus

  @telemetry_event [:thunderline, :cerebros, :difflogic_ca]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type difflogic_params :: %{
          optional(:lambda) => float(),
          optional(:bias) => float(),
          optional(:gate_temp) => float(),
          optional(:gate_logits) => Nx.Tensor.t(),
          optional(:diffusion_rate) => float()
        }

  @type ca_config :: %{
          bounds: {pos_integer(), pos_integer(), pos_integer()},
          neighborhood_type: :von_neumann | :moore | :extended,
          boundary_condition: :clip | :wrap | :reflect
        }

  @type optimization_config :: %{
          n_trials: pos_integer(),
          ticks_per_eval: pos_integer(),
          search_space: map(),
          seed: non_neg_integer() | nil
        }

  @type state :: %{
          run_id: String.t(),
          ca_config: ca_config(),
          optimization_config: optimization_config(),
          grid: map() | nil,
          current_params: difflogic_params(),
          tick: non_neg_integer(),
          loop_monitor: pid() | nil,
          tpe_bridge: pid() | nil,
          status: :idle | :running | :optimizing | :stopped
        }

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts a DiffLogic-controlled CA.

  ## Options

  - `:run_id` - Required. Unique identifier for the run.
  - `:bounds` - Grid dimensions as {x, y, z} (default: {16, 16, 4})
  - `:optimization` - Optimization config map
  - `:initial_params` - Starting DiffLogic parameters
  - `:name` - Process name registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = Keyword.get(opts, :name, via(run_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Runs the self-optimization loop to find edge-of-chaos parameters.

  Returns `{:ok, best_params, best_fitness}` when optimization completes.
  """
  @spec optimize(GenServer.server(), keyword()) ::
          {:ok, difflogic_params(), float()} | {:error, term()}
  def optimize(server, opts \\ []) do
    GenServer.call(server, {:optimize, opts}, :infinity)
  end

  @doc """
  Runs the CA with specified parameters for N ticks.

  Emits real-time voxel updates and metrics.
  """
  @spec run(GenServer.server(), difflogic_params(), keyword()) :: :ok | {:error, term()}
  def run(server, params, opts \\ []) do
    GenServer.call(server, {:run, params, opts}, :infinity)
  end

  @doc """
  Performs a single CA step and returns deltas.
  """
  @spec step(GenServer.server()) :: {:ok, [map()]} | {:error, term()}
  def step(server) do
    GenServer.call(server, :step)
  end

  @doc """
  Gets current metrics from the LoopMonitor.
  """
  @spec get_metrics(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_metrics(server) do
    GenServer.call(server, :get_metrics)
  end

  @doc """
  Gets current status and state summary.
  """
  @spec status(GenServer.server()) :: {:ok, map()}
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Stops the CA and cleans up resources.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    bounds = Keyword.get(opts, :bounds, {16, 16, 4})
    opt_config = Keyword.get(opts, :optimization, %{})
    initial_params = Keyword.get(opts, :initial_params, default_params())

    ca_config = %{
      bounds: bounds,
      neighborhood_type: :von_neumann,
      boundary_condition: :clip
    }

    optimization_config = %{
      n_trials: Map.get(opt_config, :n_trials, 50),
      ticks_per_eval: Map.get(opt_config, :ticks_per_eval, 100),
      search_space: Map.get(opt_config, :search_space, default_search_space()),
      seed: Map.get(opt_config, :seed)
    }

    state = %{
      run_id: run_id,
      ca_config: ca_config,
      optimization_config: optimization_config,
      grid: nil,
      current_params: initial_params,
      tick: 0,
      loop_monitor: nil,
      tpe_bridge: nil,
      status: :idle
    }

    Logger.info("[DiffLogicCA] Initialized run=#{run_id} bounds=#{inspect(bounds)}")

    {:ok, state}
  end

  @impl true
  def handle_call({:optimize, opts}, _from, state) do
    Logger.info("[DiffLogicCA] Starting optimization for #{state.run_id}")

    case run_optimization(state, opts) do
      {:ok, best_params, best_fitness, new_state} ->
        {:reply, {:ok, best_params, best_fitness}, %{new_state | status: :idle}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:run, params, opts}, _from, state) do
    ticks = Keyword.get(opts, :ticks, 100)
    emit_events = Keyword.get(opts, :emit_events, true)

    case run_ca(state, params, ticks, emit_events) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:step, _from, state) do
    case step_ca(state) do
      {:ok, deltas, new_state} ->
        {:reply, {:ok, deltas}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics =
      if state.loop_monitor do
        case LoopMonitor.get_metrics(state.loop_monitor) do
          {:ok, m} -> m
          _ -> empty_metrics()
        end
      else
        empty_metrics()
      end

    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    summary = %{
      run_id: state.run_id,
      status: state.status,
      tick: state.tick,
      bounds: state.ca_config.bounds,
      current_params: state.current_params,
      grid_size: if(state.grid, do: map_size(Map.get(state.grid, :bits, %{})), else: 0)
    }

    {:reply, {:ok, summary}, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[DiffLogicCA] Terminating run=#{state.run_id}")
    :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Optimization Loop
  # ═══════════════════════════════════════════════════════════════

  defp run_optimization(state, _opts) do
    # Start TPE bridge
    tpe_opts = [
      run_id: "#{state.run_id}_tpe",
      study_name: "difflogic_ca_#{state.run_id}",
      search_space: state.optimization_config.search_space,
      n_trials: state.optimization_config.n_trials,
      seed: state.optimization_config.seed
    ]

    case TPEBridge.start_link(tpe_opts) do
      {:ok, tpe_pid} ->
        # Run optimization loop
        new_state = %{state | tpe_bridge: tpe_pid, status: :optimizing}

        # Define evaluation function
        eval_fn = fn params ->
          evaluate_params(new_state, params)
        end

        case TPEBridge.optimize(tpe_pid, eval_fn, max_trials: state.optimization_config.n_trials) do
          {:ok, best_params, best_fitness} ->
            Logger.info(
              "[DiffLogicCA] Optimization complete! fitness=#{Float.round(best_fitness, 4)}"
            )

            # Emit completion event
            emit_event("bolt.difflogic_ca.optimized", %{
              run_id: state.run_id,
              best_fitness: best_fitness,
              best_params: best_params
            })

            {:ok, best_params, best_fitness, %{new_state | current_params: best_params}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("[DiffLogicCA] Failed to start TPE: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp evaluate_params(state, params) do
    started = System.monotonic_time(:millisecond)

    # Initialize fresh grid
    {x, y, z} = state.ca_config.bounds
    grid = Stepper.create_thunderbit_grid(x, y, z, rule_id: :difflogic)

    # Start loop monitor
    monitor_opts = [
      run_id: "#{state.run_id}_eval_#{:os.system_time(:millisecond)}",
      sample_window: min(50, state.optimization_config.ticks_per_eval),
      emit_interval: 1000
    ]

    {:ok, monitor} = LoopMonitor.start_link(monitor_opts)

    # Build ruleset from DiffLogic params
    ruleset = build_difflogic_ruleset(params)

    # Run for ticks_per_eval steps
    ticks = state.optimization_config.ticks_per_eval
    {_final_grid, _} = run_evaluation_loop(grid, ruleset, monitor, ticks)

    # Get final metrics
    {:ok, metrics} = LoopMonitor.get_metrics(monitor)

    # Compute fitness
    fitness = PACCompute.compute_edge_score(metrics)

    elapsed_ms = System.monotonic_time(:millisecond) - started

    :telemetry.execute(
      @telemetry_event ++ [:evaluation],
      %{elapsed_ms: elapsed_ms, ticks: ticks, fitness: fitness},
      %{run_id: state.run_id}
    )

    # Cleanup
    GenServer.stop(monitor, :normal)

    Logger.debug(
      "[DiffLogicCA] Evaluation: fitness=#{Float.round(fitness, 4)} λ̂=#{Float.round(metrics.lambda_hat, 3)} H=#{Float.round(metrics.entropy, 3)}"
    )

    {:ok, fitness}
  rescue
    e ->
      Logger.warning("[DiffLogicCA] Evaluation failed: #{inspect(e)}")
      {:error, e}
  end

  defp run_evaluation_loop(grid, _ruleset, monitor, 0), do: {grid, monitor}

  defp run_evaluation_loop(grid, ruleset, monitor, remaining) do
    {:ok, _deltas, new_grid} = Stepper.step_thunderbit_grid(grid, ruleset)

    # Extract voxel states for monitoring
    voxel_states =
      new_grid.bits
      |> Map.values()
      |> Enum.map(fn bit ->
        %{
          coord: bit.coord,
          sigma_flow: bit.sigma_flow,
          phi_phase: bit.phi_phase,
          state: bit.state
        }
      end)

    LoopMonitor.observe(monitor, new_grid.tick, voxel_states)

    run_evaluation_loop(new_grid, ruleset, monitor, remaining - 1)
  end

  # ═══════════════════════════════════════════════════════════════
  # CA Execution
  # ═══════════════════════════════════════════════════════════════

  defp run_ca(state, params, ticks, emit_events) do
    {x, y, z} = state.ca_config.bounds

    # Initialize or reset grid
    grid =
      if state.grid do
        state.grid
      else
        Stepper.create_thunderbit_grid(x, y, z, rule_id: :difflogic)
      end

    # Start loop monitor if not running
    monitor =
      if state.loop_monitor do
        state.loop_monitor
      else
        {:ok, m} =
          LoopMonitor.start_link(
            run_id: state.run_id,
            sample_window: 50,
            emit_interval: 10
          )

        m
      end

    ruleset = build_difflogic_ruleset(params)

    # Run ticks
    final_grid = run_ticks(grid, ruleset, monitor, ticks, emit_events, state.run_id)

    new_state = %{
      state
      | grid: final_grid,
        tick: final_grid.tick,
        current_params: params,
        loop_monitor: monitor,
        status: :running
    }

    {:ok, new_state}
  end

  defp run_ticks(grid, _ruleset, _monitor, 0, _emit, _run_id), do: grid

  defp run_ticks(grid, ruleset, monitor, remaining, emit_events, run_id) do
    {:ok, deltas, new_grid} = Stepper.step_thunderbit_grid(grid, ruleset)

    # Update monitor
    voxel_states =
      new_grid.bits
      |> Map.values()
      |> Enum.map(fn bit ->
        %{
          coord: bit.coord,
          sigma_flow: bit.sigma_flow,
          phi_phase: bit.phi_phase,
          state: bit.state
        }
      end)

    LoopMonitor.observe(monitor, new_grid.tick, voxel_states)

    # Emit events if requested
    if emit_events and length(deltas) > 0 do
      PACCompute.voxel_batch(run_id, deltas, new_grid.tick)
      |> case do
        {:ok, event} -> EventBus.publish_event(event)
        _ -> :ok
      end
    end

    run_ticks(new_grid, ruleset, monitor, remaining - 1, emit_events, run_id)
  end

  defp step_ca(state) do
    if state.grid == nil do
      {:error, :grid_not_initialized}
    else
      ruleset = build_difflogic_ruleset(state.current_params)
      {:ok, deltas, new_grid} = Stepper.step_thunderbit_grid(state.grid, ruleset)

      new_state = %{state | grid: new_grid, tick: new_grid.tick}
      {:ok, deltas, new_state}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # DiffLogic Ruleset
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Builds a CA ruleset from DiffLogic parameters.

  The ruleset uses differentiable gate outputs to modulate CA dynamics.
  """
  @spec build_difflogic_ruleset(difflogic_params()) :: map()
  def build_difflogic_ruleset(params) do
    lambda = Map.get(params, :lambda, 0.5)
    bias = Map.get(params, :bias, 0.3)
    gate_temp = Map.get(params, :gate_temp, 1.0)
    diffusion_rate = Map.get(params, :diffusion_rate, 0.1)

    # Initialize gate logits if not provided
    gate_logits =
      Map.get_lazy(params, :gate_logits, fn ->
        Gates.initialize_gate_logits(n_gates: 16, scale: gate_temp)
      end)

    %{
      rule_id: :difflogic,
      neighborhood_type: :von_neumann,
      boundary_condition: :clip,
      # DiffLogic parameters
      lambda: lambda,
      bias: bias,
      gate_temp: gate_temp,
      gate_logits: gate_logits,
      diffusion_rate: diffusion_rate,
      # Apply function using DiffLogic gates
      apply_fn: &apply_difflogic_rule(&1, &2, gate_logits, lambda, bias)
    }
  end

  @doc """
  Applies DiffLogic gate network to compute next state.

  Uses soft gates with learned weights to combine neighbor states.
  """
  def apply_difflogic_rule(bit, neighbors, gate_logits, lambda, bias) do
    if length(neighbors) == 0 do
      # No neighbors - apply decay
      {bit.state, bit.sigma_flow * 0.99, bit.phi_phase, bit.lambda_sensitivity}
    else
      # Extract neighbor flows
      neighbor_flows =
        neighbors
        |> Enum.map(fn {_coord, n} -> n.sigma_flow end)

      # Use DiffLogic soft gates to combine inputs
      avg_flow = Enum.sum(neighbor_flows) / length(neighbor_flows)

      # Apply soft gate between current and average neighbor
      a = Nx.tensor([bit.sigma_flow])
      b = Nx.tensor([avg_flow])

      new_flow_tensor = Gates.soft_gate(a, b, gate_logits)
      new_flow = Nx.to_number(Nx.squeeze(new_flow_tensor))

      # Apply lambda modulation (criticality control)
      new_flow = new_flow * lambda + bias * (1.0 - lambda)
      new_flow = max(0.0, min(1.0, new_flow))

      # Advance phase
      new_phase = :math.fmod(bit.phi_phase + new_flow * 0.1, 2 * :math.pi())

      # Update lambda sensitivity based on variance
      variance =
        neighbor_flows
        |> Enum.map(fn f -> (f - avg_flow) ** 2 end)
        |> Enum.sum()
        |> Kernel./(length(neighbor_flows))

      new_lambda = bit.lambda_sensitivity * 0.9 + variance * 0.5
      new_lambda = max(0.0, min(1.0, new_lambda))

      # Derive state
      new_state = derive_state(new_flow, new_lambda)

      {new_state, new_flow, new_phase, new_lambda}
    end
  end

  defp derive_state(_flow, lambda) when lambda > 0.8, do: :chaotic
  defp derive_state(flow, _lambda) when flow > 0.8, do: :active
  defp derive_state(flow, _lambda) when flow > 0.5, do: :stable
  defp derive_state(flow, _lambda) when flow > 0.2, do: :dormant
  defp derive_state(_flow, _lambda), do: :inactive

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp default_params do
    %{
      lambda: 0.5,
      bias: 0.3,
      gate_temp: 1.0,
      diffusion_rate: 0.1
    }
  end

  defp default_search_space do
    %{
      lambda: {0.1, 0.9},
      bias: {0.0, 0.5},
      gate_temp: {0.1, 2.0},
      diffusion_rate: {0.0, 0.3}
    }
  end

  defp empty_metrics do
    %{plv: 0.5, entropy: 0.5, lambda_hat: 0.5, lyapunov: 0.0, tick: 0}
  end

  defp emit_event(name, payload) do
    case Thunderline.Event.new(
           name: name,
           source: :bolt,
           payload: payload,
           meta: %{pipeline: :cerebros}
         ) do
      {:ok, event} -> EventBus.publish_event(event)
      _ -> :ok
    end
  end

  defp via(run_id) do
    {:via, Registry, {Thunderline.Thunderbolt.CA.Registry, {:difflogic_ca, run_id}}}
  end
end
