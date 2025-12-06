defmodule Thunderline.Thunderpac.Supervisor do
  @moduledoc """
  Supervisor for Thunderpac domain with tick-based activation.

  Implements the DomainActivation behavior to coordinate startup
  with the tick system. Activates on tick 2 after core flow infrastructure.

  ## Responsibilities

  - Supervise PAC Registry for process naming
  - Supervise MemoryModule DynamicSupervisor for PAC memory instances
  - Supervise SurpriseEventHandler for memory write triggers
  - Listen for tick broadcasts
  - Activate domain on tick 2
  - Register activation with DomainRegistry

  ## Architecture

  The Thunderpac domain manages PAC (Persistent Agent Compute) lifecycle:

  ```
  Thunderpac.Supervisor
  ├── Thunderpac.Registry (process registration & lookup)
  ├── Thunderpac.MemoryDynamicSupervisor (dynamic memory modules)
  └── Thunderpac.SurpriseEventHandler (surprise → memory write)
  ```

  ## Memory Module Integration (HC-75)

  Each PAC can have an associated MemoryModule for MIRAS/Titans-style
  deep MLP memory. The MemoryDynamicSupervisor manages these instances,
  while the SurpriseEventHandler listens for surprise events from the
  Thunderbolt domain and triggers memory writes when surprise exceeds threshold.
  """

  use Supervisor
  @behaviour Thunderline.Thunderblock.DomainActivation

  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    |> tap(fn
      {:ok, _pid} ->
        # Subscribe to tick system and set up activation
        Thunderline.Thunderblock.DomainActivation.Helpers.maybe_activate(__MODULE__)

      {:error, reason} ->
        Logger.error("[Thunderpac.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # PAC Registry for process naming and lookup
      Thunderline.Thunderpac.Registry,
      # Dynamic supervisor for memory module instances
      {DynamicSupervisor, name: Thunderline.Thunderpac.MemoryDynamicSupervisor, strategy: :one_for_one},
      # Surprise event handler - connects Bolt surprise signals to PAC memory writes
      Thunderline.Thunderpac.SurpriseEventHandler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ===========================================================================
  # Public API for Memory Module Management
  # ===========================================================================

  @doc """
  Starts a memory module for a PAC.

  ## Parameters
    - pac_id: The PAC identifier
    - config: Memory module configuration (optional)
      - :depth - Number of layers (default: 3)
      - :width - Neurons per layer (default: 64)
      - :input_dim - Input dimension (default: 32)
      - :output_dim - Output dimension (default: 32)
      - :surprise_threshold - Write threshold (default: 0.1)
      - :momentum_beta - Surprise smoothing (default: 0.9)
      - :weight_decay - Forgetting factor (default: 0.99)
      - :write_lr - Write learning rate (default: 0.01)

  ## Returns
    - {:ok, pid} on success
    - {:error, reason} on failure
  """
  @spec start_memory_module(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_memory_module(pac_id, config \\ []) do
    child_spec = {
      Thunderline.Thunderpac.MemoryModule,
      [pac_id: pac_id] ++ config
    }

    case DynamicSupervisor.start_child(Thunderline.Thunderpac.MemoryDynamicSupervisor, child_spec) do
      {:ok, pid} ->
        Logger.info("[Thunderpac] Started memory module for PAC #{pac_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("[Thunderpac] Memory module already exists for PAC #{pac_id}")
        {:ok, pid}

      error ->
        Logger.error("[Thunderpac] Failed to start memory module for PAC #{pac_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Stops a memory module for a PAC.
  """
  @spec stop_memory_module(String.t()) :: :ok | {:error, :not_found}
  def stop_memory_module(pac_id) do
    case Thunderline.Thunderpac.Registry.get_memory_pid(pac_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(Thunderline.Thunderpac.MemoryDynamicSupervisor, pid)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets or creates a memory module for a PAC.

  This is the preferred way to obtain a memory module - it will create
  one if it doesn't exist.
  """
  @spec ensure_memory_module(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_memory_module(pac_id, config \\ []) do
    case Thunderline.Thunderpac.Registry.get_memory_pid(pac_id) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :not_found} ->
        start_memory_module(pac_id, config)
    end
  end

  # ===========================================================================
  # DomainActivation Callbacks
  # ===========================================================================

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thunderpac"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 2

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info("[Thunderpac] Domain activated at tick #{tick_count}")

    # Verify registry is running
    registry_ready = Process.whereis(Thunderline.Thunderpac.Registry) != nil

    # Verify dynamic supervisor is running
    memory_sup_ready = Process.whereis(Thunderline.Thunderpac.MemoryDynamicSupervisor) != nil

    # Verify event handler is running
    event_handler_ready = Process.whereis(Thunderline.Thunderpac.SurpriseEventHandler) != nil

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      registry_ready: registry_ready,
      memory_supervisor_ready: memory_sup_ready,
      event_handler_ready: event_handler_ready,
      tick_count: tick_count
    }

    # Emit activation telemetry
    :telemetry.execute(
      [:thunderline, :pac, :domain, :activated],
      %{tick: tick_count},
      %{
        domain: "thunderpac",
        registry_ready: registry_ready,
        memory_supervisor_ready: memory_sup_ready,
        event_handler_ready: event_handler_ready
      }
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Emit health check every 10 ticks
    if rem(tick_count, 10) == 0 do
      stats = Thunderline.Thunderpac.Registry.stats()

      :telemetry.execute(
        [:thunderline, :pac, :health_check],
        %{
          tick: tick_count,
          memory_module_count: stats.total_count,
          zones_active: map_size(stats.by_zone)
        },
        %{domain: "thunderpac"}
      )

      Logger.debug("[Thunderpac] Health check at tick #{tick_count}: #{stats.total_count} memory modules")
    end

    # Tick active PACs every 20 system ticks (~1 second at 50ms tick rate)
    state =
      if rem(tick_count, 20) == 0 do
        tick_active_pacs(tick_count, state)
      else
        state
      end

    {:noreply, %{state | tick_count: tick_count}}
  end

  # Tick all active PACs and emit events
  defp tick_active_pacs(tick_count, state) do
    alias Thunderline.Thunderpac.Resources.PAC

    # Get active PACs using code interface
    case PAC.active_pacs(authorize?: false) do
      {:ok, active_pacs} when is_list(active_pacs) and length(active_pacs) > 0 ->
        pacs_ticked =
          Enum.reduce(active_pacs, 0, fn pac, count ->
            case PAC.tick(pac, authorize?: false) do
              {:ok, _updated_pac} ->
                # Emit tick event for this PAC
                emit_pac_tick_event(pac, tick_count)
                count + 1

              {:error, reason} ->
                Logger.warning("[Thunderpac] Failed to tick PAC #{pac.id}: #{inspect(reason)}")
                count
            end
          end)

        :telemetry.execute(
          [:thunderline, :pac, :tick_batch],
          %{tick: tick_count, pacs_ticked: pacs_ticked, total_active: length(active_pacs)},
          %{domain: "thunderpac"}
        )

        Logger.debug(
          "[Thunderpac] Ticked #{pacs_ticked}/#{length(active_pacs)} active PACs at tick #{tick_count}"
        )

        Map.put(state, :last_pac_tick, tick_count)

      {:ok, []} ->
        state

      {:error, reason} ->
        Logger.warning("[Thunderpac] Failed to list active PACs: #{inspect(reason)}")
        state
    end
  end

  defp emit_pac_tick_event(pac, tick_count) do
    alias Thunderline.Thunderflow.EventBus
    alias Thunderline.Event

    payload = %{
      pac_id: pac.id,
      pac_name: pac.name,
      tick_count: tick_count,
      total_active_ticks: pac.total_active_ticks,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Event.new(name: "pac.tick.processed", source: :pac, payload: payload) do
      {:ok, event} ->
        case EventBus.publish_event(event) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.debug("[Thunderpac] Event publish failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.debug("[Thunderpac] Event creation failed: #{inspect(reason)}")
    end
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    ticks_active = state.tick_count - state.activated_at

    Logger.info(
      "[Thunderpac] Domain deactivated after #{ticks_active} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end
end
