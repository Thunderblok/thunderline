defmodule Thunderline.Thunderbolt.ThunderCell.SpikingCell do
  @moduledoc """
  HC-54: Spiking Thunderbit Mode - LIF (Leaky Integrate-and-Fire) neurons
  with trainable synaptic delays.

  Integrates research from "Event-Based Delay Learning in SNNs" for:
  - Efficient event-driven dynamics (spikes, not continuous values)
  - Learnable axonal/synaptic delays (τ_delay per connection)
  - Sub-50% memory usage vs continuous-value alternatives

  ## LIF Dynamics

  Membrane potential evolution:
    τ_m * dV/dt = -(V - V_rest) + R_m * I(t)

  When V ≥ V_threshold:
    - Emit spike
    - V → V_reset
    - Enter refractory period

  ## Trainable Delays

  Each incoming connection has a learnable delay τ_d:
    I(t) = Σ w_i * spike_i(t - τ_d_i)

  Delays are updated via surrogate gradients during EventProp training.

  ## Integration with LoopMonitor (HC-40)

  - Records spike times as phases for PLV computation
  - Reports state for λ̂ estimation
  - Receives perturbation recommendations for noise injection

  ## Telemetry

  Emits `[:thunderline, :bolt, :spiking, :spike]` on each spike event.
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Signal.LoopMonitor

  @type spike :: %{
          source: term(),
          time: non_neg_integer(),
          weight: float()
        }

  @type connection :: %{
          source_id: term(),
          weight: float(),
          delay: float(),
          delay_trainable: boolean()
        }

  @type t :: %__MODULE__{
          id: term(),
          coordinate: tuple() | nil,
          # Membrane dynamics
          v_membrane: float(),
          v_rest: float(),
          v_threshold: float(),
          v_reset: float(),
          tau_membrane: float(),
          resistance: float(),
          # Refractory
          refractory_period: non_neg_integer(),
          refractory_remaining: non_neg_integer(),
          # Timing
          current_time: non_neg_integer(),
          dt: float(),
          # Synaptic input
          connections: list(connection()),
          spike_queue: list(spike()),
          # Output
          last_spike_time: non_neg_integer() | nil,
          spike_count: non_neg_integer(),
          spike_history: list(non_neg_integer()),
          # Integration
          loop_monitor: GenServer.server() | nil,
          perturbation_enabled: boolean()
        }

  defstruct id: nil,
            coordinate: nil,
            # Membrane dynamics (ms-scale)
            v_membrane: -70.0,
            v_rest: -70.0,
            v_threshold: -55.0,
            v_reset: -75.0,
            tau_membrane: 20.0,
            resistance: 10.0,
            # Refractory period (timesteps)
            refractory_period: 2,
            refractory_remaining: 0,
            # Timing
            current_time: 0,
            dt: 1.0,
            # Synaptic connections with delays
            connections: [],
            spike_queue: [],
            # Output tracking
            last_spike_time: nil,
            spike_count: 0,
            spike_history: [],
            # LoopMonitor integration
            loop_monitor: nil,
            perturbation_enabled: true

  @max_spike_history 100
  @max_queue_size 1000

  # ──────────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Starts a SpikingCell process.

  ## Options

  - `:id` - Cell identifier (required)
  - `:coordinate` - 3D position in lattice
  - `:v_threshold` - Spike threshold (default: -55.0 mV)
  - `:v_rest` - Resting potential (default: -70.0 mV)
  - `:tau_membrane` - Membrane time constant (default: 20.0 ms)
  - `:connections` - List of incoming connections with delays
  - `:loop_monitor` - LoopMonitor server for criticality feedback
  """
  def start_link(opts \\ []) do
    id = Keyword.fetch!(opts, :id)

    state = %__MODULE__{
      id: id,
      coordinate: Keyword.get(opts, :coordinate),
      v_threshold: Keyword.get(opts, :v_threshold, -55.0),
      v_rest: Keyword.get(opts, :v_rest, -70.0),
      v_reset: Keyword.get(opts, :v_reset, -75.0),
      tau_membrane: Keyword.get(opts, :tau_membrane, 20.0),
      resistance: Keyword.get(opts, :resistance, 10.0),
      refractory_period: Keyword.get(opts, :refractory_period, 2),
      connections: Keyword.get(opts, :connections, []),
      loop_monitor: Keyword.get(opts, :loop_monitor),
      perturbation_enabled: Keyword.get(opts, :perturbation_enabled, true),
      dt: Keyword.get(opts, :dt, 1.0)
    }

    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, state, name: name)
    else
      GenServer.start_link(__MODULE__, state)
    end
  end

  @doc """
  Receives an incoming spike from another cell.
  The spike will be queued with the appropriate delay from the connection.
  """
  @spec receive_spike(GenServer.server(), term(), non_neg_integer()) :: :ok
  def receive_spike(server, source_id, spike_time) do
    GenServer.cast(server, {:receive_spike, source_id, spike_time})
  end

  @doc """
  Injects external current (e.g., from sensor input).
  """
  @spec inject_current(GenServer.server(), float()) :: :ok
  def inject_current(server, current) do
    GenServer.cast(server, {:inject_current, current})
  end

  @doc """
  Advances the cell by one timestep.
  Returns {:spike, time} if the cell spiked, :no_spike otherwise.
  """
  @spec step(GenServer.server()) :: :ok
  def step(server) do
    GenServer.cast(server, :step)
  end

  @doc """
  Gets the current cell state.
  """
  @spec get_state(GenServer.server()) :: t()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Updates connection weights (for learning).
  """
  @spec update_weights(GenServer.server(), map()) :: :ok
  def update_weights(server, weight_updates) do
    GenServer.cast(server, {:update_weights, weight_updates})
  end

  @doc """
  Updates connection delays (for delay learning - EventProp).
  """
  @spec update_delays(GenServer.server(), map()) :: :ok
  def update_delays(server, delay_updates) do
    GenServer.cast(server, {:update_delays, delay_updates})
  end

  @doc """
  Adds a new incoming connection with specified delay.
  """
  @spec add_connection(GenServer.server(), term(), float(), float()) :: :ok
  def add_connection(server, source_id, weight, delay) do
    GenServer.cast(server, {:add_connection, source_id, weight, delay})
  end

  @doc """
  Resets the cell to initial state.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.cast(server, :reset)
  end

  # ──────────────────────────────────────────────────────────────────────
  # Pure Functions (LIF Dynamics)
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Computes membrane potential update via Euler integration.
  dV/dt = (-(V - V_rest) + R * I) / τ_m
  """
  @spec membrane_update(float(), float(), float(), float(), float(), float()) :: float()
  def membrane_update(v, v_rest, tau_m, resistance, current, dt) do
    dv = (-(v - v_rest) + resistance * current) / tau_m
    v + dv * dt
  end

  @doc """
  Checks if membrane potential exceeds threshold.
  """
  @spec should_spike?(float(), float()) :: boolean()
  def should_spike?(v_membrane, v_threshold) do
    v_membrane >= v_threshold
  end

  @doc """
  Computes total synaptic current from queued spikes at current time.
  """
  @spec compute_synaptic_current(list(spike()), non_neg_integer()) :: float()
  def compute_synaptic_current(spike_queue, current_time) do
    spike_queue
    |> Enum.filter(fn spike -> spike.time == current_time end)
    |> Enum.map(& &1.weight)
    |> Enum.sum()
  end

  @doc """
  Applies surrogate gradient for delay learning (EventProp-compatible).
  Uses fast sigmoid surrogate: σ'(x) ≈ 1 / (1 + |βx|)²
  """
  @spec surrogate_gradient(float(), float(), float()) :: float()
  def surrogate_gradient(v_membrane, v_threshold, beta \\ 5.0) do
    x = beta * (v_membrane - v_threshold)
    denom = 1.0 + abs(x)
    1.0 / (denom * denom)
  end

  # ──────────────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ──────────────────────────────────────────────────────────────────────

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:receive_spike, source_id, spike_time}, state) do
    # Find connection for this source
    case Enum.find(state.connections, &(&1.source_id == source_id)) do
      nil ->
        # No connection from this source, ignore
        {:noreply, state}

      connection ->
        # Queue spike with delay
        arrival_time = spike_time + round(connection.delay / state.dt)

        spike = %{
          source: source_id,
          time: arrival_time,
          weight: connection.weight
        }

        new_queue =
          [spike | state.spike_queue]
          |> Enum.take(@max_queue_size)

        {:noreply, %{state | spike_queue: new_queue}}
    end
  end

  @impl true
  def handle_cast({:inject_current, current}, state) do
    # Direct current injection creates a pseudo-spike at current time
    spike = %{
      source: :external,
      time: state.current_time,
      weight: current
    }

    new_queue = [spike | state.spike_queue]
    {:noreply, %{state | spike_queue: new_queue}}
  end

  @impl true
  def handle_cast(:step, state) do
    # Check if in refractory period
    if state.refractory_remaining > 0 do
      {:noreply,
       %{
         state
         | refractory_remaining: state.refractory_remaining - 1,
           current_time: state.current_time + 1
       }}
    else
      # Compute synaptic current
      i_syn = compute_synaptic_current(state.spike_queue, state.current_time)

      # Add perturbation noise if enabled and LoopMonitor available
      i_perturb = maybe_perturbation(state)
      i_total = i_syn + i_perturb

      # Update membrane potential
      new_v =
        membrane_update(
          state.v_membrane,
          state.v_rest,
          state.tau_membrane,
          state.resistance,
          i_total,
          state.dt
        )

      # Check for spike
      if should_spike?(new_v, state.v_threshold) do
        # Spike!
        emit_spike_telemetry(state)
        report_to_loop_monitor(state)

        new_history =
          [state.current_time | state.spike_history]
          |> Enum.take(@max_spike_history)

        # Clean up old spikes from queue
        new_queue =
          Enum.filter(state.spike_queue, fn s -> s.time > state.current_time end)

        {:noreply,
         %{
           state
           | v_membrane: state.v_reset,
             refractory_remaining: state.refractory_period,
             current_time: state.current_time + 1,
             last_spike_time: state.current_time,
             spike_count: state.spike_count + 1,
             spike_history: new_history,
             spike_queue: new_queue
         }}
      else
        # No spike, just update
        new_queue =
          Enum.filter(state.spike_queue, fn s -> s.time >= state.current_time end)

        {:noreply,
         %{
           state
           | v_membrane: new_v,
             current_time: state.current_time + 1,
             spike_queue: new_queue
         }}
      end
    end
  end

  @impl true
  def handle_cast({:update_weights, weight_updates}, state) do
    new_connections =
      Enum.map(state.connections, fn conn ->
        case Map.get(weight_updates, conn.source_id) do
          nil -> conn
          delta -> %{conn | weight: conn.weight + delta}
        end
      end)

    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_cast({:update_delays, delay_updates}, state) do
    new_connections =
      Enum.map(state.connections, fn conn ->
        if conn.delay_trainable do
          case Map.get(delay_updates, conn.source_id) do
            nil -> conn
            delta -> %{conn | delay: max(0.0, conn.delay + delta)}
          end
        else
          conn
        end
      end)

    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_cast({:add_connection, source_id, weight, delay}, state) do
    connection = %{
      source_id: source_id,
      weight: weight,
      delay: delay,
      delay_trainable: true
    }

    {:noreply, %{state | connections: [connection | state.connections]}}
  end

  @impl true
  def handle_cast(:reset, state) do
    {:noreply,
     %{
       state
       | v_membrane: state.v_rest,
         refractory_remaining: 0,
         current_time: 0,
         last_spike_time: nil,
         spike_count: 0,
         spike_history: [],
         spike_queue: []
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ──────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────

  defp maybe_perturbation(%{perturbation_enabled: false}), do: 0.0
  defp maybe_perturbation(%{loop_monitor: nil}), do: 0.0

  defp maybe_perturbation(%{loop_monitor: monitor}) do
    # Get recommended perturbation intensity from LoopMonitor
    try do
      sigma = LoopMonitor.recommended_perturbation(monitor)
      # Gaussian noise with recommended standard deviation
      :rand.normal() * sigma
    rescue
      _ -> 0.0
    catch
      :exit, _ -> 0.0
    end
  end

  defp emit_spike_telemetry(state) do
    :telemetry.execute(
      [:thunderline, :bolt, :spiking, :spike],
      %{
        time: state.current_time,
        v_membrane: state.v_membrane,
        spike_count: state.spike_count + 1
      },
      %{
        id: state.id,
        coordinate: state.coordinate
      }
    )
  end

  defp report_to_loop_monitor(%{loop_monitor: nil}), do: :ok

  defp report_to_loop_monitor(state) do
    try do
      # Report spike time as phase (normalized to buffer window)
      phase = rem(state.current_time, 100) / 100.0
      LoopMonitor.record_phase(state.loop_monitor, phase)

      # Report binary state (spiking = 1)
      LoopMonitor.record_state(state.loop_monitor, [1])
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end
end
