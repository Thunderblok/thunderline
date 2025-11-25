defmodule Thunderline.Telemetry.TickObserver do
  @moduledoc """
  Observes domain ticks and feeds near-critical dynamics to LoopMonitor.

  Subscribes to the "system:domain_tick" PubSub topic and collects
  observations from registered domains, feeding them to the LoopMonitor
  for analysis and intervention triggering.

  ## Architecture

  ```
  TickGenerator → PubSub → TickObserver → LoopMonitor → iRoPE interventions
                              ↓
                        Domain collectors
  ```

  ## Usage

  Start in your supervision tree:

      children = [
        {Thunderline.Telemetry.TickObserver, []}
      ]

  Register a domain to observe:

      TickObserver.register_domain(:ml_pipeline, fn tick ->
        # Return observation map
        %{
          tick: tick,
          activations: get_current_activations(),
          entropy_prev: get_prev_entropy(),
          entropy_next: get_curr_entropy()
        }
      end)

  ## Telemetry

  Emits:
  - `[:thunderline, :tick_observer, :tick_received]` - On each tick
  - `[:thunderline, :tick_observer, :domain_observed]` - After observing a domain
  - `[:thunderline, :tick_observer, :collector_error]` - If collector fails
  """

  use GenServer
  require Logger

  alias Thunderline.Telemetry.{LoopMonitor, IRoPE}

  @pubsub_topic "system:domain_tick"
  @default_observe_interval 5

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  @doc """
  Start the TickObserver.

  ## Options

  - `:loop_monitor` - Name of LoopMonitor to use (default: LoopMonitor)
  - `:observe_interval` - Observe every N ticks (default: 5)
  - `:auto_irope` - Auto-register iRoPE callbacks (default: true)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a domain to observe.

  The collector function is called on each observation tick and should
  return a map with:
  - `:tick` - Current tick number
  - `:activations` - Nx tensor of activations
  - `:entropy_prev` - Previous entropy value
  - `:entropy_next` - Current entropy value
  - `:jvp_matrix` - Optional Jacobian for FTLE (default provided)

  ## Example

      TickObserver.register_domain(:ml_pipeline, fn tick ->
        %{
          tick: tick,
          activations: MyML.get_activations(),
          entropy_prev: MyML.get_prev_entropy(),
          entropy_next: MyML.get_curr_entropy()
        }
      end)
  """
  @spec register_domain(atom(), (non_neg_integer() -> map())) :: :ok
  def register_domain(domain, collector, server \\ __MODULE__)
      when is_atom(domain) and is_function(collector, 1) do
    GenServer.cast(server, {:register_domain, domain, collector})
  end

  @doc """
  Unregister a domain from observation.
  """
  @spec unregister_domain(atom()) :: :ok
  def unregister_domain(domain, server \\ __MODULE__) do
    GenServer.cast(server, {:unregister_domain, domain})
  end

  @doc """
  Get list of registered domains.
  """
  @spec list_domains() :: [atom()]
  def list_domains(server \\ __MODULE__) do
    GenServer.call(server, :list_domains)
  end

  @doc """
  Get observer statistics.
  """
  @spec stats() :: map()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  Force observation on next tick (for testing).
  """
  @spec force_observe() :: :ok
  def force_observe(server \\ __MODULE__) do
    GenServer.cast(server, :force_observe)
  end

  # -------------------------------------------------------------------
  # Server Callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    loop_monitor = Keyword.get(opts, :loop_monitor, LoopMonitor)
    observe_interval = Keyword.get(opts, :observe_interval, @default_observe_interval)
    auto_irope = Keyword.get(opts, :auto_irope, true)

    # Subscribe to tick system
    Phoenix.PubSub.subscribe(Thunderline.PubSub, @pubsub_topic)

    Logger.info(
      "[TickObserver] Started, observe interval: #{observe_interval} ticks, auto_irope: #{auto_irope}"
    )

    state = %{
      loop_monitor: loop_monitor,
      observe_interval: observe_interval,
      auto_irope: auto_irope,
      domains: %{},
      current_tick: 0,
      ticks_received: 0,
      observations_made: 0,
      last_observation_tick: 0,
      force_next: false,
      started_at: DateTime.utc_now(),
      errors: []
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:domain_tick, tick_count, _timestamp, _meta}, state) do
    new_state = handle_tick(tick_count, state)
    {:noreply, new_state}
  end

  # Also handle map format for compatibility
  @impl true
  def handle_info(%{tick: tick_count}, state) do
    new_state = handle_tick(tick_count, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:register_domain, domain, collector}, state) do
    Logger.info("[TickObserver] Registered domain: #{domain}")

    # Auto-register iRoPE intervention if enabled
    if state.auto_irope and Process.whereis(state.loop_monitor) do
      callback = IRoPE.default_intervention_callback()
      LoopMonitor.register_intervention(domain, callback, state.loop_monitor)
      Logger.debug("[TickObserver] Auto-registered iRoPE callback for #{domain}")
    end

    new_domains = Map.put(state.domains, domain, %{
      collector: collector,
      registered_at: DateTime.utc_now(),
      observations: 0,
      last_result: nil
    })

    {:noreply, %{state | domains: new_domains}}
  end

  @impl true
  def handle_cast({:unregister_domain, domain}, state) do
    Logger.info("[TickObserver] Unregistered domain: #{domain}")
    new_domains = Map.delete(state.domains, domain)
    {:noreply, %{state | domains: new_domains}}
  end

  @impl true
  def handle_cast(:force_observe, state) do
    {:noreply, %{state | force_next: true}}
  end

  @impl true
  def handle_call(:list_domains, _from, state) do
    {:reply, Map.keys(state.domains), state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.started_at)

    stats = %{
      current_tick: state.current_tick,
      ticks_received: state.ticks_received,
      observations_made: state.observations_made,
      domains_count: map_size(state.domains),
      domains: Enum.map(state.domains, fn {name, info} ->
        {name, %{observations: info.observations, registered_at: info.registered_at}}
      end) |> Map.new(),
      uptime_seconds: uptime,
      observe_interval: state.observe_interval,
      last_observation_tick: state.last_observation_tick,
      error_count: length(state.errors)
    }

    {:reply, stats, state}
  end

  # -------------------------------------------------------------------
  # Private Implementation
  # -------------------------------------------------------------------

  defp handle_tick(tick_count, state) do
    # Emit tick received telemetry
    :telemetry.execute(
      [:thunderline, :tick_observer, :tick_received],
      %{tick: tick_count},
      %{domains_count: map_size(state.domains)}
    )

    state = %{state | current_tick: tick_count, ticks_received: state.ticks_received + 1}

    # Check if we should observe on this tick
    should_observe =
      state.force_next or
        rem(tick_count, state.observe_interval) == 0

    if should_observe and map_size(state.domains) > 0 do
      observe_all_domains(tick_count, %{state | force_next: false})
    else
      state
    end
  end

  defp observe_all_domains(tick_count, state) do
    # Observe each registered domain
    {new_domains, observations_made, errors} =
      Enum.reduce(state.domains, {%{}, 0, []}, fn {domain, info}, {domains, count, errs} ->
        case observe_domain(domain, info, tick_count, state) do
          {:ok, result} ->
            updated_info = %{info | observations: info.observations + 1, last_result: result}
            {Map.put(domains, domain, updated_info), count + 1, errs}

          {:error, reason} ->
            Logger.warning("[TickObserver] Error observing #{domain}: #{inspect(reason)}")
            err = %{domain: domain, tick: tick_count, reason: reason, at: DateTime.utc_now()}
            {Map.put(domains, domain, info), count, [err | errs]}
        end
      end)

    %{state |
      domains: new_domains,
      observations_made: state.observations_made + observations_made,
      last_observation_tick: tick_count,
      errors: Enum.take(errors ++ state.errors, 100)
    }
  end

  defp observe_domain(domain, info, tick_count, state) do
    # Call the collector to get observation data
    case safe_collect(info.collector, tick_count) do
      {:ok, observation} ->
        # Ensure tick is set
        observation = Map.put_new(observation, :tick, tick_count)

        # Send to LoopMonitor
        result =
          if Process.whereis(state.loop_monitor) do
            LoopMonitor.observe(domain, observation, state.loop_monitor)
          else
            :loop_monitor_not_running
          end

        # Emit telemetry
        :telemetry.execute(
          [:thunderline, :tick_observer, :domain_observed],
          %{tick: tick_count},
          %{domain: domain, result: result}
        )

        {:ok, result}

      {:error, reason} ->
        :telemetry.execute(
          [:thunderline, :tick_observer, :collector_error],
          %{tick: tick_count},
          %{domain: domain, error: reason}
        )

        {:error, reason}
    end
  end

  defp safe_collect(collector, tick_count) do
    {:ok, collector.(tick_count)}
  rescue
    e ->
      {:error, {:exception, Exception.message(e)}}
  catch
    :exit, reason ->
      {:error, {:exit, reason}}
  end
end
