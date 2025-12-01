defmodule Thunderline.Thunderwall.Sink do
  @moduledoc """
  Thunderwall Entropy Sink (HC-Ω-4).

  Auto-quarantine failed CA runs, archive unstable PAC lineages, and manage
  entropy overflow from the self-optimizing system.

  ## Architecture

      ┌─────────────────────────────────────────────────────────────────┐
      │                       ENTROPY SINK                              │
      │                                                                 │
      │  ┌──────────────────┐   ┌──────────────────┐                   │
      │  │ Quarantine       │   │ Archive          │                   │
      │  │ - Failed CA runs │   │ - Unstable PACs  │                   │
      │  │ - Chaos spikes   │   │ - Dead lineages  │                   │
      │  │ - Divergent bits │   │ - Expired trials │                   │
      │  └────────┬─────────┘   └────────┬─────────┘                   │
      │           │                      │                              │
      │           └──────────┬───────────┘                              │
      │                      ↓                                          │
      │  ┌──────────────────────────────────────────────────────────┐  │
      │  │               ENTROPY ALGORITHM                           │  │
      │  │                                                           │  │
      │  │  Score = f(age, chaos_level, lineage_depth, fitness)     │  │
      │  │                                                           │  │
      │  │  if score > threshold:                                    │  │
      │  │    - Move to archive                                      │  │
      │  │    - Extract patterns (for learning)                      │  │
      │  │    - Free resources                                       │  │
      │  │    - Emit decay event                                     │  │
      │  └──────────────────────────────────────────────────────────┘  │
      │                      │                                          │
      │                      ↓                                          │
      │  ┌──────────────────────────────────────────────────────────┐  │
      │  │               PATTERN EXTRACTION                          │  │
      │  │                                                           │  │
      │  │  Before discarding:                                       │  │
      │  │  - Extract failure patterns                               │  │
      │  │  - Record chaos signatures                                │  │
      │  │  - Save lineage metadata                                  │  │
      │  │  - Feed back to TPE (negative examples)                   │  │
      │  └──────────────────────────────────────────────────────────┘  │
      └─────────────────────────────────────────────────────────────────┘

  ## Quarantine Categories

  - **CA Failures**: DiffLogic runs that diverged or crashed
  - **Chaos Spikes**: Thunderbits with λ̂ > threshold for extended periods
  - **Dead Lineages**: PAC evolution branches with no fitness improvement
  - **Expired Trials**: TPE trials that timed out or produced NaN

  ## Sink Algorithm

  The entropy score determines when to archive:

  ```
  entropy_score =
    age_factor * (now - created_at) +
    chaos_factor * max(0, lambda_hat - 0.5) +
    fitness_factor * (1.0 - fitness) +
    lineage_factor * (1.0 / (lineage_depth + 1))
  ```

  When `entropy_score > threshold`, the entity is archived.

  ## Events

  - `wall.sink.quarantined` - Entity placed in quarantine
  - `wall.sink.archived` - Entity moved to archive
  - `wall.sink.pattern_extracted` - Failure pattern saved
  - `wall.sink.gc_batch` - Batch GC completed
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderwall.EntropyMetrics
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Event

  @telemetry_prefix [:thunderline, :wall, :sink]

  # Entropy thresholds
  @quarantine_threshold 0.7
  @archive_threshold 0.9
  @gc_batch_size 100

  # Score factors (tune these!)
  # Per hour
  @age_factor 0.001
  @chaos_factor 2.0
  @fitness_factor 1.5
  @lineage_factor 0.5

  # Retention periods
  @quarantine_ttl_hours 24
  @archive_ttl_days 30

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type quarantine_reason ::
          :ca_failure
          | :chaos_spike
          | :fitness_collapse
          | :lineage_death
          | :trial_timeout
          | :nan_detected
          | :manual

  @type sink_entry :: %{
          id: String.t(),
          entity_type: :ca_run | :thunderbit | :pac | :trial | :lineage,
          entity_id: String.t(),
          reason: quarantine_reason(),
          entropy_score: float(),
          metadata: map(),
          quarantined_at: DateTime.t(),
          archived_at: DateTime.t() | nil,
          pattern: map() | nil
        }

  @type pattern :: %{
          type: atom(),
          signature: map(),
          frequency: non_neg_integer(),
          last_seen: DateTime.t()
        }

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Quarantine a failed CA run.

  ## Parameters

  - `run_id` - ID of the DiffLogic CA run
  - `reason` - Why the run failed
  - `metadata` - Additional context (metrics, config, etc.)
  """
  @spec quarantine_ca_run(String.t(), quarantine_reason(), map()) ::
          {:ok, sink_entry()} | {:error, term()}
  def quarantine_ca_run(run_id, reason, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:quarantine, :ca_run, run_id, reason, metadata})
  end

  @doc """
  Quarantine a chaotic Thunderbit.
  """
  @spec quarantine_thunderbit(String.t(), map()) :: {:ok, sink_entry()} | {:error, term()}
  def quarantine_thunderbit(bit_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:quarantine, :thunderbit, bit_id, :chaos_spike, metadata})
  end

  @doc """
  Archive an unstable PAC lineage.
  """
  @spec archive_pac_lineage(String.t(), list(), map()) :: {:ok, sink_entry()} | {:error, term()}
  def archive_pac_lineage(pac_id, lineage, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:archive_lineage, pac_id, lineage, metadata})
  end

  @doc """
  Quarantine a failed TPE trial.
  """
  @spec quarantine_trial(String.t(), quarantine_reason(), map()) ::
          {:ok, sink_entry()} | {:error, term()}
  def quarantine_trial(trial_id, reason, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:quarantine, :trial, trial_id, reason, metadata})
  end

  @doc """
  Get all quarantined entries.
  """
  @spec list_quarantine() :: [sink_entry()]
  def list_quarantine do
    GenServer.call(__MODULE__, :list_quarantine)
  end

  @doc """
  Get all archived entries.
  """
  @spec list_archive() :: [sink_entry()]
  def list_archive do
    GenServer.call(__MODULE__, :list_archive)
  end

  @doc """
  Get extracted failure patterns.
  """
  @spec list_patterns() :: [pattern()]
  def list_patterns do
    GenServer.call(__MODULE__, :list_patterns)
  end

  @doc """
  Get sink statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Manually trigger GC on quarantine/archive.
  """
  @spec run_gc() :: {:ok, non_neg_integer()}
  def run_gc do
    GenServer.call(__MODULE__, :run_gc)
  end

  @doc """
  Restore an entry from quarantine (if still valid).
  """
  @spec restore(String.t()) :: {:ok, sink_entry()} | {:error, :not_found | :already_archived}
  def restore(entry_id) do
    GenServer.call(__MODULE__, {:restore, entry_id})
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Implementation
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    # Schedule periodic GC
    gc_interval = Keyword.get(opts, :gc_interval_ms, 60_000)
    Process.send_after(self(), :gc_tick, gc_interval)

    state = %{
      # id => sink_entry
      quarantine: %{},
      # id => sink_entry
      archive: %{},
      # pattern_key => pattern
      patterns: %{},
      gc_interval: gc_interval,
      stats: %{
        quarantined_total: 0,
        archived_total: 0,
        restored_total: 0,
        patterns_extracted: 0,
        gc_runs: 0
      }
    }

    Logger.info("[Thunderwall.Sink] Initialized with GC interval #{gc_interval}ms")
    {:ok, state}
  end

  @impl true
  def handle_call({:quarantine, entity_type, entity_id, reason, metadata}, _from, state) do
    entry = create_sink_entry(entity_type, entity_id, reason, metadata)
    new_quarantine = Map.put(state.quarantine, entry.id, entry)

    new_stats = Map.update!(state.stats, :quarantined_total, &(&1 + 1))

    emit_event(:quarantined, entry)
    EntropyMetrics.record_overflow()

    :telemetry.execute(
      @telemetry_prefix ++ [:quarantine],
      %{count: 1, entropy_score: entry.entropy_score},
      %{entity_type: entity_type, reason: reason}
    )

    Logger.info(
      "[Sink] Quarantined #{entity_type}:#{entity_id} reason=#{reason} score=#{Float.round(entry.entropy_score, 3)}"
    )

    {:reply, {:ok, entry}, %{state | quarantine: new_quarantine, stats: new_stats}}
  end

  @impl true
  def handle_call({:archive_lineage, pac_id, lineage, metadata}, _from, state) do
    lineage_depth = length(lineage)
    fitness_history = Enum.map(lineage, & &1.fitness)
    avg_fitness = if lineage_depth > 0, do: Enum.sum(fitness_history) / lineage_depth, else: 0

    enriched_metadata =
      Map.merge(metadata, %{
        lineage_depth: lineage_depth,
        fitness_history: fitness_history,
        avg_fitness: avg_fitness,
        lineage: lineage
      })

    entry = create_sink_entry(:lineage, pac_id, :lineage_death, enriched_metadata)

    # Extract pattern from lineage
    pattern = extract_lineage_pattern(pac_id, lineage)

    # Archive immediately (lineages go straight to archive)
    archived_entry = %{entry | archived_at: DateTime.utc_now(), pattern: pattern}
    new_archive = Map.put(state.archive, archived_entry.id, archived_entry)

    # Update patterns
    new_patterns = record_pattern(state.patterns, pattern)

    new_stats =
      state.stats
      |> Map.update!(:archived_total, &(&1 + 1))
      |> Map.update!(:patterns_extracted, &(&1 + 1))

    emit_event(:archived, archived_entry)
    emit_event(:pattern_extracted, pattern)
    EntropyMetrics.record_decay()

    Logger.info(
      "[Sink] Archived lineage #{pac_id} depth=#{lineage_depth} avg_fitness=#{Float.round(avg_fitness, 3)}"
    )

    {:reply, {:ok, archived_entry},
     %{state | archive: new_archive, patterns: new_patterns, stats: new_stats}}
  end

  @impl true
  def handle_call(:list_quarantine, _from, state) do
    entries = Map.values(state.quarantine)
    {:reply, entries, state}
  end

  @impl true
  def handle_call(:list_archive, _from, state) do
    entries = Map.values(state.archive)
    {:reply, entries, state}
  end

  @impl true
  def handle_call(:list_patterns, _from, state) do
    patterns = Map.values(state.patterns)
    {:reply, patterns, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        quarantine_count: map_size(state.quarantine),
        archive_count: map_size(state.archive),
        pattern_count: map_size(state.patterns)
      })

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:run_gc, _from, state) do
    {new_state, collected} = do_gc(state)
    {:reply, {:ok, collected}, new_state}
  end

  @impl true
  def handle_call({:restore, entry_id}, _from, state) do
    case Map.get(state.quarantine, entry_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        if entry.archived_at do
          {:reply, {:error, :already_archived}, state}
        else
          new_quarantine = Map.delete(state.quarantine, entry_id)
          new_stats = Map.update!(state.stats, :restored_total, &(&1 + 1))

          Logger.info("[Sink] Restored #{entry.entity_type}:#{entry.entity_id}")

          {:reply, {:ok, entry}, %{state | quarantine: new_quarantine, stats: new_stats}}
        end
    end
  end

  @impl true
  def handle_info(:gc_tick, state) do
    {new_state, collected} = do_gc(state)

    if collected > 0 do
      Logger.debug("[Sink] GC collected #{collected} entries")
    end

    Process.send_after(self(), :gc_tick, state.gc_interval)
    {:noreply, new_state}
  end

  # ═══════════════════════════════════════════════════════════════
  # Core Logic
  # ═══════════════════════════════════════════════════════════════

  defp create_sink_entry(entity_type, entity_id, reason, metadata) do
    now = DateTime.utc_now()
    entropy_score = compute_entropy_score(metadata, now)

    %{
      id: "sink_#{System.unique_integer([:positive])}",
      entity_type: entity_type,
      entity_id: entity_id,
      reason: reason,
      entropy_score: entropy_score,
      metadata: metadata,
      quarantined_at: now,
      archived_at: nil,
      pattern: nil
    }
  end

  @doc """
  Computes entropy score for an entity.

  Higher score = more likely to be archived.
  """
  @spec compute_entropy_score(map(), DateTime.t()) :: float()
  def compute_entropy_score(metadata, now \\ DateTime.utc_now()) do
    # Age factor
    created_at = Map.get(metadata, :created_at, now)
    age_hours = DateTime.diff(now, created_at, :hour)
    age_score = @age_factor * age_hours

    # Chaos factor (from lambda_hat)
    lambda_hat = Map.get(metadata, :lambda_hat, 0.273)
    chaos_score = @chaos_factor * max(0, lambda_hat - 0.5)

    # Fitness factor (low fitness = high entropy)
    fitness = Map.get(metadata, :fitness, 0.5)
    fitness_score = @fitness_factor * (1.0 - fitness)

    # Lineage factor (shallow lineages are more expendable)
    lineage_depth = Map.get(metadata, :lineage_depth, 1)
    lineage_score = @lineage_factor * (1.0 / (lineage_depth + 1))

    # Combine scores
    raw_score = age_score + chaos_score + fitness_score + lineage_score

    # Normalize to [0, 1]
    min(1.0, raw_score)
  end

  defp do_gc(state) do
    now = DateTime.utc_now()

    # 1. Promote quarantine entries with high entropy to archive
    {quarantine_to_archive, remaining_quarantine} =
      state.quarantine
      |> Map.to_list()
      |> Enum.split_with(fn {_id, entry} ->
        entry.entropy_score >= @archive_threshold or
          quarantine_expired?(entry, now)
      end)

    # 2. Archive promoted entries
    {new_archive, patterns_extracted} =
      Enum.reduce(quarantine_to_archive, {state.archive, []}, fn {id, entry},
                                                                 {archive, patterns} ->
        pattern = extract_failure_pattern(entry)
        archived_entry = %{entry | archived_at: now, pattern: pattern}

        emit_event(:archived, archived_entry)
        EntropyMetrics.record_decay()

        {Map.put(archive, id, archived_entry), [pattern | patterns]}
      end)

    # 3. Clean up old archive entries
    {_, remaining_archive} =
      new_archive
      |> Map.to_list()
      |> Enum.split_with(fn {_id, entry} ->
        archive_expired?(entry, now)
      end)

    # 4. Update patterns
    new_patterns =
      patterns_extracted
      |> Enum.filter(fn x -> x end)
      |> Enum.reduce(state.patterns, &record_pattern(&2, &1))

    # 5. Update stats
    collected = length(quarantine_to_archive)
    valid_patterns_count = patterns_extracted |> Enum.filter(fn x -> x end) |> length()

    new_stats =
      state.stats
      |> Map.update!(:archived_total, &(&1 + collected))
      |> Map.update!(:patterns_extracted, &(&1 + valid_patterns_count))
      |> Map.update!(:gc_runs, &(&1 + 1))

    if collected > 0 do
      emit_event(:gc_batch, %{collected: collected, archived: length(quarantine_to_archive)})
      EntropyMetrics.record_gc(collected)

      :telemetry.execute(
        @telemetry_prefix ++ [:gc],
        %{collected: collected},
        %{}
      )
    end

    new_state = %{
      state
      | quarantine: Map.new(remaining_quarantine),
        archive: Map.new(remaining_archive),
        patterns: new_patterns,
        stats: new_stats
    }

    {new_state, collected}
  end

  defp quarantine_expired?(entry, now) do
    hours_in_quarantine = DateTime.diff(now, entry.quarantined_at, :hour)
    hours_in_quarantine >= @quarantine_ttl_hours
  end

  defp archive_expired?(entry, now) do
    case entry.archived_at do
      nil ->
        false

      archived_at ->
        days_archived = DateTime.diff(now, archived_at, :day)
        days_archived >= @archive_ttl_days
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Pattern Extraction
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Extracts a failure pattern from a sink entry.

  Patterns are used to improve the system by learning from failures.
  """
  @spec extract_failure_pattern(sink_entry()) :: pattern() | nil
  def extract_failure_pattern(entry) do
    signature =
      case entry.entity_type do
        :ca_run ->
          %{
            reason: entry.reason,
            lambda_hat: Map.get(entry.metadata, :lambda_hat),
            entropy: Map.get(entry.metadata, :entropy),
            config: Map.get(entry.metadata, :config, %{})
          }

        :thunderbit ->
          %{
            reason: entry.reason,
            lambda_hat: Map.get(entry.metadata, :lambda_hat),
            sigma_flow: Map.get(entry.metadata, :sigma_flow),
            coord: Map.get(entry.metadata, :coord)
          }

        :trial ->
          %{
            reason: entry.reason,
            params: Map.get(entry.metadata, :params, %{}),
            fitness: Map.get(entry.metadata, :fitness)
          }

        _ ->
          %{reason: entry.reason}
      end

    %{
      type: entry.entity_type,
      signature: signature,
      frequency: 1,
      last_seen: DateTime.utc_now()
    }
  end

  defp extract_lineage_pattern(pac_id, lineage) do
    # Analyze lineage for patterns
    fitness_trend =
      lineage
      |> Enum.map(& &1.fitness)
      |> detect_trend()

    lambda_values = Enum.map(lineage, &Map.get(&1, :lambda_hat, 0.273))

    avg_lambda =
      if length(lambda_values) > 0,
        do: Enum.sum(lambda_values) / length(lambda_values),
        else: 0.273

    %{
      type: :lineage,
      signature: %{
        pac_id: pac_id,
        lineage_depth: length(lineage),
        fitness_trend: fitness_trend,
        avg_lambda: avg_lambda,
        final_fitness: List.last(lineage)[:fitness] || 0
      },
      frequency: 1,
      last_seen: DateTime.utc_now()
    }
  end

  defp detect_trend([]), do: :flat
  defp detect_trend([_]), do: :flat

  defp detect_trend(values) do
    pairs = Enum.zip(values, tl(values))
    diffs = Enum.map(pairs, fn {a, b} -> b - a end)

    positive = Enum.count(diffs, &(&1 > 0.01))
    negative = Enum.count(diffs, &(&1 < -0.01))

    cond do
      positive > negative * 2 -> :improving
      negative > positive * 2 -> :declining
      true -> :stagnant
    end
  end

  defp record_pattern(patterns, nil), do: patterns

  defp record_pattern(patterns, pattern) do
    key = pattern_key(pattern)

    Map.update(patterns, key, pattern, fn existing ->
      %{existing | frequency: existing.frequency + 1, last_seen: pattern.last_seen}
    end)
  end

  defp pattern_key(pattern) do
    # Create a unique key from pattern signature
    :erlang.phash2({pattern.type, pattern.signature.reason})
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Emission
  # ═══════════════════════════════════════════════════════════════

  defp emit_event(event_type, data) do
    event_name = "wall.sink.#{event_type}"

    payload =
      case data do
        %{id: _} = entry ->
          %{
            entry_id: entry.id,
            entity_type: entry.entity_type,
            entity_id: entry.entity_id,
            reason: entry.reason,
            entropy_score: entry.entropy_score,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }

        %{type: _} = pattern ->
          %{
            pattern_type: pattern.type,
            frequency: pattern.frequency,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }

        other when is_map(other) ->
          Map.put(other, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
      end

    case Event.new(name: event_name, source: :wall, payload: payload, meta: %{pipeline: :async}) do
      {:ok, event} ->
        EventBus.publish_event(event)

      {:error, reason} ->
        Logger.warning("[Sink] Failed to emit event: #{inspect(reason)}")
    end
  end
end
