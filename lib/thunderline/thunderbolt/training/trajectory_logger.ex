defmodule Thunderline.Thunderbolt.Training.TrajectoryLogger do
  @moduledoc """
  Enhanced Trajectory Logger for ML Training Pipeline.

  Extends Thunderchief.Logger with training-specific features:
  - Training-ready feature extraction
  - Batch export to NumPy-compatible formats
  - Streaming to Python training pipelines
  - Episode segmentation for RL

  ## Architecture

  ```
  Thunderbit Protocol ─────┐
                          │
  Thunderchief Chiefs ────┼──▶ TrajectoryLogger ──▶ TrainingDataset
                          │         │
  BitChief Evaluations ───┘         │
                                    ▼
                            Python TPE/Keras
  ```

  ## Usage

      # Start logger
      {:ok, pid} = TrajectoryLogger.start_link(
        backend: :ets,
        export_path: "priv/training_data/trajectories",
        batch_size: 1000
      )

      # Log a trajectory step from Thunderbit
      TrajectoryLogger.log_thunderbit_step(bit, action, reward, next_bit, context)

      # Log from Chief evaluation
      TrajectoryLogger.log_chief_step(:bit, state, action, outcome)

      # Export for training
      {:ok, data} = TrajectoryLogger.export_training_batch(:bit, limit: 10_000)

      # Stream to Python
      TrajectoryLogger.stream_to_file("training_data.jsonl")

  ## Event Integration

  Also publishes trajectory events for real-time monitoring:

      {:ok, ev} = EventBus.publish_event(%{
        name: "ml.trajectory.step",
        source: :training,
        payload: %{chief: :bit, step: step}
      })
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Training.FeatureExtractor

  @type step :: %{
          state: [float()],
          action: term(),
          action_idx: non_neg_integer(),
          reward: float(),
          next_state: [float()],
          done: boolean(),
          metadata: map()
        }

  @type episode :: [step()]

  # Action space indices for Chief actions
  @chief_action_indices %{
    # BitChief actions
    wait: 0,
    consolidate: 1,
    checkpoint: 2,
    activate_pending: 3,
    transition: 4,
    cerebros_evaluate: 5,
    # VineChief actions
    spawn_workflow: 10,
    prune_stale: 11,
    rebalance: 12,
    # CrownChief actions
    apply_policy: 20,
    adjust_governance: 21,
    # UIChief actions
    refresh_view: 30,
    sync_state: 31
  }

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts the trajectory logger.

  ## Options

  - `:backend` - Storage backend (:ets | :file), default :ets
  - `:export_path` - Directory for exported files
  - `:batch_size` - Steps per batch export, default 1000
  - `:max_steps` - Maximum steps in ETS, default 100_000
  - `:name` - GenServer name, default __MODULE__
  """
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Logs a trajectory step from a Thunderbit lifecycle event.

  Extracts features from both bit states and logs the transition.
  """
  @spec log_thunderbit_step(map(), term(), float(), map(), map(), keyword()) :: :ok
  def log_thunderbit_step(bit, action, reward, next_bit, context, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.cast(server, {:log_thunderbit_step, bit, action, reward, next_bit, context})
  end

  @doc """
  Logs a trajectory step from a Chief observation cycle.

  Uses State.to_features/1 for state extraction.
  """
  @spec log_chief_step(atom(), map(), term(), map(), keyword()) :: :ok
  def log_chief_step(chief, state, action, outcome, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.cast(server, {:log_chief_step, chief, state, action, outcome})
  end

  @doc """
  Logs a complete episode (e.g., full Thunderbit lifecycle from spawn to retire).
  """
  @spec log_episode(atom(), episode(), keyword()) :: :ok
  def log_episode(source, steps, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.cast(server, {:log_episode, source, steps})
  end

  @doc """
  Exports training data for a source in ML-ready format.

  ## Options

  - `:limit` - Maximum steps to export
  - `:format` - :numpy | :json | :tensor
  - `:since` - Only export after timestamp
  """
  @spec export_training_batch(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def export_training_batch(source, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, {:export_training_batch, source, opts}, 30_000)
  end

  @doc """
  Exports all trajectory data to a JSONL file for Python consumption.
  """
  @spec stream_to_file(String.t(), keyword()) :: :ok | {:error, term()}
  def stream_to_file(path, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, {:stream_to_file, path, opts}, 60_000)
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
  Clears all trajectory data for a source or all sources.
  """
  @spec clear(atom() | :all, keyword()) :: :ok
  def clear(source \\ :all, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, {:clear, source})
  end

  @doc """
  Gets the action index for a Chief action.
  """
  @spec action_to_index(term()) :: non_neg_integer()
  def action_to_index(action) when is_atom(action) do
    Map.get(@chief_action_indices, action, 99)
  end

  def action_to_index({action, _params}) when is_atom(action) do
    Map.get(@chief_action_indices, action, 99)
  end

  def action_to_index(_), do: 99

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    export_path = opts[:export_path] || "priv/training_data/trajectories"
    File.mkdir_p!(export_path)

    state = %{
      backend: opts[:backend] || :ets,
      export_path: export_path,
      batch_size: opts[:batch_size] || 1000,
      max_steps: opts[:max_steps] || 100_000,
      tables: %{},
      counters: %{},
      episode_buffers: %{}
    }

    Logger.info("[TrajectoryLogger] Started with backend=#{state.backend}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:log_thunderbit_step, bit, action, reward, next_bit, context}, state) do
    # Extract features from bits
    {:ok, state_features} = FeatureExtractor.extract(bit, context)
    {:ok, next_state_features} = FeatureExtractor.extract(next_bit, context)

    step = %{
      state: state_features.vector,
      action: encode_action(action),
      action_idx: action_to_index(action),
      reward: reward,
      next_state: next_state_features.vector,
      done: Map.get(next_bit, :status) in [:retired, :archived],
      metadata: %{
        bit_id: bit.id,
        category: bit.category,
        tick: Map.get(context, :tick, 0),
        timestamp: DateTime.utc_now()
      }
    }

    state = store_step(state, :thunderbit, step)
    maybe_publish_event(:thunderbit, step)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:log_chief_step, chief, chief_state, action, outcome}, state) do
    # Extract features from chief state
    state_features = extract_chief_features(chief_state)
    next_features = extract_chief_features(Map.get(outcome, :next_state, chief_state))

    step = %{
      state: state_features,
      action: encode_action(action),
      action_idx: action_to_index(action),
      reward: calculate_reward(outcome),
      next_state: next_features,
      done: false,
      metadata: %{
        chief: chief,
        tick: Map.get(chief_state, :tick, 0),
        success: Map.get(outcome, :success?, true),
        timestamp: DateTime.utc_now()
      }
    }

    state = store_step(state, chief, step)
    maybe_publish_event(chief, step)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:log_episode, source, steps}, state) do
    enriched =
      steps
      |> Enum.with_index()
      |> Enum.map(fn {step, idx} ->
        step
        |> Map.put(:episode_step, idx)
        |> Map.put(:episode_length, length(steps))
        |> Map.update(:done, false, fn done ->
          done || idx == length(steps) - 1
        end)
      end)

    state = Enum.reduce(enriched, state, &store_step(&2, source, &1))
    {:noreply, state}
  end

  @impl true
  def handle_call({:export_training_batch, source, opts}, _from, state) do
    result = do_export(state, source, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:stream_to_file, path, opts}, _from, state) do
    result = do_stream_to_file(state, path, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      backend: state.backend,
      sources: Map.keys(state.counters),
      step_counts: state.counters,
      total_steps: state.counters |> Map.values() |> Enum.sum(),
      export_path: state.export_path,
      batch_size: state.batch_size
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:clear, :all}, _from, state) do
    Enum.each(state.tables, fn {_source, table} ->
      :ets.delete_all_objects(table)
    end)

    {:reply, :ok, %{state | counters: %{}}}
  end

  @impl true
  def handle_call({:clear, source}, _from, state) do
    case Map.get(state.tables, source) do
      nil -> :ok
      table -> :ets.delete_all_objects(table)
    end

    {:reply, :ok, %{state | counters: Map.delete(state.counters, source)}}
  end

  # ===========================================================================
  # Storage
  # ===========================================================================

  defp store_step(%{backend: :ets} = state, source, step) do
    table = ensure_ets_table(state, source)
    counter = Map.get(state.counters, source, 0) + 1

    # Insert with monotonic key
    :ets.insert(table, {counter, step})

    # Prune if over limit
    if counter > state.max_steps do
      prune_ets(table, counter - state.max_steps)
    end

    %{
      state
      | tables: Map.put(state.tables, source, table),
        counters: Map.put(state.counters, source, counter)
    }
  end

  defp store_step(%{backend: :file} = state, source, step) do
    # Append to source-specific file
    path = Path.join(state.export_path, "#{source}_trajectories.jsonl")
    line = Jason.encode!(%{source: source, step: step}) <> "\n"
    File.write!(path, line, [:append])

    counter = Map.get(state.counters, source, 0) + 1
    %{state | counters: Map.put(state.counters, source, counter)}
  end

  defp ensure_ets_table(state, source) do
    case Map.get(state.tables, source) do
      nil ->
        table_name = :"training_trajectories_#{source}"
        :ets.new(table_name, [:ordered_set, :public])

      table ->
        table
    end
  end

  defp prune_ets(table, threshold) do
    :ets.select_delete(table, [
      {{:"$1", :_}, [{:<, :"$1", threshold}], [true]}
    ])
  end

  # ===========================================================================
  # Export
  # ===========================================================================

  defp do_export(%{backend: :ets} = state, source, opts) do
    case Map.get(state.tables, source) do
      nil ->
        {:ok, empty_training_batch()}

      table ->
        limit = opts[:limit] || state.max_steps

        steps =
          :ets.tab2list(table)
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.take(-limit)
          |> Enum.map(&elem(&1, 1))

        format_training_batch(steps, opts[:format] || :numpy)
    end
  end

  defp do_export(%{backend: :file, export_path: export_path}, source, opts) do
    path = Path.join(export_path, "#{source}_trajectories.jsonl")
    limit = opts[:limit] || 10_000

    steps =
      if File.exists?(path) do
        File.stream!(path)
        |> Stream.map(&Jason.decode!/1)
        |> Stream.map(& &1["step"])
        |> Stream.take(limit)
        |> Enum.to_list()
      else
        []
      end

    format_training_batch(steps, opts[:format] || :numpy)
  rescue
    e -> {:error, e}
  end

  defp empty_training_batch do
    %{
      states: [],
      actions: [],
      rewards: [],
      next_states: [],
      dones: [],
      count: 0
    }
  end

  defp format_training_batch(steps, :numpy) do
    # Format for NumPy consumption
    batch = %{
      states: Enum.map(steps, & &1.state),
      actions: Enum.map(steps, & &1.action_idx),
      rewards: Enum.map(steps, & &1.reward),
      next_states: Enum.map(steps, & &1.next_state),
      dones: Enum.map(steps, &if(&1.done, do: 1.0, else: 0.0)),
      count: length(steps)
    }

    {:ok, batch}
  end

  defp format_training_batch(steps, :json) do
    {:ok, steps}
  end

  defp format_training_batch(steps, :tensor) do
    # Prepare for Nx/Axon tensors
    batch = %{
      states: steps |> Enum.map(& &1.state) |> Enum.map(&List.flatten/1),
      actions: Enum.map(steps, & &1.action_idx),
      rewards: Enum.map(steps, & &1.reward),
      next_states: steps |> Enum.map(& &1.next_state) |> Enum.map(&List.flatten/1),
      dones: Enum.map(steps, &if(&1.done, do: 1.0, else: 0.0)),
      count: length(steps)
    }

    {:ok, batch}
  end

  defp do_stream_to_file(state, path, opts) do
    sources = opts[:sources] || Map.keys(state.counters)

    File.open!(path, [:write, :utf8], fn file ->
      for source <- sources do
        case Map.get(state.tables, source) do
          nil ->
            :ok

          table ->
            :ets.tab2list(table)
            |> Enum.sort_by(&elem(&1, 0))
            |> Enum.each(fn {_idx, step} ->
              line = Jason.encode!(%{source: source, step: step})
              IO.puts(file, line)
            end)
        end
      end
    end)

    :ok
  rescue
    e -> {:error, e}
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp encode_action(action) when is_atom(action) do
    Atom.to_string(action)
  end

  defp encode_action({action, _params}) when is_atom(action) do
    Atom.to_string(action)
  end

  defp encode_action(action), do: inspect(action)

  defp extract_chief_features(nil), do: List.duplicate(0.0, 16)

  defp extract_chief_features(chief_state) when is_map(chief_state) do
    # Extract numeric features from chief state
    [
      Map.get(chief_state, :active_count, 0) / 100.0,
      Map.get(chief_state, :pending_count, 0) / 100.0,
      Map.get(chief_state, :total_energy, 0.0),
      Map.get(chief_state, :avg_health, 0.5),
      Map.get(chief_state, :avg_salience, 0.5),
      Map.get(chief_state, :tick, 0) / 10000.0,
      Map.get(chief_state, :workflow_count, 0) / 50.0,
      Map.get(chief_state, :stale_count, 0) / 20.0,
      Map.get(chief_state, :policy_score, 0.5),
      Map.get(chief_state, :governance_level, 0.5),
      Map.get(chief_state, :ui_lag, 0.0),
      Map.get(chief_state, :sync_status, 1.0),
      # Padding for alignment
      0.0,
      0.0,
      0.0,
      0.0
    ]
  end

  defp extract_chief_features(_), do: List.duplicate(0.0, 16)

  defp calculate_reward(%{success?: true}), do: 1.0
  defp calculate_reward(%{success?: false}), do: -0.5
  defp calculate_reward(%{result: :ok}), do: 1.0
  defp calculate_reward(%{result: :noop}), do: 0.0
  defp calculate_reward(%{result: :error}), do: -1.0
  defp calculate_reward(_), do: 0.0

  defp maybe_publish_event(source, step) do
    # Publish to EventBus for real-time monitoring
    attrs = %{
      name: "ml.trajectory.step",
      source: :training,
      payload: %{
        source: source,
        action: step.action,
        reward: step.reward,
        done: step.done,
        timestamp: DateTime.utc_now()
      }
    }

    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      Thunderline.EventBus.publish_event(ev)
    end
  rescue
    _ -> :ok
  end
end
