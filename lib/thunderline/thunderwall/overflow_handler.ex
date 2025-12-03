defmodule Thunderline.Thunderwall.OverflowHandler do
  @moduledoc """
  Handles overflow and reject streams from other domains.

  The OverflowHandler receives resources that have been rejected by their
  home domains due to:

  - Queue capacity limits
  - Rate limiting
  - Validation failures (non-retryable)
  - Resource constraints

  ## Overflow Streams

  Each domain can have an overflow stream. When a domain rejects a resource,
  it sends it to the OverflowHandler which either:

  1. Routes to decay (permanent rejection)
  2. Routes to dead-letter queue (for manual review)
  3. Attempts re-routing to alternate domain

  ## Usage

      # Handle overflow from a domain
      OverflowHandler.handle_overflow(:thunderflow, event, :queue_full)

      # Get overflow statistics
      OverflowHandler.stats()
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderwall.DecayProcessor

  @telemetry_prefix [:thunderline, :wall, :overflow]

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc "Starts the OverflowHandler."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Handle an overflow item from a domain.

  ## Reasons

  - `:queue_full` - Domain queue at capacity
  - `:rate_limited` - Exceeded rate limit
  - `:validation_failed` - Non-retryable validation error
  - `:resource_exhausted` - Memory/CPU constraints
  - `:rejected` - Explicit rejection
  """
  @spec handle_overflow(atom(), map(), atom()) :: :ok | {:error, term()}
  def handle_overflow(source_domain, item, reason, server \\ __MODULE__) do
    GenServer.call(server, {:overflow, source_domain, item, reason})
  end

  @doc """
  Route a rejected resource to the overflow handler.

  Convenience function that accepts a map of rejection details and
  routes them to the overflow handler for processing.

  ## Parameters

  - `:source_domain` - The domain the resource came from
  - `:resource_type` - The type/module of the resource
  - `:resource_id` - The ID of the resource
  - `:reason` - The reason for rejection (atom)
  - `:payload` - Optional additional data about the rejection

  ## Example

      OverflowHandler.route_reject(%{
        source_domain: :bolt,
        resource_type: :saga_state,
        resource_id: saga.id,
        reason: :stale_timeout,
        payload: %{saga_module: SomeModule}
      })
  """
  @spec route_reject(map()) :: :ok | {:error, term()}
  def route_reject(%{source_domain: domain, reason: reason} = params) do
    item = %{
      resource_type: Map.get(params, :resource_type, :unknown),
      resource_id: Map.get(params, :resource_id),
      payload: Map.get(params, :payload, %{}),
      rejected_at: DateTime.utc_now()
    }

    handle_overflow(domain, item, reason)
  end

  def route_reject(params) do
    Logger.warning(
      "[Thunderwall.OverflowHandler] Invalid route_reject params: #{inspect(params)}"
    )

    {:error, :invalid_params}
  end

  @doc "Get overflow statistics."
  @spec stats(GenServer.server()) :: map()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc "Clear overflow statistics."
  @spec clear_stats(GenServer.server()) :: :ok
  def clear_stats(server \\ __MODULE__) do
    GenServer.call(server, :clear_stats)
  end

  @doc "Get recent overflow items (for debugging)."
  @spec recent(non_neg_integer(), GenServer.server()) :: [map()]
  def recent(limit \\ 10, server \\ __MODULE__) do
    GenServer.call(server, {:recent, limit})
  end

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    state = %{
      stats: %{
        total: 0,
        by_domain: %{},
        by_reason: %{}
      },
      # Circular buffer of recent items
      recent: []
    }

    Logger.info("[Thunderwall.OverflowHandler] Started")

    {:ok, state}
  end

  @impl true
  def handle_call({:overflow, source_domain, item, reason}, _from, state) do
    start_time = System.monotonic_time(:microsecond)

    # Update stats
    new_stats = update_stats(state.stats, source_domain, reason)

    # Process the overflow
    result = process_overflow(source_domain, item, reason)

    # Track recent items
    recent_item = %{
      source_domain: source_domain,
      reason: reason,
      item_type: get_item_type(item),
      timestamp: DateTime.utc_now(),
      result: result
    }

    new_recent = [recent_item | Enum.take(state.recent, 99)]

    elapsed = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:received],
      %{duration_us: elapsed},
      %{source_domain: source_domain, reason: reason}
    )

    {:reply, result, %{state | stats: new_stats, recent: new_recent}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  def handle_call(:clear_stats, _from, state) do
    new_stats = %{total: 0, by_domain: %{}, by_reason: %{}}
    {:reply, :ok, %{state | stats: new_stats}}
  end

  def handle_call({:recent, limit}, _from, state) do
    {:reply, Enum.take(state.recent, limit), state}
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════

  defp update_stats(stats, source_domain, reason) do
    %{
      total: stats.total + 1,
      by_domain: Map.update(stats.by_domain, source_domain, 1, &(&1 + 1)),
      by_reason: Map.update(stats.by_reason, reason, 1, &(&1 + 1))
    }
  end

  defp process_overflow(source_domain, item, reason) do
    Logger.debug(
      "[Thunderwall.OverflowHandler] Overflow from #{source_domain}: #{inspect(reason)}"
    )

    # Emit event
    emit_event(source_domain, item, reason)

    # Route based on reason
    case classify_overflow(reason) do
      :decay ->
        # Route to decay processor
        resource_type = get_item_type(item)
        resource_id = get_item_id(item)

        DecayProcessor.decay_resource(
          resource_type,
          resource_id,
          :overflow,
          snapshot: item,
          metadata: %{source_domain: source_domain, original_reason: reason}
        )

        :ok

      :dead_letter ->
        # TODO: Route to dead-letter queue when implemented
        Logger.warning(
          "[Thunderwall.OverflowHandler] Dead-letter not implemented, decaying instead"
        )

        :ok

      :discard ->
        # Silently discard (for rate-limited items)
        :ok
    end
  end

  defp classify_overflow(reason) do
    case reason do
      :queue_full -> :decay
      :rate_limited -> :discard
      :validation_failed -> :decay
      :resource_exhausted -> :decay
      :rejected -> :decay
      _ -> :decay
    end
  end

  defp get_item_type(%{__struct__: struct}), do: struct
  defp get_item_type(%{type: type}), do: type
  defp get_item_type(_), do: :unknown

  defp get_item_id(%{id: id}), do: id
  defp get_item_id(%{event_id: id}), do: id
  defp get_item_id(_), do: Ash.UUID.generate()

  defp emit_event(source_domain, _item, reason) do
    event = %{
      type: "wall.overflow.received",
      source_domain: source_domain,
      reason: reason,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Thunderline.PubSub, "wall:overflow", {:wall_event, event})
  end
end
