defmodule Thunderline.Thunderwall.Sandbox do
  @moduledoc """
  Soft sandbox operations for Thunderwall containment.

  HC-Ω-10: Provides high-level API for sandbox operations:
  - `freeze_chunk/2` - Temporarily freeze a chunk's CA execution
  - `mirror_replay/3` - Replay historical tick range for a chunk
  - `decay_override/2` - Override PAC decay factor temporarily
  - `segment_quarantine/1` - Isolate a segment from normal processing

  All operations are logged to `SandboxLog` resource and emit
  `wall.sandbox.*` events for observability.

  ## Safety Model

  Sandbox operations are designed to be:
  - **Reversible**: All operations can be cancelled or will expire
  - **Auditable**: Every operation creates a log entry
  - **Observable**: Events emitted for monitoring
  - **Bounded**: Operations have maximum durations

  ## Usage

      # Freeze a chaotic chunk for 100 ticks
      Sandbox.freeze_chunk("chunk_001", 100, reason: "chaos containment")

      # Replay chunk history for analysis
      Sandbox.mirror_replay("chunk_001", 1000, 1100)

      # Slow down PAC decay
      Sandbox.decay_override("pac_123", 0.5, duration_hours: 12)

      # Quarantine a problematic segment
      Sandbox.segment_quarantine("segment_xyz", isolation_level: :full)
  """

  require Logger

  alias Thunderline.Thunderwall.Resources.SandboxLog

  @max_freeze_ticks 10_000
  @max_replay_range 1_000
  @max_decay_factor 10.0
  @default_decay_hours 24

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Freeze a chunk's CA execution for a specified number of ticks.

  During freeze:
  - Thunderbit cells in the chunk do not update
  - Reflex evaluations are skipped
  - Events are still captured but not processed

  ## Options

  - `:reason` - Human-readable reason for freeze
  - `:triggered_by` - Source identifier (handler, user, etc.)

  ## Examples

      # Freeze for 100 ticks
      Sandbox.freeze_chunk("chunk_001", 100)

      # Freeze with reason
      Sandbox.freeze_chunk("chunk_001", 200, reason: "chaos spike containment")
  """
  @spec freeze_chunk(String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def freeze_chunk(chunk_id, ticks, opts \\ []) when is_binary(chunk_id) and is_integer(ticks) do
    if ticks <= 0 or ticks > @max_freeze_ticks do
      {:error, {:invalid_ticks, "ticks must be between 1 and #{@max_freeze_ticks}"}}
    else
      reason = Keyword.get(opts, :reason, "Manual freeze")
      triggered_by = Keyword.get(opts, :triggered_by, "sandbox_api")

      Logger.info("[Sandbox] Freezing chunk #{chunk_id} for #{ticks} ticks")

      case SandboxLog.log_freeze(%{
             target_id: chunk_id,
             ticks: ticks,
             reason: reason,
             triggered_by: triggered_by
           }) do
        {:ok, log} ->
          # Apply the actual freeze effect
          apply_freeze_effect(chunk_id, ticks, log.id)
          {:ok, %{log_id: log.id, chunk_id: chunk_id, ticks: ticks, expires_at: log.expires_at}}

        {:error, reason} = err ->
          Logger.error("[Sandbox] Failed to log freeze: #{inspect(reason)}")
          err
      end
    end
  end

  @doc """
  Replay historical tick range for a chunk (mirror replay).

  Creates a read-only replay of chunk state between two ticks,
  useful for debugging and analysis without affecting live state.

  ## Options

  - `:reason` - Reason for replay
  - `:triggered_by` - Source identifier

  ## Examples

      # Replay ticks 1000-1100
      Sandbox.mirror_replay("chunk_001", 1000, 1100)
  """
  @spec mirror_replay(String.t(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def mirror_replay(chunk_id, start_tick, end_tick, opts \\ [])
      when is_binary(chunk_id) and is_integer(start_tick) and is_integer(end_tick) do
    cond do
      start_tick >= end_tick ->
        {:error, {:invalid_range, "start_tick must be less than end_tick"}}

      end_tick - start_tick > @max_replay_range ->
        {:error, {:range_too_large, "replay range cannot exceed #{@max_replay_range} ticks"}}

      true ->
        reason = Keyword.get(opts, :reason, "Historical analysis")
        triggered_by = Keyword.get(opts, :triggered_by, "sandbox_api")

        Logger.info(
          "[Sandbox] Starting mirror replay for chunk #{chunk_id}: #{start_tick}-#{end_tick}"
        )

        case SandboxLog.log_replay(%{
               target_id: chunk_id,
               start_tick: start_tick,
               end_tick: end_tick,
               reason: reason,
               triggered_by: triggered_by
             }) do
          {:ok, log} ->
            # Start replay process
            replay_result = start_mirror_replay(chunk_id, start_tick, end_tick, log.id)

            {:ok,
             %{
               log_id: log.id,
               chunk_id: chunk_id,
               tick_range: {start_tick, end_tick},
               replay_id: replay_result
             }}

          {:error, reason} = err ->
            Logger.error("[Sandbox] Failed to log replay: #{inspect(reason)}")
            err
        end
    end
  end

  @doc """
  Override decay factor for a PAC temporarily.

  Factor values:
  - `< 1.0` - Slower decay (memories persist longer)
  - `= 1.0` - Normal decay
  - `> 1.0` - Faster decay (memories fade quicker)

  ## Options

  - `:duration_hours` - How long override lasts (default: 24)
  - `:reason` - Reason for override
  - `:triggered_by` - Source identifier

  ## Examples

      # Slow down decay by half
      Sandbox.decay_override("pac_123", 0.5)

      # Speed up decay for 12 hours
      Sandbox.decay_override("pac_123", 2.0, duration_hours: 12)
  """
  @spec decay_override(String.t(), float(), keyword()) :: {:ok, map()} | {:error, term()}
  def decay_override(pac_id, factor, opts \\ [])
      when is_binary(pac_id) and is_float(factor) do
    if factor < 0.0 or factor > @max_decay_factor do
      {:error, {:invalid_factor, "factor must be between 0.0 and #{@max_decay_factor}"}}
    else
      duration_hours = Keyword.get(opts, :duration_hours, @default_decay_hours)
      reason = Keyword.get(opts, :reason, "Manual decay adjustment")
      triggered_by = Keyword.get(opts, :triggered_by, "sandbox_api")

      Logger.info("[Sandbox] Setting decay override for PAC #{pac_id}: factor=#{factor}")

      case SandboxLog.log_decay_override(%{
             target_id: pac_id,
             factor: factor,
             duration_hours: duration_hours,
             reason: reason,
             triggered_by: triggered_by
           }) do
        {:ok, log} ->
          # Apply decay factor
          apply_decay_override(pac_id, factor, log.id)

          {:ok,
           %{
             log_id: log.id,
             pac_id: pac_id,
             factor: factor,
             expires_at: log.expires_at
           }}

        {:error, reason} = err ->
          Logger.error("[Sandbox] Failed to log decay override: #{inspect(reason)}")
          err
      end
    end
  end

  @doc """
  Quarantine a segment, isolating it from normal processing.

  Quarantined segments:
  - Do not receive new events
  - Do not participate in reflex evaluation
  - State is preserved but frozen

  ## Options

  - `:isolation_level` - `:partial` (default) or `:full`
  - `:reason` - Reason for quarantine
  - `:triggered_by` - Source identifier

  ## Examples

      # Partial quarantine (events logged but not processed)
      Sandbox.segment_quarantine("segment_xyz")

      # Full quarantine (complete isolation)
      Sandbox.segment_quarantine("segment_xyz", isolation_level: :full)
  """
  @spec segment_quarantine(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def segment_quarantine(segment_id, opts \\ []) when is_binary(segment_id) do
    isolation_level = Keyword.get(opts, :isolation_level, :partial)
    reason = Keyword.get(opts, :reason, "Segment quarantine")
    triggered_by = Keyword.get(opts, :triggered_by, "sandbox_api")

    Logger.warning("[Sandbox] Quarantining segment #{segment_id} (level: #{isolation_level})")

    case SandboxLog.log_quarantine(%{
           target_id: segment_id,
           isolation_level: isolation_level,
           reason: reason,
           triggered_by: triggered_by
         }) do
      {:ok, log} ->
        # Apply quarantine
        apply_quarantine(segment_id, isolation_level, log.id)

        {:ok,
         %{
           log_id: log.id,
           segment_id: segment_id,
           isolation_level: isolation_level
         }}

      {:error, reason} = err ->
        Logger.error("[Sandbox] Failed to log quarantine: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Release an active sandbox operation.

  Cancels an active freeze, replay, override, or quarantine.

  ## Examples

      Sandbox.release(log_id, reason: "Manual release")
  """
  @spec release(Ash.UUID.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def release(log_id, opts \\ []) do
    cancel_reason = Keyword.get(opts, :reason, "Manual release")

    case Ash.get(SandboxLog, log_id) do
      {:ok, log} ->
        if log.status == :active do
          case SandboxLog.cancel(log, %{cancel_reason: cancel_reason}) do
            {:ok, updated_log} ->
              release_effect(updated_log)
              {:ok, %{log_id: updated_log.id, status: :cancelled}}

            {:error, reason} = err ->
              Logger.error("[Sandbox] Failed to cancel operation: #{inspect(reason)}")
              err
          end
        else
          {:error, {:not_active, "Operation is not active (status: #{log.status})"}}
        end

      {:error, _} ->
        {:error, {:not_found, "Sandbox log not found"}}
    end
  end

  @doc """
  List all active sandbox operations.
  """
  @spec active_operations() :: {:ok, list()} | {:error, term()}
  def active_operations do
    SandboxLog.active_operations()
  end

  @doc """
  Check if a target is currently under sandbox operation.
  """
  @spec target_sandboxed?(atom(), String.t()) :: boolean()
  def target_sandboxed?(target_type, target_id) do
    case SandboxLog.for_target(target_type, target_id) do
      {:ok, logs} ->
        Enum.any?(logs, &(&1.status == :active))

      _ ->
        false
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # EFFECT APPLICATION (STUBS FOR INTEGRATION)
  # ═══════════════════════════════════════════════════════════════

  defp apply_freeze_effect(chunk_id, ticks, log_id) do
    # Integration point: Would signal to Thunderbit chunk manager
    # to pause CA execution for this chunk
    Logger.debug(
      "[Sandbox] Applied freeze effect: chunk=#{chunk_id} ticks=#{ticks} log=#{log_id}"
    )

    # Schedule auto-release after ticks (at 50ms/tick)
    duration_ms = ticks * 50

    Task.start(fn ->
      Process.sleep(duration_ms)
      auto_complete_operation(log_id)
    end)
  end

  defp start_mirror_replay(chunk_id, start_tick, end_tick, log_id) do
    # Integration point: Would start a replay process that reads
    # historical tick states and replays them
    Logger.debug(
      "[Sandbox] Started replay: chunk=#{chunk_id} range=#{start_tick}-#{end_tick} log=#{log_id}"
    )

    replay_id = "replay_#{:erlang.unique_integer([:positive])}"

    # Simulate replay completion
    Task.start(fn ->
      range = end_tick - start_tick
      # Estimate replay time at 10ms per tick
      Process.sleep(range * 10)
      auto_complete_operation(log_id)
    end)

    replay_id
  end

  defp apply_decay_override(pac_id, factor, log_id) do
    # Integration point: Would update PAC's decay configuration
    Logger.debug("[Sandbox] Applied decay override: pac=#{pac_id} factor=#{factor} log=#{log_id}")

    # Decay override auto-expires via the expires_at field
    # A background job would check and complete these
  end

  defp apply_quarantine(segment_id, isolation_level, log_id) do
    # Integration point: Would signal to segment manager
    # to isolate this segment
    Logger.debug(
      "[Sandbox] Applied quarantine: segment=#{segment_id} level=#{isolation_level} log=#{log_id}"
    )

    # Quarantine remains until manually released
  end

  defp release_effect(log) do
    Logger.debug(
      "[Sandbox] Released #{log.operation_type} on #{log.target_type}:#{log.target_id}"
    )

    # Integration point: Would signal to appropriate manager
    # to resume normal operation
  end

  defp auto_complete_operation(log_id) do
    case Ash.get(SandboxLog, log_id) do
      {:ok, log} ->
        if log.status == :active do
          SandboxLog.complete(log, %{result: %{auto_completed: true}})
          Logger.debug("[Sandbox] Auto-completed operation #{log_id}")
        end

      _ ->
        :ok
    end
  end
end
