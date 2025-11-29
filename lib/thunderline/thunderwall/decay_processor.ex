defmodule Thunderline.Thunderwall.DecayProcessor do
  @moduledoc """
  Processes resource decay across the Thunderline system.

  The DecayProcessor is responsible for:

  1. Accepting decay requests from other domains
  2. Creating DecayRecords for audit trails
  3. Archiving or destroying the original resources
  4. Emitting decay events for telemetry

  ## Usage

      # Decay a resource
      DecayProcessor.decay_resource(MyResource, resource_id, :ttl_expired)

      # Decay with snapshot
      DecayProcessor.decay_resource(MyResource, resource_id, :explicit, snapshot: data)

      # Bulk decay
      DecayProcessor.bulk_decay([{MyResource, id1}, {MyResource, id2}], :gc)
  """

  require Logger

  alias Thunderline.Thunderwall.Resources.DecayRecord

  @telemetry_prefix [:thunderline, :wall, :decay]

  @doc """
  Decay a single resource.

  ## Options

  - `:snapshot` - Data snapshot to preserve (map)
  - `:metadata` - Additional metadata (map)
  - `:archive` - Whether to also create an archive entry (default: false)
  """
  @spec decay_resource(module(), any(), atom(), keyword()) ::
          {:ok, DecayRecord.t()} | {:error, term()}
  def decay_resource(resource_type, resource_id, reason, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    type_string = inspect(resource_type)
    id_string = to_string(resource_id)

    attrs = %{
      resource_type: type_string,
      resource_id: id_string,
      decay_reason: reason,
      snapshot: Keyword.get(opts, :snapshot),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    result = DecayRecord.record_decay(attrs)

    elapsed = System.monotonic_time(:microsecond) - start_time

    case result do
      {:ok, record} ->
        emit_telemetry(:success, reason, elapsed)
        emit_event(:decayed, record)

        Logger.debug(
          "[Thunderwall.DecayProcessor] Decayed #{type_string}##{id_string} reason=#{reason}"
        )

        {:ok, record}

      {:error, error} ->
        emit_telemetry(:error, reason, elapsed)
        Logger.error("[Thunderwall.DecayProcessor] Failed to decay: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Bulk decay multiple resources.

  Takes a list of `{resource_type, resource_id}` tuples.
  Returns `{:ok, count}` with the number of successfully decayed resources.
  """
  @spec bulk_decay([{module(), any()}], atom(), keyword()) :: {:ok, non_neg_integer()}
  def bulk_decay(resources, reason, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    results =
      Enum.map(resources, fn {type, id} ->
        decay_resource(type, id, reason, opts)
      end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = Enum.count(results, &match?({:error, _}, &1))

    elapsed = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:bulk],
      %{
        success_count: success_count,
        error_count: error_count,
        total: length(resources),
        duration_us: elapsed
      },
      %{reason: reason}
    )

    Logger.info(
      "[Thunderwall.DecayProcessor] Bulk decay: #{success_count}/#{length(resources)} succeeded"
    )

    {:ok, success_count}
  end

  @doc """
  Check if a resource should be decayed based on TTL.

  Returns `true` if the resource's age exceeds the TTL.
  """
  @spec should_decay?(DateTime.t(), pos_integer()) :: boolean()
  def should_decay?(created_at, ttl_seconds) do
    age_seconds = DateTime.diff(DateTime.utc_now(), created_at, :second)
    age_seconds >= ttl_seconds
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════

  defp emit_telemetry(status, reason, duration_us) do
    :telemetry.execute(
      @telemetry_prefix ++ [status],
      %{duration_us: duration_us},
      %{reason: reason}
    )
  end

  defp emit_event(event_type, record) do
    event = %{
      type: "wall.decay.#{event_type}",
      resource_type: record.resource_type,
      resource_id: record.resource_id,
      decay_reason: record.decay_reason,
      timestamp: DateTime.utc_now()
    }

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(Thunderline.PubSub, "wall:decay", {:wall_event, event})
  end
end
