defmodule Thunderline.Thunderflow.EventValidator do
  @moduledoc """
  Event taxonomy validator (WARHORSE Phase 1).

  Enforces minimal canonical rules before events enter pipelines:
  - Name has >= 2 segments and reserved prefix rules honored
  - Allowed category for source domain (delegates to Event.category_allowed?/2 via construction)
  - correlation_id present (UUID v7 shape – best-effort check)
  - taxonomy_version & event_version positive integers
  - Reserved prefixes: system., reactor., ui., audit., ml. — must not collide with forbidden domain-specific disallowed list (future)

  Modes (configurable via :thunderline, :event_validator_mode):
    :warn  (dev)   -> log + telemetry only
    :raise (test)  -> raise to fail fast
    :drop  (prod)  -> emit audit drop event & telemetry
  """
  require Logger
  alias Thunderline.Event

  @reserved_prefixes ~w(system. reactor. ui. audit. evt. ml. ai. flow. grid.)
  @uuid_v7_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  @spec validate(Event.t()) :: :ok | {:error, term()}
  def validate(%Event{} = ev) do
    start = System.monotonic_time()

    case do_validate(ev) do
      :ok ->
        telemetry(:validated, start, %{status: :ok, name: ev.name})
        :ok

      {:error, reason} = err ->
        telemetry(:validated, start, %{status: :error, name: ev.name, reason: reason})
        handle_failure(ev, reason)
        err
    end
  end

  defp do_validate(%Event{
         name: name,
         correlation_id: cid,
         taxonomy_version: tv,
         event_version: evv,
         meta: meta
       }) do
    cond do
      !is_binary(name) ->
        {:error, :invalid_name}

      length(String.split(name, ".")) < 2 ->
        {:error, :short_name}

      not valid_reserved?(name) ->
        {:error, :reserved_violation}

      cid == nil or !is_binary(cid) ->
        {:error, :missing_correlation_id}

      String.length(cid) < 10 or not Regex.match?(@uuid_v7_regex, cid) ->
        {:error, :bad_correlation_id}

      !is_integer(tv) or tv < 1 ->
        {:error, :invalid_taxonomy_version}

      !is_integer(evv) or evv < 1 ->
        {:error, :invalid_event_version}

      not is_map(meta) ->
        {:error, :invalid_meta}

      true ->
        :ok
    end
  end

  defp valid_reserved?(name) do
    # Allow names that start with any reserved family. If you want to allow
    # additional non-reserved families (e.g., "ai."), adjust @reserved_prefixes
    # or extend this function accordingly.
    Enum.any?(@reserved_prefixes, &String.starts_with?(name, &1))
  end

  defp handle_failure(ev, reason) do
    case mode() do
      :warn ->
        Logger.warning("[EventValidator] invalid event #{ev.name} reason=#{inspect(reason)}")

      :raise ->
        raise ArgumentError, "Invalid event #{ev.name}: #{inspect(reason)}"

      :drop ->
        drop_event(ev, reason)

      other ->
        Logger.warning("[EventValidator] unknown mode #{inspect(other)}; treating as warn")
    end
  end

  defp drop_event(ev, reason) do
    Logger.warning("[EventValidator] dropping event #{ev.name} reason=#{inspect(reason)}")

    :telemetry.execute([:thunderline, :event, :dropped], %{count: 1}, %{
      reason: reason,
      name: ev.name
    })

    # Emit audit event for governance chain
    audit_payload = %{
      invalid_event: Event.to_map(ev),
      reason: inspect(reason)
    }

    with {:ok, ev} <-
           Thunderline.Event.new(%{
             name: "audit.event_drop",
             source: :flow,
             payload: audit_payload,
             type: :audit_event_drop,
             meta: %{pipeline: :realtime},
             priority: :high
           }) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[EventValidator] publish audit.event_drop failed: #{inspect(reason)} name=#{ev.name}"
          )
      end
    end

    :ok
  end

  defp telemetry(kind, start, meta) do
    :telemetry.execute(
      [:thunderline, :event, kind],
      %{duration: System.monotonic_time() - start},
      meta
    )
  end

  defp mode do
    Application.get_env(:thunderline, :event_validator_mode) || inferred_mode()
  end

  defp inferred_mode do
    case Mix.env() do
      :prod -> :drop
      :test -> :raise
      _ -> :warn
    end
  end
end
