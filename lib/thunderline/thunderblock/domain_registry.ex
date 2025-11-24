defmodule Thunderline.Thunderblock.DomainRegistry do
  @moduledoc """
  Tracks which domains are active based on tick flow.
  Domains must receive and acknowledge at least one tick to be considered active.

  ## Architecture

  The DomainRegistry is the central tracking system for domain activation:
  1. Starts before TickGenerator in supervision tree
  2. Subscribes to "system:domain_tick" and "system:domain_activated" events
  3. Records domain activations in ETS for fast queries
  4. Maintains activation history in memory
  5. Provides query API for health dashboards

  ## Event Subscriptions

  Listens to:
  - `"system:domain_tick"` - Update tick count
  - `"system:domain_activated"` - Record domain activation
  - `"system:domain_deactivated"` - Record domain deactivation

  ## ETS Table Structure

  Table name: `:thunderblock_domain_registry`

  Entries:
      {:last_tick, tick_count, timestamp}
      {domain_name, status, tick_count, timestamp}

  ## Query API

      # Get all active domains
      Thunderline.Thunderblock.DomainRegistry.active_domains()
      #=> ["thunderflow", "thunderbolt", "cerebros"]

      # Get active count
      Thunderline.Thunderblock.DomainRegistry.active_count()
      #=> 3

      # Get domain status
      Thunderline.Thunderblock.DomainRegistry.domain_status("thunderflow")
      #=> {:ok, %{status: :active, tick: 1, timestamp: 1732488000000}}

  ## Telemetry

  Emits `[:thunderline, :domain_registry, :activation]` event with:
  - `active_count` - Number of active domains
  - Metadata: domain name, tick count
  """
  use GenServer
  require Logger

  @table_name :thunderblock_domain_registry
  @max_history 100

  # Client API

  @doc """
  Starts the DomainRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns list of all active domain names.
  """
  @spec active_domains() :: [String.t()]
  def active_domains do
    GenServer.call(__MODULE__, :active_domains)
  end

  @doc """
  Returns count of active domains.
  """
  @spec active_count() :: non_neg_integer()
  def active_count do
    GenServer.call(__MODULE__, :active_count)
  end

  @doc """
  Returns status information for a specific domain.

  Returns `{:ok, %{status: atom, tick: integer, timestamp: integer}}` or `{:error, :not_found}`.
  """
  @spec domain_status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def domain_status(domain_name) when is_binary(domain_name) do
    case :ets.lookup(@table_name, domain_name) do
      [{^domain_name, status, tick, timestamp}] ->
        {:ok, %{status: status, tick: tick, timestamp: timestamp}}
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns activation history (last N activations).
  """
  @spec activation_history() :: [map()]
  def activation_history do
    GenServer.call(__MODULE__, :activation_history)
  end

  @doc """
  Returns current tick count.
  """
  @spec current_tick() :: non_neg_integer()
  def current_tick do
    case :ets.lookup(@table_name, :last_tick) do
      [{:last_tick, tick_count, _timestamp}] -> tick_count
      [] -> 0
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    # Subscribe to system events
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_tick")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_activated")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_deactivated")

    Logger.info("[DomainRegistry] Started and subscribed to system events")

    {:ok, %{
      active_domains: MapSet.new(),
      tick_count: 0,
      last_tick_at: nil,
      activation_history: []
    }}
  end

  @impl true
  def handle_info({:domain_tick, tick_count, timestamp, _meta}, state) do
    # Update ETS with latest tick
    :ets.insert(@table_name, {:last_tick, tick_count, timestamp})

    {:noreply, %{state | tick_count: tick_count, last_tick_at: timestamp}}
  end

  @impl true
  def handle_info({:domain_activated, domain_name, metadata}, state) do
    Logger.info("[DomainRegistry] Domain activated: #{domain_name}")

    active_domains = MapSet.put(state.active_domains, domain_name)

    # Update ETS
    :ets.insert(@table_name, {domain_name, :active, state.tick_count, System.monotonic_time()})

    # Record in history
    activation = %{
      domain: domain_name,
      tick: state.tick_count,
      timestamp: DateTime.utc_now(),
      metadata: metadata || %{}
    }

    history = [activation | state.activation_history] |> Enum.take(@max_history)

    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :domain_registry, :activation],
      %{active_count: MapSet.size(active_domains)},
      %{domain: domain_name, tick: state.tick_count}
    )

    {:noreply, %{state | active_domains: active_domains, activation_history: history}}
  end

  @impl true
  def handle_info({:domain_deactivated, domain_name, _metadata}, state) do
    Logger.info("[DomainRegistry] Domain deactivated: #{domain_name}")

    active_domains = MapSet.delete(state.active_domains, domain_name)

    # Update ETS
    :ets.insert(@table_name, {domain_name, :inactive, state.tick_count, System.monotonic_time()})

    {:noreply, %{state | active_domains: active_domains}}
  end

  @impl true
  def handle_call(:active_domains, _from, state) do
    {:reply, MapSet.to_list(state.active_domains), state}
  end

  @impl true
  def handle_call(:active_count, _from, state) do
    {:reply, MapSet.size(state.active_domains), state}
  end

  @impl true
  def handle_call(:activation_history, _from, state) do
    {:reply, state.activation_history, state}
  end
end
