defmodule Thunderline.EventBus do
  @moduledoc """
  Compatibility wrapper (ANVIL/IRONWOLF) – delegates to new core module
  `Thunderline.Thunderflow.EventBus` after namespace relocation.

  Do not extend this module. Call `Thunderline.Thunderflow.EventBus` directly in
  new code. This wrapper will be removed once call sites are migrated.
  """
  alias Thunderline.Thunderflow.EventBus, as: Core
  @spec publish_event(Thunderline.Event.t()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  defdelegate publish_event(ev), to: Core
  @spec publish_event!(Thunderline.Event.t()) :: Thunderline.Event.t() | no_return()
  defdelegate publish_event!(ev), to: Core
end
