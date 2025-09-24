defmodule Thunderline.EventBus do
  @moduledoc """
  Compatibility wrapper (ANVIL/IRONWOLF) – delegates to new core module
  `Thunderline.Thunderflow.EventBus` after namespace relocation.

  Do not extend this module. Call `Thunderline.Thunderflow.EventBus` directly in
  new code. This wrapper will be removed once call sites are migrated.
  """
  alias Thunderline.Thunderflow.EventBus, as: Core
  require Logger
  alias Thunderline.Event
  @spec publish_event(Thunderline.Event.t()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  defdelegate publish_event(ev), to: Core
  @spec publish_event!(Thunderline.Event.t()) :: Thunderline.Event.t() | no_return()
  defdelegate publish_event!(ev), to: Core

  @doc """
  Compatibility shim for legacy `EventBus.subscribe/1` calls.

  The simplified ANVIL EventBus no longer supports direct topic subscription;
  historical callers (e.g. signal sensor, thunder_bridge) invoked `subscribe/1`
  for side‑effect event forwarding. Until those call sites are refactored to
  explicit pipelines or Telemetry handlers, we provide a no‑op that logs once
  per topic per process (suppresses crashes seen at boot).
  """
  @spec subscribe(term()) :: :ok
  def subscribe(_topic) do
    raise "EventBus.subscribe/1 has been removed. Use Phoenix.PubSub or telemetry; see Thunderflow.EventBuffer/RealTimePipeline."
  end

  # --- Legacy convenience API (kept for tests/backwards compatibility) ---
  @doc "Build and publish an event from a legacy type/payload pair."
  @spec emit(atom(), map()) :: {:ok, Event.t()} | {:error, term()}
  def emit(type, payload) when is_atom(type) and is_map(payload) do
    source = map_source_domain(Map.get(payload, :domain) || Map.get(payload, "domain"))
    with {:ok, ev} <- Event.new(%{type: type, source: source, payload: payload}) do
      Core.publish_event(ev)
    end
  end

  @doc "Emit a batch of events given a list of {type, payload}. Returns :ok on best-effort completion."
  @spec emit_batch(list({atom(), map()})) :: :ok
  def emit_batch(pairs) when is_list(pairs) do
    Enum.each(pairs, fn {t, p} -> _ = emit(t, p) end)
    :ok
  end

  @doc "Emit a batch and return the built canonical events."
  @spec emit_batch_with_events(list({atom(), map()})) :: {:ok, [Event.t()]} | {:error, term()}
  def emit_batch_with_events(pairs) when is_list(pairs) do
    results = Enum.map(pairs, fn {t, p} -> emit(t, p) end)
    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} -> {:ok, Enum.map(oks, fn {:ok, ev} -> ev end)}
      {_oks, errs} -> {:error, {:batch_errors, errs}}
    end
  end

  @doc "Return batch metadata similar to historical API."
  @spec emit_batch_meta(list({atom(), map()})) :: {:ok, map()}
  def emit_batch_meta(pairs) when is_list(pairs) do
    {:ok, %{count: length(pairs), built: length(pairs), correlation_id: Thunderline.UUID.v7(), pipeline: :general}}
  end

  @doc "AI convenience emitter used by older call sites."
  @spec ai_emit(atom(), map()) :: {:ok, Event.t()} | {:error, term()}
  def ai_emit(stage, payload) when is_atom(stage) and is_map(payload) do
    name = "ai." <> to_string(stage)
    payload = Map.put(payload, :ai_stage, stage)
    attrs = %{name: name, type: :ai_event, source: :bolt, payload: payload, meta: %{pipeline: :realtime}}
    with {:ok, ev} <- Event.new(attrs) do
      Core.publish_event(ev)
    end
  end

  # Map legacy or ad-hoc domain strings to taxonomy source atoms (best-effort).
  defp map_source_domain(nil), do: :unknown
  defp map_source_domain(str) when is_binary(str) do
    cond do
      String.starts_with?(str, "thunderflow") -> :flow
      String.starts_with?(str, "thundergate") -> :gate
      String.starts_with?(str, "thunderbolt") -> :bolt
      String.starts_with?(str, "thunderblock") -> :block
      String.starts_with?(str, "thunderlink") -> :link
      true -> :unknown
    end
  end
  defp map_source_domain(atom) when is_atom(atom), do: atom
end
