defmodule Thunderline.Thunderbolt.Continuous.Telemetry do
  @moduledoc """
  Telemetry integration for Continuous Tensor operations.

  Attaches handlers for monitoring continuous tensor performance and usage.

  ## Events

  The following telemetry events are emitted:

  - `[:thunderline, :bolt, :continuous, :create]` - Tensor creation
  - `[:thunderline, :bolt, :continuous, :get]` - Index lookup
  - `[:thunderline, :bolt, :continuous, :set]` - Interval insertion
  - `[:thunderline, :bolt, :continuous, :algebra]` - Algebraic operations
  - `[:thunderline, :bolt, :continuous, :serialize]` - Storage operations

  ## Measurements

  - `:duration` - Operation duration in native time units

  ## Metadata

  - `:dims` - Tensor dimensions
  - `:operation` - Specific operation (for algebra events)
  - `:interval_count` - Number of intervals (for set events)
  - `:found` - Whether lookup found a value (for get events)

  ## Setup

  Add to your application supervision tree:

      def start(_type, _args) do
        :ok = Thunderline.Thunderbolt.Continuous.Telemetry.attach()

        children = [
          # ...
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  Or attach specific handlers:

      Thunderline.Thunderbolt.Continuous.Telemetry.attach_handlers([
        :create,
        :get,
        :algebra
      ])

  ## Logger Integration

  When attached with default handlers, operations are logged at debug level:

      [debug] ContinuousTensor created: dims=2
      [debug] ContinuousTensor get: found=true, dims=1, duration=42μs
      [debug] ContinuousTensor algebra: op=integrate, dims=1, duration=156μs

  ## Metrics Integration

  For production metrics, use the raw telemetry events:

      :telemetry.attach("my-metrics", [:thunderline, :bolt, :continuous, :get], fn
        _event, %{duration: duration}, metadata, _config ->
          Metrics.histogram("continuous.lookup.duration", duration, tags: metadata)
      end, nil)
  """

  require Logger

  @events [
    [:thunderline, :bolt, :continuous, :create],
    [:thunderline, :bolt, :continuous, :get],
    [:thunderline, :bolt, :continuous, :set],
    [:thunderline, :bolt, :continuous, :algebra],
    [:thunderline, :bolt, :continuous, :serialize]
  ]

  @doc """
  Attaches all default telemetry handlers.

  Returns `:ok` on success or `{:error, reason}` if attachment fails.
  """
  @spec attach() :: :ok | {:error, term()}
  def attach do
    attach_handlers([:create, :get, :set, :algebra, :serialize])
  end

  @doc """
  Attaches handlers for specific event types.

  ## Examples

      # Attach only lookup monitoring
      attach_handlers([:get])

      # Attach performance-critical operations
      attach_handlers([:get, :algebra])
  """
  @spec attach_handlers(list(atom())) :: :ok | {:error, term()}
  def attach_handlers(event_types) when is_list(event_types) do
    events =
      event_types
      |> Enum.map(fn type -> [:thunderline, :bolt, :continuous, type] end)
      |> Enum.filter(&(&1 in @events))

    case :telemetry.attach_many(
           "thunderline-continuous-tensor",
           events,
           &handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      error -> error
    end
  end

  @doc """
  Detaches all continuous tensor telemetry handlers.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach("thunderline-continuous-tensor")
  end

  @doc """
  Returns the list of telemetry events emitted by continuous tensors.
  """
  @spec events() :: list(list(atom()))
  def events, do: @events

  # ============================================================================
  # Event Handlers
  # ============================================================================

  defp handle_event(
         [:thunderline, :bolt, :continuous, :create],
         %{duration: duration},
         metadata,
         _config
       ) do
    Logger.debug(
      "ContinuousTensor created: dims=#{metadata[:dims]}, duration=#{format_duration(duration)}"
    )
  end

  defp handle_event(
         [:thunderline, :bolt, :continuous, :get],
         %{duration: duration},
         metadata,
         _config
       ) do
    Logger.debug(
      "ContinuousTensor get: found=#{metadata[:found]}, dims=#{metadata[:dims]}, duration=#{format_duration(duration)}"
    )
  end

  defp handle_event(
         [:thunderline, :bolt, :continuous, :set],
         %{duration: duration},
         metadata,
         _config
       ) do
    Logger.debug(
      "ContinuousTensor set: intervals=#{metadata[:interval_count]}, dims=#{metadata[:dims]}, duration=#{format_duration(duration)}"
    )
  end

  defp handle_event(
         [:thunderline, :bolt, :continuous, :algebra],
         %{duration: duration},
         metadata,
         _config
       ) do
    Logger.debug(
      "ContinuousTensor algebra: op=#{metadata[:operation]}, dims=#{metadata[:dims]}, duration=#{format_duration(duration)}"
    )
  end

  defp handle_event(
         [:thunderline, :bolt, :continuous, :serialize],
         %{duration: duration},
         metadata,
         _config
       ) do
    Logger.debug(
      "ContinuousTensor serialize: format=#{metadata[:format]}, duration=#{format_duration(duration)}"
    )
  end

  defp handle_event(_event, _measurements, _metadata, _config), do: :ok

  # ============================================================================
  # Helpers
  # ============================================================================

  defp format_duration(native_time) do
    microseconds = System.convert_time_unit(native_time, :native, :microsecond)

    cond do
      microseconds < 1000 -> "#{microseconds}μs"
      microseconds < 1_000_000 -> "#{Float.round(microseconds / 1000, 2)}ms"
      true -> "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end
end
