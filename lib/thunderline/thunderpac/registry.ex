defmodule Thunderline.Thunderpac.Registry do
  @moduledoc """
  Thunderpac Registry - Runtime Lookup and Management for PAC Memory Modules

  Provides runtime registration and lookup of active PAC memory modules
  and related processes. Uses ETS for fast, concurrent access.

  ## Features

  - Register/unregister memory modules by PAC ID
  - Lookup by PAC ID, zone, or state
  - List active memory modules with filters
  - Track memory module metrics and statistics
  - Automatic cleanup on process termination

  ## Usage

      # Get the memory module for a PAC
      {:ok, pid} = Registry.lookup_memory(pac_id)

      # Register a new memory module
      :ok = Registry.register_memory(pac_id, pid, zone_id)

      # List all memory modules in a zone
      modules = Registry.by_zone(zone_id)

      # Get aggregate statistics
      stats = Registry.stats()

  ## Integration with MemoryModule

  The MemoryModule GenServer uses this registry via:

      {:via, Registry, {Thunderline.Thunderpac.Registry, {:memory, pac_id}}}

  This registry wraps Elixir's built-in Registry for named process lookup
  while providing domain-specific APIs for memory module management.
  """

  use GenServer

  require Logger

  @table_name :thunderpac_registry
  @index_by_zone :thunderpac_by_zone
  @index_by_state :thunderpac_by_state

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts the registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the child spec for the underlying Elixir Registry.

  This should be started in the supervision tree for process naming.
  """
  def child_spec_for_process_registry do
    {Registry, keys: :unique, name: __MODULE__}
  end

  @doc """
  Registers a memory module for a PAC.

  ## Parameters
    - pac_id: The PAC identifier
    - pid: The memory module process PID
    - opts: Optional metadata (zone_id, config, etc.)

  ## Returns
    - :ok on success
    - {:error, :already_registered} if a module already exists for this PAC
  """
  @spec register_memory(String.t(), pid(), keyword()) :: :ok | {:error, :already_registered}
  def register_memory(pac_id, pid, opts \\ []) do
    GenServer.call(__MODULE__, {:register_memory, pac_id, pid, opts})
  end

  @doc """
  Unregisters a memory module for a PAC.
  """
  @spec unregister_memory(String.t()) :: :ok
  def unregister_memory(pac_id) do
    GenServer.call(__MODULE__, {:unregister_memory, pac_id})
  end

  @doc """
  Looks up a memory module by PAC ID.

  ## Returns
    - {:ok, entry} with pid, zone_id, registered_at, etc.
    - {:error, :not_found} if no module registered
  """
  @spec lookup_memory(String.t()) :: {:ok, map()} | {:error, :not_found}
  def lookup_memory(pac_id) do
    case :ets.lookup(@table_name, {:memory, pac_id}) do
      [{_key, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the PID for a memory module, if it exists.
  """
  @spec get_memory_pid(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_memory_pid(pac_id) do
    case lookup_memory(pac_id) do
      {:ok, %{pid: pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Lists all memory modules in a given zone.
  """
  @spec by_zone(integer()) :: [map()]
  def by_zone(zone_id) do
    case :ets.lookup(@index_by_zone, zone_id) do
      [{^zone_id, pac_ids}] ->
        pac_ids
        |> Enum.map(&lookup_memory/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, entry} -> entry end)

      [] ->
        []
    end
  end

  @doc """
  Lists all memory modules with a given state.
  """
  @spec by_state(atom()) :: [map()]
  def by_state(state) do
    case :ets.lookup(@index_by_state, state) do
      [{^state, pac_ids}] ->
        pac_ids
        |> Enum.map(&lookup_memory/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, entry} -> entry end)

      [] ->
        []
    end
  end

  @doc """
  Returns all registered memory modules.
  """
  @spec all_memory_modules() :: [map()]
  def all_memory_modules do
    :ets.match_object(@table_name, {{:memory, :_}, :_})
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  @doc """
  Returns the count of registered memory modules.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.select_count(@table_name, [
      {{{:memory, :_}, :_}, [], [true]}
    ])
  end

  @doc """
  Returns aggregate statistics about registered memory modules.
  """
  @spec stats() :: map()
  def stats do
    modules = all_memory_modules()

    %{
      total_count: length(modules),
      by_zone: Enum.group_by(modules, & &1.zone_id) |> Map.new(fn {k, v} -> {k, length(v)} end),
      by_state: Enum.group_by(modules, & &1.state) |> Map.new(fn {k, v} -> {k, length(v)} end),
      oldest_registered:
        modules
        |> Enum.min_by(& &1.registered_at, DateTime, fn -> nil end)
        |> case do
          nil -> nil
          m -> m.registered_at
        end
    }
  end

  @doc """
  Updates the state of a memory module.
  """
  @spec update_state(String.t(), atom()) :: :ok | {:error, :not_found}
  def update_state(pac_id, new_state) do
    GenServer.call(__MODULE__, {:update_state, pac_id, new_state})
  end

  @doc """
  Updates metrics for a memory module.
  """
  @spec update_metrics(String.t(), map()) :: :ok | {:error, :not_found}
  def update_metrics(pac_id, metrics) do
    GenServer.call(__MODULE__, {:update_metrics, pac_id, metrics})
  end

  @doc """
  Clears all registered memory modules.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@index_by_zone, [:set, :public, :named_table])
    :ets.new(@index_by_state, [:set, :public, :named_table])

    Logger.info("[Thunderpac.Registry] Registry started")

    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call({:register_memory, pac_id, pid, opts}, _from, state) do
    key = {:memory, pac_id}

    case :ets.lookup(@table_name, key) do
      [] ->
        zone_id = Keyword.get(opts, :zone_id, 0)
        config = Keyword.get(opts, :config, %{})

        entry = %{
          pac_id: pac_id,
          pid: pid,
          zone_id: zone_id,
          config: config,
          state: :active,
          registered_at: DateTime.utc_now(),
          metrics: %{
            read_count: 0,
            write_count: 0,
            decay_count: 0,
            last_activity: nil
          }
        }

        # Insert into main table
        :ets.insert(@table_name, {key, entry})

        # Update indices
        update_index(@index_by_zone, zone_id, pac_id)
        update_index(@index_by_state, :active, pac_id)

        # Monitor the process for cleanup
        ref = Process.monitor(pid)
        monitors = Map.put(state.monitors, ref, pac_id)

        Logger.debug("[Thunderpac.Registry] Registered memory module for PAC #{pac_id}")
        {:reply, :ok, %{state | monitors: monitors}}

      _ ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister_memory, pac_id}, _from, state) do
    key = {:memory, pac_id}

    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        # Remove from main table
        :ets.delete(@table_name, key)

        # Remove from indices
        remove_from_index(@index_by_zone, entry.zone_id, pac_id)
        remove_from_index(@index_by_state, entry.state, pac_id)

        Logger.debug("[Thunderpac.Registry] Unregistered memory module for PAC #{pac_id}")
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:update_state, pac_id, new_state}, _from, state) do
    key = {:memory, pac_id}

    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        old_state = entry.state

        # Update indices
        remove_from_index(@index_by_state, old_state, pac_id)
        update_index(@index_by_state, new_state, pac_id)

        # Update entry
        updated = %{entry | state: new_state}
        :ets.insert(@table_name, {key, updated})

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_metrics, pac_id, new_metrics}, _from, state) do
    key = {:memory, pac_id}

    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        merged_metrics = Map.merge(entry.metrics, new_metrics)
        updated = %{entry | metrics: merged_metrics}
        :ets.insert(@table_name, {key, updated})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@index_by_zone)
    :ets.delete_all_objects(@index_by_state)

    Logger.info("[Thunderpac.Registry] Cleared all memory modules")
    {:reply, :ok, %{state | monitors: %{}}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {pac_id, monitors} ->
        # Clean up the entry
        key = {:memory, pac_id}

        case :ets.lookup(@table_name, key) do
          [{^key, entry}] ->
            :ets.delete(@table_name, key)
            remove_from_index(@index_by_zone, entry.zone_id, pac_id)
            remove_from_index(@index_by_state, entry.state, pac_id)
            Logger.debug("[Thunderpac.Registry] Cleaned up memory module for PAC #{pac_id} (process down)")

          [] ->
            :ok
        end

        {:noreply, %{state | monitors: monitors}}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp update_index(_table, nil, _id), do: :ok

  defp update_index(table, key, id) do
    case :ets.lookup(table, key) do
      [{^key, ids}] ->
        :ets.insert(table, {key, [id | ids] |> Enum.uniq()})

      [] ->
        :ets.insert(table, {key, [id]})
    end
  end

  defp remove_from_index(_table, nil, _id), do: :ok

  defp remove_from_index(table, key, id) do
    case :ets.lookup(table, key) do
      [{^key, ids}] ->
        new_ids = List.delete(ids, id)

        if new_ids == [] do
          :ets.delete(table, key)
        else
          :ets.insert(table, {key, new_ids})
        end

      [] ->
        :ok
    end
  end
end
