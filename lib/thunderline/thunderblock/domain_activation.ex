defmodule Thunderline.Thunderblock.DomainActivation do
  @moduledoc """
  Behavior for domain activation in response to tick system broadcasts.

  ## Purpose

  Provides a standardized interface for domains to:
  - Activate on specific tick counts
  - Register activation with the DomainRegistry
  - Handle tick-based lifecycle events
  - Integrate with the tick-based coordination system

  ## Usage

  Implement this behavior in your domain's supervisor or coordinator:

      defmodule Thunderline.Thunderflow.Supervisor do
        use Supervisor
        @behaviour Thunderline.Thunderblock.DomainActivation

        @impl Thunderline.Thunderblock.DomainActivation
        def domain_name, do: "thunderflow"

        @impl Thunderline.Thunderblock.DomainActivation
        def activation_tick, do: 1

        @impl Thunderline.Thunderblock.DomainActivation
        def on_activated(tick_count) do
          # Start domain-specific processes
          {:ok, %{started_at: tick_count}}
        end

        @impl Thunderline.Thunderblock.DomainActivation
        def on_tick(tick_count, state) do
          # Handle periodic ticks
          {:noreply, state}
        end
      end

  Then add activation support in your `start_link/1`:

      def start_link(init_arg) do
        Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        |> tap(fn {:ok, _pid} ->
          Thunderline.Thunderblock.DomainActivation.Helpers.maybe_activate(__MODULE__)
        end)
      end

  ## Lifecycle

  1. Domain supervisor starts
  2. Calls `maybe_activate/1` which subscribes to ticks
  3. On reaching `activation_tick()`, calls `on_activated/1`
  4. Emits activation event to DomainRegistry
  5. Continues receiving ticks via `on_tick/2`

  ## Telemetry

  Emits the following events:
  - `[:thunderline, :domain, :activation, :start]` - Before activation
  - `[:thunderline, :domain, :activation, :complete]` - After activation
  - `[:thunderline, :domain, :activation, :error]` - On activation failure
  """

  @doc """
  Returns the canonical name of the domain.

  This name is used for:
  - Registration in DomainRegistry
  - PubSub topic namespacing
  - Telemetry event metadata
  - Persistent storage in ActiveDomainRegistry

  ## Examples

      domain_name() #=> "thunderflow"
  """
  @callback domain_name() :: String.t()

  @doc """
  Returns the tick count at which this domain should activate.

  Domains can stagger their activation to avoid thundering herd:
  - Tick 1: Core infrastructure domains (Thunderflow, Thunderblock)
  - Tick 2-5: Application domains (Thunderbolt, Thundergate)
  - Tick 5+: Optional/feature domains

  ## Examples

      activation_tick() #=> 1  # Activate on first tick
      activation_tick() #=> 3  # Activate on third tick
  """
  @callback activation_tick() :: non_neg_integer()

  @doc """
  Called when the domain reaches its activation tick.

  This is where you should:
  - Initialize domain-specific state
  - Start critical processes
  - Establish connections
  - Load configuration

  Return `{:ok, state}` on success or `{:error, reason}` on failure.

  ## Parameters

  - `tick_count` - The current tick count when activation occurred

  ## Examples

      def on_activated(tick_count) do
        Logger.info("[Thunderflow] Activating at tick \#{tick_count}")
        {:ok, %{activated_at: tick_count, status: :ready}}
      end
  """
  @callback on_activated(tick_count :: non_neg_integer()) ::
              {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Called on every tick after activation.

  Use this for:
  - Periodic health checks
  - Metric collection
  - Background maintenance
  - State synchronization

  Return `{:noreply, state}` to continue or `{:stop, reason, state}` to deactivate.

  ## Parameters

  - `tick_count` - The current tick count
  - `state` - Domain state from `on_activated/1` or previous `on_tick/2`

  ## Examples

      def on_tick(tick_count, state) do
        if rem(tick_count, 10) == 0 do
          Logger.debug("[Thunderflow] Health check at tick \#{tick_count}")
        end
        {:noreply, state}
      end
  """
  @callback on_tick(tick_count :: non_neg_integer(), state :: term()) ::
              {:noreply, state :: term()} | {:stop, reason :: term(), state :: term()}

  @doc """
  Optional callback for cleanup when domain deactivates.

  Default implementation does nothing.

  ## Parameters

  - `reason` - Reason for deactivation (`:normal`, `:shutdown`, or error)
  - `state` - Final domain state

  ## Examples

      def on_deactivated(:shutdown, state) do
        Logger.info("[Thunderflow] Graceful shutdown")
        :ok
      end
  """
  @callback on_deactivated(reason :: term(), state :: term()) :: :ok

  @optional_callbacks on_deactivated: 2

  defmodule Helpers do
    @moduledoc """
    Helper functions for implementing domain activation.
    """

    require Logger

    @doc """
    Subscribes to tick system and handles activation lifecycle.

    Call this from your domain's `start_link/1` after the supervisor starts:

        def start_link(init_arg) do
          Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
          |> tap(fn {:ok, _pid} ->
            DomainActivation.Helpers.maybe_activate(__MODULE__)
          end)
        end
    """
    def maybe_activate(module) when is_atom(module) do
      if function_exported?(module, :domain_name, 0) do
        domain_name = module.domain_name()
        activation_tick = module.activation_tick()

        # Start activation listener GenServer (it will subscribe to ticks in its init/1)
        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Thunderline.TaskSupervisor,
            {Thunderline.Thunderblock.DomainActivation.Listener,
             module: module, domain_name: domain_name, activation_tick: activation_tick}
          )

        :ok
      else
        Logger.warning(
          "[DomainActivation] Module #{inspect(module)} does not implement DomainActivation behavior"
        )

        {:error, :not_implemented}
      end
    end

    @doc """
    Broadcasts domain activation event.
    """
    def broadcast_activation(domain_name, tick_count, metadata \\ %{}) do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "system:domain_activated",
        %{
          domain_name: domain_name,
          tick_count: tick_count,
          metadata: metadata,
          timestamp: DateTime.utc_now()
        }
      )
    end

    @doc """
    Broadcasts domain deactivation event.
    """
    def broadcast_deactivation(domain_name, tick_count, reason \\ :normal) do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "system:domain_deactivated",
        %{
          domain_name: domain_name,
          tick_count: tick_count,
          reason: reason,
          timestamp: DateTime.utc_now()
        }
      )
    end

    @doc """
    Records activation in the persistent ActiveDomainRegistry.
    """
    def record_activation(domain_name, tick_count, metadata \\ %{}) do
      Thunderline.Thunderblock.Resources.ActiveDomainRegistry.record_activation!(
        domain_name,
        tick_count,
        metadata
      )
    rescue
      e ->
        Logger.error(
          "[DomainActivation] Failed to record activation for #{domain_name}: #{inspect(e)}"
        )

        {:error, e}
    end
  end

  defmodule Listener do
    @moduledoc """
    GenServer that listens for ticks and triggers domain activation.

    This process is started automatically by `Helpers.maybe_activate/1`.
    """
    use GenServer
    require Logger

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl true
    def init(opts) do
      module = Keyword.fetch!(opts, :module)
      domain_name = Keyword.fetch!(opts, :domain_name)
      activation_tick = Keyword.fetch!(opts, :activation_tick)

      # CRITICAL: Subscribe to tick events in THIS process (not the supervisor)
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_tick")

      Logger.info(
        "[DomainActivation] #{domain_name} subscribed, will activate at tick #{activation_tick}"
      )

      state = %{
        module: module,
        domain_name: domain_name,
        activation_tick: activation_tick,
        activated?: false,
        domain_state: nil,
        current_tick: 0
      }

      {:ok, state}
    end

    @impl true
    def handle_info(%{tick: tick_count}, state) when tick_count < state.activation_tick do
      # Not yet time to activate, just track tick
      {:noreply, %{state | current_tick: tick_count}}
    end

    @impl true
    def handle_info(%{tick: tick_count}, %{activated?: false} = state)
        when tick_count >= state.activation_tick do
      # Time to activate!
      :telemetry.execute(
        [:thunderline, :domain, :activation, :start],
        %{tick: tick_count},
        %{domain: state.domain_name}
      )

      case state.module.on_activated(tick_count) do
        {:ok, domain_state} ->
          Logger.info("[DomainActivation] #{state.domain_name} activated at tick #{tick_count}")

          # Broadcast activation
          Helpers.broadcast_activation(state.domain_name, tick_count, %{
            module: state.module
          })

          # Record in database
          Helpers.record_activation(state.domain_name, tick_count, %{
            module: inspect(state.module)
          })

          :telemetry.execute(
            [:thunderline, :domain, :activation, :complete],
            %{tick: tick_count},
            %{domain: state.domain_name}
          )

          {:noreply,
           %{state | activated?: true, domain_state: domain_state, current_tick: tick_count}}

        {:error, reason} ->
          Logger.error(
            "[DomainActivation] #{state.domain_name} failed to activate: #{inspect(reason)}"
          )

          :telemetry.execute(
            [:thunderline, :domain, :activation, :error],
            %{tick: tick_count},
            %{domain: state.domain_name, error: reason}
          )

          {:stop, {:activation_failed, reason}, state}
      end
    end

    @impl true
    def handle_info(%{tick: tick_count}, %{activated?: true} = state) do
      # Already activated, call on_tick callback
      case state.module.on_tick(tick_count, state.domain_state) do
        {:noreply, new_domain_state} ->
          {:noreply, %{state | domain_state: new_domain_state, current_tick: tick_count}}

        {:stop, reason, final_state} ->
          Logger.info("[DomainActivation] #{state.domain_name} deactivating: #{inspect(reason)}")

          # Call optional deactivation callback
          if function_exported?(state.module, :on_deactivated, 2) do
            state.module.on_deactivated(reason, final_state)
          end

          # Broadcast deactivation
          Helpers.broadcast_deactivation(state.domain_name, tick_count, reason)

          {:stop, reason, state}
      end
    end

    @impl true
    def handle_info(_msg, state) do
      # Ignore unknown messages
      {:noreply, state}
    end
  end
end
