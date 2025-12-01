defmodule Thunderline.Thunderbit.Registry do
  @moduledoc """
  Thunderbit Registry - Runtime Lookup and Management

  Provides runtime registration and lookup of active Thunderbits.
  Uses ETS for fast, concurrent access.

  ## Features

  - Register/unregister Thunderbits
  - Lookup by ID, category, owner, or role
  - List active Thunderbits with filters
  - Automatic cleanup on process termination

  ## Usage

      # Register a Thunderbit
      :ok = Registry.register(bit)

      # Lookup by ID
      {:ok, bit} = Registry.lookup(bit_id)

      # List by category
      bits = Registry.by_category(:sensory)

      # List by owner (PAC)
      bits = Registry.by_owner("ezra_001")
  """

  use GenServer

  require Logger

  @table_name :thunderbit_registry
  @index_by_category :thunderbit_by_category
  @index_by_owner :thunderbit_by_owner
  @index_by_role :thunderbit_by_role

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
  Registers a Thunderbit in the registry.
  """
  @spec register(map()) :: :ok | {:error, :already_registered}
  def register(bit) do
    GenServer.call(__MODULE__, {:register, bit})
  end

  @doc """
  Unregisters a Thunderbit from the registry.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(bit_id) do
    GenServer.call(__MODULE__, {:unregister, bit_id})
  end

  @doc """
  Looks up a Thunderbit by ID.
  """
  @spec lookup(String.t()) :: {:ok, map()} | {:error, :not_found}
  def lookup(bit_id) do
    case :ets.lookup(@table_name, bit_id) do
      [{^bit_id, bit}] -> {:ok, bit}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all Thunderbits of a given category.
  """
  @spec by_category(atom()) :: [map()]
  def by_category(category) do
    case :ets.lookup(@index_by_category, category) do
      [{^category, ids}] ->
        ids
        |> Enum.map(&lookup/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, bit} -> bit end)

      [] ->
        []
    end
  end

  @doc """
  Lists all Thunderbits owned by a given PAC/agent.
  """
  @spec by_owner(String.t()) :: [map()]
  def by_owner(owner) do
    case :ets.lookup(@index_by_owner, owner) do
      [{^owner, ids}] ->
        ids
        |> Enum.map(&lookup/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, bit} -> bit end)

      [] ->
        []
    end
  end

  @doc """
  Lists all Thunderbits with a given role.
  """
  @spec by_role(atom()) :: [map()]
  def by_role(role) do
    case :ets.lookup(@index_by_role, role) do
      [{^role, ids}] ->
        ids
        |> Enum.map(&lookup/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, bit} -> bit end)

      [] ->
        []
    end
  end

  @doc """
  Returns all registered Thunderbits.
  """
  @spec all() :: [map()]
  def all do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, bit} -> bit end)
  end

  @doc """
  Returns the count of registered Thunderbits.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table_name, :size)
  end

  @doc """
  Clears all registered Thunderbits.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Updates a registered Thunderbit.
  """
  @spec update(String.t(), (map() -> map())) :: {:ok, map()} | {:error, :not_found}
  def update(bit_id, update_fn) do
    GenServer.call(__MODULE__, {:update, bit_id, update_fn})
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@index_by_category, [:set, :public, :named_table])
    :ets.new(@index_by_owner, [:set, :public, :named_table])
    :ets.new(@index_by_role, [:set, :public, :named_table])

    Logger.info("[Registry] Thunderbit registry started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, bit}, _from, state) do
    bit_id = bit.id

    case :ets.lookup(@table_name, bit_id) do
      [] ->
        # Insert into main table
        :ets.insert(@table_name, {bit_id, bit})

        # Update indices
        update_index(@index_by_category, bit.category, bit_id)
        update_index(@index_by_owner, bit.owner, bit_id)
        update_index(@index_by_role, bit.role, bit_id)

        Logger.debug("[Registry] Registered Thunderbit: #{bit_id}")
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister, bit_id}, _from, state) do
    case :ets.lookup(@table_name, bit_id) do
      [{^bit_id, bit}] ->
        # Remove from main table
        :ets.delete(@table_name, bit_id)

        # Remove from indices
        remove_from_index(@index_by_category, bit.category, bit_id)
        remove_from_index(@index_by_owner, bit.owner, bit_id)
        remove_from_index(@index_by_role, bit.role, bit_id)

        Logger.debug("[Registry] Unregistered Thunderbit: #{bit_id}")
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@index_by_category)
    :ets.delete_all_objects(@index_by_owner)
    :ets.delete_all_objects(@index_by_role)

    Logger.info("[Registry] Cleared all Thunderbits")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update, bit_id, update_fn}, _from, state) do
    case :ets.lookup(@table_name, bit_id) do
      [{^bit_id, bit}] ->
        new_bit = update_fn.(bit)
        :ets.insert(@table_name, {bit_id, new_bit})
        {:reply, {:ok, new_bit}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
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
