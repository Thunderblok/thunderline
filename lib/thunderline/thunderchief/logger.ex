defmodule Thunderline.Thunderchief.Logger do
  @moduledoc """
  Trajectory Logger for Thunderchief RL Training (Cerebros Integration).

  Logs state-action-reward trajectories from all Chiefs for offline
  reinforcement learning. Trajectories are stored in a format compatible
  with Cerebros training pipelines.

  ## Trajectory Format

  Each trajectory step contains:
  - `state`: Feature vector from chief observation
  - `action`: Action taken (tuple or atom)
  - `reward`: Immediate reward signal
  - `next_state`: Resulting state after action
  - `done`: Whether episode terminated
  - `metadata`: Additional context (chief, tick, timestamp)

  ## Storage Backends

  - `:ets` - In-memory for development/testing
  - `:file` - Append to JSONL file for batch training
  - `:broadway` - Stream to external collector via Broadway

  ## Usage

      # Start logger
      {:ok, pid} = Logger.start_link(backend: :file, path: "/tmp/trajectories.jsonl")

      # Log a step
      Logger.log_step(:bit, %{
        state: state_features,
        action: {:activate_pending, %{strategy: :fifo}},
        reward: 0.5,
        next_state: next_features,
        done: false
      })

      # Log complete episode
      Logger.log_episode(:vine, steps)

      # Export for training
      trajectories = Logger.export(:bit, limit: 10_000)
  """

  use GenServer
  require Logger, as: ELogger

  @type step :: %{
          state: map(),
          action: term(),
          reward: float(),
          next_state: map(),
          done: boolean(),
          metadata: map()
        }

  @type episode :: [step()]

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts the trajectory logger.

  ## Options

  - `:backend` - Storage backend (:ets | :file | :broadway), default :ets
  - `:path` - File path for :file backend
  - `:max_steps` - Maximum steps to retain in :ets, default 100_000
  - `:name` - GenServer name, default __MODULE__
  """
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Logs a single trajectory step.
  """
  @spec log_step(atom(), step(), keyword()) :: :ok
  def log_step(chief, step, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.cast(server, {:log_step, chief, step})
  end

  @doc """
  Logs a complete episode (sequence of steps).
  """
  @spec log_episode(atom(), episode(), keyword()) :: :ok
  def log_episode(chief, steps, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.cast(server, {:log_episode, chief, steps})
  end

  @doc """
  Exports trajectories for a chief.

  ## Options

  - `:limit` - Maximum number of steps to export
  - `:since` - Only export steps after this timestamp
  - `:format` - Export format (:map | :tensor | :jsonl)
  """
  @spec export(atom(), keyword()) :: {:ok, [step()]} | {:error, term()}
  def export(chief, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, {:export, chief, opts})
  end

  @doc """
  Returns statistics about logged trajectories.
  """
  @spec stats(keyword()) :: map()
  def stats(opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, :stats)
  end

  @doc """
  Clears all logged trajectories.
  """
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, :clear)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    backend = opts[:backend] || :ets
    max_steps = opts[:max_steps] || 100_000

    state = %{
      backend: backend,
      path: opts[:path],
      max_steps: max_steps,
      tables: %{},
      counters: %{},
      file_handle: nil
    }

    state = init_backend(state)
    {:ok, state}
  end

  @impl true
  def handle_cast({:log_step, chief, step}, state) do
    enriched = enrich_step(step, chief)
    state = store_step(state, chief, enriched)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:log_episode, chief, steps}, state) do
    enriched =
      Enum.with_index(steps)
      |> Enum.map(fn {step, idx} ->
        enrich_step(step, chief)
        |> Map.put(:episode_step, idx)
      end)

    state = Enum.reduce(enriched, state, &store_step(&2, chief, &1))
    {:noreply, state}
  end

  @impl true
  def handle_call({:export, chief, opts}, _from, state) do
    result = do_export(state, chief, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      backend: state.backend,
      chiefs: Map.keys(state.counters),
      step_counts: state.counters,
      total_steps: state.counters |> Map.values() |> Enum.sum()
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    state = clear_backend(state)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close file handle if open
    if state.file_handle do
      File.close(state.file_handle)
    end

    :ok
  end

  # ===========================================================================
  # Backend Implementation
  # ===========================================================================

  defp init_backend(%{backend: :ets} = state) do
    # Create ETS tables per chief on demand
    state
  end

  defp init_backend(%{backend: :file, path: path} = state) when is_binary(path) do
    # Ensure directory exists
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    # Open file for append
    {:ok, handle} = File.open(path, [:append, :utf8])
    %{state | file_handle: handle}
  end

  defp init_backend(%{backend: :broadway} = state) do
    # Broadway integration - just track counters
    state
  end

  defp init_backend(state) do
    state
  end

  defp store_step(%{backend: :ets} = state, chief, step) do
    table = ensure_ets_table(state, chief)
    counter = Map.get(state.counters, chief, 0) + 1

    # Insert with counter as key
    :ets.insert(table, {counter, step})

    # Prune if over limit
    if counter > state.max_steps do
      prune_ets(table, counter - state.max_steps)
    end

    %{
      state
      | tables: Map.put(state.tables, chief, table),
        counters: Map.put(state.counters, chief, counter)
    }
  end

  defp store_step(%{backend: :file} = state, chief, step) do
    # Write as JSONL
    line = Jason.encode!(%{chief: chief, step: step}) <> "\n"
    IO.write(state.file_handle, line)

    counter = Map.get(state.counters, chief, 0) + 1
    %{state | counters: Map.put(state.counters, chief, counter)}
  end

  defp store_step(%{backend: :broadway} = state, chief, step) do
    # Emit to Broadway pipeline
    emit_to_broadway(chief, step)

    counter = Map.get(state.counters, chief, 0) + 1
    %{state | counters: Map.put(state.counters, chief, counter)}
  end

  defp store_step(state, _chief, _step), do: state

  defp ensure_ets_table(state, chief) do
    case Map.get(state.tables, chief) do
      nil ->
        table_name = :"thunderchief_trajectories_#{chief}"
        :ets.new(table_name, [:ordered_set, :public])

      table ->
        table
    end
  end

  defp prune_ets(table, threshold) do
    # Delete old entries
    :ets.select_delete(table, [
      {{:"$1", :_}, [{:<, :"$1", threshold}], [true]}
    ])
  end

  defp do_export(%{backend: :ets} = state, chief, opts) do
    case Map.get(state.tables, chief) do
      nil ->
        {:ok, []}

      table ->
        limit = opts[:limit] || state.max_steps

        steps =
          :ets.tab2list(table)
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.take(-limit)
          |> Enum.map(&elem(&1, 1))

        {:ok, format_export(steps, opts[:format] || :map)}
    end
  end

  defp do_export(%{backend: :file, path: path}, chief, opts) do
    # Read file and filter by chief
    limit = opts[:limit] || 10_000

    steps =
      File.stream!(path)
      |> Stream.map(&Jason.decode!/1)
      |> Stream.filter(&(&1["chief"] == to_string(chief)))
      |> Stream.take(limit)
      |> Stream.map(& &1["step"])
      |> Enum.to_list()

    {:ok, format_export(steps, opts[:format] || :map)}
  rescue
    e -> {:error, e}
  end

  defp do_export(_, _, _), do: {:ok, []}

  defp format_export(steps, :map), do: steps

  defp format_export(steps, :jsonl) do
    Enum.map(steps, &Jason.encode!/1)
  end

  defp format_export(steps, :tensor) do
    # Convert to tensor-ready format
    Enum.map(steps, fn step ->
      %{
        state: Map.get(step, :state, %{}) |> Map.values(),
        action: encode_action(step.action),
        reward: step.reward || 0.0,
        next_state: Map.get(step, :next_state, %{}) |> Map.values(),
        done: if(step.done, do: 1.0, else: 0.0)
      }
    end)
  end

  defp clear_backend(%{backend: :ets} = state) do
    Enum.each(state.tables, fn {_chief, table} ->
      :ets.delete_all_objects(table)
    end)

    %{state | counters: %{}}
  end

  defp clear_backend(%{backend: :file} = state) do
    # Truncate file
    if state.file_handle do
      File.close(state.file_handle)
    end

    if state.path do
      File.write!(state.path, "")
      {:ok, handle} = File.open(state.path, [:append, :utf8])
      %{state | file_handle: handle, counters: %{}}
    else
      %{state | counters: %{}}
    end
  end

  defp clear_backend(state), do: %{state | counters: %{}}

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp enrich_step(step, chief) do
    step
    |> Map.put(:chief, chief)
    |> Map.put(:timestamp, DateTime.utc_now())
    |> Map.put_new(:done, false)
    |> Map.put_new(:reward, 0.0)
    |> Map.put_new(:metadata, %{})
  end

  defp encode_action(action) when is_atom(action) do
    Atom.to_string(action)
  end

  defp encode_action({action, params}) when is_atom(action) do
    [Atom.to_string(action), params]
  end

  defp encode_action(action), do: action

  defp emit_to_broadway(chief, step) do
    # Emit event for Broadway consumption
    event_name = "chief.trajectory.#{chief}"

    Thunderline.Thunderflow.EventBus.publish_event(%{
      name: event_name,
      source: :thunderchief,
      payload: %{chief: chief, step: step}
    })
  rescue
    _ -> :ok
  end
end
