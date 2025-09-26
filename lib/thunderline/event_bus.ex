defmodule Thunderline.EventBus do
  @moduledoc """
  Compatibility wrapper for the canonical EventBus implementation.

  Delegates to `Thunderline.Thunderflow.EventBus` while preserving the historical
  module name used across the codebase and in documentation.
  """

  alias Thunderline.Thunderflow.EventBus, as: FlowBus

  @spec publish_event(Thunderline.Event.t()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  defdelegate publish_event(event), to: FlowBus

  @spec publish_event!(Thunderline.Event.t()) :: Thunderline.Event.t() | no_return()
  defdelegate publish_event!(event), to: FlowBus
end
