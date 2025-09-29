defmodule Thunderline.Thundercrown.Action do
  @moduledoc """
  Unified action execution facade that wraps Ash resource actions (and future non-Ash operations)
  with standardized telemetry, event emission, correlation/causation tracking, and tool metadata
  extraction.

  This provides the rails required by High Command assessment items:
    * Action -> Tool exposure (JSON schema derivation for arguments & returns)
    * Consistent causal envelope: correlation_id & causation_id
    * Structured telemetry span around every execution with success/failure
    * Normalized %Thunderline.Event{} emission (ui/ai/system/... names)

  Design goals:
    * Zero-cost opt-out for pure Ash usage (delegate to Ash directly if no opts)
    * Extensible handlers (custom before/after hooks)
    * Pluggable argument schema generator (initial version: basic typespec inference + fallback)

  Minimal surface for now while we iterate:
    Thunderline.Thundercrown.Action.call(resource, action, input, opts)

  Options:
    :actor - Ash actor (for authorization)
    :correlation_id - existing correlation threading
    :causation_id - parent event id
    :event_name - explicit event name (defaults to system.<resource>.<action>)
    :emit? - boolean (default true)
    :tool_meta - map with additional tool metadata (added to event.meta.tool)

  TODO (follow-up PRs):
    * JSON Schema export (Mix task)
    * Tool registry persistence & linter
    * Argument spec extraction from Ash DSL attributes/arguments
  """
  require Logger

  @default_taxonomy_version 1

  @spec call(module(), atom(), map() | keyword(), keyword()) :: {:ok, term()} | {:error, term()}
  def call(resource, action, input, opts \\ []) when is_atom(action) and is_list(opts) do
    telemetry_prefix = [:thunderline, :action]
    correlation_id = opts[:correlation_id] || uuid()
    causation_id = opts[:causation_id]
    actor = opts[:actor]

    meta = %{
      resource: resource,
      action: action,
      correlation_id: correlation_id,
      causation_id: causation_id
    }

    start_time = System.monotonic_time()

    measurements = %{system_time: System.system_time()}
    :telemetry.execute(telemetry_prefix ++ [:start], measurements, meta)

    result =
      try do
        {:ok, run_ash(resource, action, input, actor)}
      rescue
        e -> {:error, e}
      catch
        kind, value -> {:error, {kind, value}}
      end

    duration_us = System.monotonic_time() - start_time

    event_name = opts[:event_name] || default_event_name(resource, action, result)
    emit? = Keyword.get(opts, :emit?, true)

    case result do
      {:ok, value} ->
        :telemetry.execute(
          telemetry_prefix ++ [:stop],
          %{duration: duration_us},
          Map.put(meta, :result, :ok)
        )

        emit? and emit_success(event_name, value, correlation_id, causation_id, opts)
        {:ok, value}

      {:error, error} ->
        :telemetry.execute(
          telemetry_prefix ++ [:exception],
          %{duration: duration_us},
          Map.put(meta, :error, error)
        )

        emit? and emit_error(event_name, error, correlation_id, causation_id, opts)
        {:error, error}
    end
  end

  defp run_ash(resource, action, input, actor) do
    _ = Code.ensure_compiled(resource)

    resource
    |> Ash.Changeset.for_create(action, normalize_input(input), actor: actor)
    |> Ash.create()
    |> case do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  rescue
    UndefinedFunctionError ->
      raise ArgumentError,
            "Unsupported resource module #{inspect(resource)} for Thunderline.Thundercrown.Action.call/4"
  end

  defp normalize_input(input) when is_map(input), do: input
  defp normalize_input(input) when is_list(input), do: Map.new(input)

  defp default_event_name(resource, action, {:ok, _}) do
    base = resource |> Module.split() |> List.last() |> Macro.underscore()
    "system." <> base <> "." <> to_string(action)
  end

  defp default_event_name(resource, action, {:error, _}) do
    base = resource |> Module.split() |> List.last() |> Macro.underscore()
    "system." <> base <> "." <> to_string(action)
  end

  defp emit_success(event_name, value, correlation_id, causation_id, opts) do
    envelope = base_envelope(event_name, correlation_id, causation_id, opts)
    payload = serialize_value(value)
    publish(envelope, payload)
  end

  defp emit_error(event_name, error, correlation_id, causation_id, opts) do
    envelope = base_envelope(event_name, correlation_id, causation_id, opts)

    class =
      case error do
        %{__exception__: true} -> error.__struct__ |> to_string()
        _ -> inspect(error)
      end

    payload = %{error: Exception.message(error), class: class}
    publish(envelope, payload)
  end

  defp base_envelope(event_name, correlation_id, causation_id, opts) do
    %{
      id: uuid(),
      at: DateTime.utc_now(),
      name: event_name,
      source: :crown,
      correlation_id: correlation_id,
      causation_id: causation_id,
      taxonomy_version: @default_taxonomy_version,
      event_version: 1,
      meta: %{tool: opts[:tool_meta] || %{}, flags: [], reliability: :persistent}
    }
  end

  defp serialize_value(value) do
    cond do
      is_map(value) -> Map.take(value, Enum.take(Map.keys(value), 25))
      function_exported?(value.__struct__, :__schema__, 1) -> Map.from_struct(value)
      true -> %{value: inspect(value)}
    end
  end

  defp publish(envelope, payload) do
    attrs = Map.merge(envelope, %{payload: payload, type: :action_event, source: envelope.source})

    case Thunderline.Event.new(attrs) do
      {:ok, ev} ->
        case Thunderline.Thunderflow.EventBus.publish_event(ev) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to publish action event #{envelope.name}: #{inspect(reason)}")
        end

      {:error, errs} ->
        Logger.warning("Failed to construct action event #{envelope.name}: #{inspect(errs)}")
    end
  rescue
    e -> Logger.warning("Failed to emit action event #{envelope.name}: #{inspect(e)}")
  end

  defp uuid, do: UUID.uuid4()
end
