defmodule Thunderline.EventBus do
  @moduledoc """
  Compatibility wrapper (ANVIL/IRONWOLF) – delegates to new core module
  `Thunderline.Thunderflow.EventBus` after namespace relocation.

  Do not extend this module. Call `Thunderline.Thunderflow.EventBus` directly in
  new code. This wrapper will be removed once call sites are migrated.
  """
  alias Thunderline.Thunderflow.EventBus, as: Core
  require Logger
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
  def subscribe(topic) do
    key = {:eventbus_subscribe_warned, topic}
    unless Process.get(key) do
      Logger.warning("EventBus.subscribe/1 is a no-op shim (topic=#{inspect(topic)}) – migrate to telemetry or pipeline consumer")
      Process.put(key, true)
    end
    :ok
  end
end
