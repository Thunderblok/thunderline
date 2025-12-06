defmodule Thunderline.Thundercore.Telemetry do
  @moduledoc """
  Telemetry helpers for Thundercore subsystems.

  Provides instrumentation for:
  - Doctrine (algotype) metrics
  - Delayed gratification detection
  - Reward loop signals
  - Tick/clock events

  ## Telemetry Events

  ### Algotype Events
  - `[:thunderbolt, :automata, :algotype]` - Algotype clustering and Ising energy
  - `[:thundercore, :doctrine, :distribution]` - Doctrine distribution updates

  ### Gratification Events
  - `[:thundercore, :reward, :delayed_gratification]` - Detected dip-then-recover

  ### Reward Events
  - `[:thundercore, :reward, :computed]` - Reward signal computed

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Doctrine Layer
  """

  require Logger

  @algotype_ns [:thunderbolt, :automata, :algotype]
  @gratification_ns [:thundercore, :reward, :delayed_gratification]
  @reward_ns [:thundercore, :reward, :computed]
  @doctrine_ns [:thundercore, :doctrine, :distribution]

  # ═══════════════════════════════════════════════════════════════
  # Algotype Telemetry
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Emit telemetry for algotype metrics (clustering and Ising energy).

  ## Measurements
  - `algotype_clustering` - Same-doctrine clustering coefficient [0, 1]
  - `algotype_ising_energy` - Ising model energy from doctrine spins

  ## Metadata
  - `run_id` - CA run identifier
  - `tick` - Current tick
  - `doctrine_distribution` - Map of doctrine -> count
  """
  @spec algotype_metrics(map(), map()) :: :ok
  def algotype_metrics(measurements, metadata \\ %{}) do
    :telemetry.execute(
      @algotype_ns,
      Map.take(measurements, [:algotype_clustering, :algotype_ising_energy]),
      Map.take(metadata, [:run_id, :tick, :doctrine_distribution])
    )

    Logger.debug(
      "[Telemetry] algotype: clustering=#{measurements[:algotype_clustering]} " <>
        "ising_energy=#{measurements[:algotype_ising_energy]} run=#{metadata[:run_id]}"
    )

    :ok
  end

  @doc """
  Emit telemetry for doctrine distribution changes.

  ## Measurements
  - `entropy` - Normalized entropy of distribution [0, 1]
  - `dominant_count` - Count of most common doctrine

  ## Metadata
  - `run_id` - CA run identifier
  - `tick` - Current tick
  - `distribution` - Map of doctrine -> count
  """
  @spec doctrine_distribution(map(), map()) :: :ok
  def doctrine_distribution(measurements, metadata \\ %{}) do
    :telemetry.execute(
      @doctrine_ns,
      measurements,
      metadata
    )

    :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Gratification Telemetry
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Emit telemetry for detected delayed gratification events.

  ## Measurements
  - `depth` - Depth of the reward dip
  - `duration` - Number of ticks in dip state
  - `baseline` - Baseline reward before dip
  - `recovered_to` - Reward level after recovery

  ## Metadata
  - `run_id` - CA run identifier (optional)
  - `tick` - Current tick when detected
  - `tick_start` - Tick when dip started
  - `tick_bottom` - Tick of minimum reward
  - `tick_recover` - Tick when recovery completed
  """
  @spec delayed_gratification(map(), map()) :: :ok
  def delayed_gratification(measurements, metadata \\ %{}) do
    :telemetry.execute(
      @gratification_ns,
      Map.take(measurements, [:depth, :duration, :baseline, :recovered_to]),
      Map.take(metadata, [:run_id, :tick, :tick_start, :tick_bottom, :tick_recover])
    )

    Logger.info(
      "[Telemetry] delayed_gratification: depth=#{measurements[:depth]} " <>
        "duration=#{measurements[:duration]} ticks at tick=#{metadata[:tick]}"
    )

    :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Reward Telemetry
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Emit telemetry for computed reward signals.

  ## Measurements
  - `reward` - Computed reward value [0, 1]
  - `edge_score` - Edge-of-chaos score
  - `emergence_score` - Emergence detection score

  ## Metadata
  - `run_id` - CA run identifier
  - `tick` - Current tick
  - `zone` - Criticality zone (:subcritical, :critical, :supercritical)
  """
  @spec reward_computed(map(), map()) :: :ok
  def reward_computed(measurements, metadata \\ %{}) do
    :telemetry.execute(
      @reward_ns,
      measurements,
      metadata
    )

    :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Prefixes (for telemetry_metrics setup)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns all Thundercore telemetry event prefixes for metrics configuration.
  """
  @spec event_prefixes() :: [list()]
  def event_prefixes do
    [
      @algotype_ns,
      @gratification_ns,
      @reward_ns,
      @doctrine_ns
    ]
  end

  # ═══════════════════════════════════════════════════════════════
  # Telemetry Handler Attachment
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Attaches default handlers for Thundercore telemetry events.

  Call this from your application supervision tree or telemetry setup.

  ## Options
  - `:log_level` - Logger level for events (default: :debug)
  - `:handlers` - Custom handler map (optional)
  """
  @spec attach_handlers(keyword()) :: :ok
  def attach_handlers(opts \\ []) do
    log_level = Keyword.get(opts, :log_level, :debug)

    # Attach algotype handler
    :telemetry.attach(
      "thundercore-algotype-handler",
      @algotype_ns,
      &handle_algotype_event/4,
      %{log_level: log_level}
    )

    # Attach gratification handler
    :telemetry.attach(
      "thundercore-gratification-handler",
      @gratification_ns,
      &handle_gratification_event/4,
      %{log_level: log_level}
    )

    # Attach reward handler
    :telemetry.attach(
      "thundercore-reward-handler",
      @reward_ns,
      &handle_reward_event/4,
      %{log_level: log_level}
    )

    Logger.debug("[Thundercore.Telemetry] handlers attached")

    :ok
  end

  @doc """
  Detaches all Thundercore telemetry handlers.
  """
  @spec detach_handlers() :: :ok
  def detach_handlers do
    :telemetry.detach("thundercore-algotype-handler")
    :telemetry.detach("thundercore-gratification-handler")
    :telemetry.detach("thundercore-reward-handler")
    :ok
  rescue
    _ -> :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Handler Implementations
  # ═══════════════════════════════════════════════════════════════

  defp handle_algotype_event(_event, measurements, metadata, config) do
    clustering = Map.get(measurements, :algotype_clustering, 0.0)
    ising = Map.get(measurements, :algotype_ising_energy, 0.0)
    run_id = Map.get(metadata, :run_id, "unknown")
    tick = Map.get(metadata, :tick, 0)

    log_message =
      "[Algotype] run=#{run_id} tick=#{tick} clustering=#{Float.round(clustering, 3)} ising=#{Float.round(ising, 3)}"

    Logger.log(config.log_level, log_message)
  end

  defp handle_gratification_event(_event, measurements, metadata, config) do
    depth = Map.get(measurements, :depth, 0.0)
    duration = Map.get(measurements, :duration, 0)
    tick = Map.get(metadata, :tick, 0)

    log_message =
      "[Gratification] detected at tick=#{tick} depth=#{Float.round(depth, 3)} duration=#{duration}"

    Logger.log(config.log_level, log_message)
  end

  defp handle_reward_event(_event, measurements, metadata, config) do
    reward = Map.get(measurements, :reward, 0.0)
    zone = Map.get(metadata, :zone, :unknown)
    run_id = Map.get(metadata, :run_id, "unknown")

    log_message = "[Reward] run=#{run_id} reward=#{Float.round(reward, 3)} zone=#{zone}"

    Logger.log(config.log_level, log_message)
  end
end
