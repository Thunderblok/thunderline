defmodule Thunderline.EventBus do
  @moduledoc """
  Convenience wrapper for Thunderline.Thunderflow.EventBus.

  This module exists to maintain backward compatibility with code that references
  `Thunderline.EventBus` instead of the full `Thunderline.Thunderflow.EventBus`.

  All functions delegate directly to Thunderline.Thunderflow.EventBus.
  """

  @doc """
  Publish an event to the Thunderline event system.

  Accepts either a `Thunderline.Event` struct or a map with event attributes.
  Returns `{:ok, event}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> event = Thunderline.Event.new!(name: "test.event", type: :test, source: :flow)
      iex> Thunderline.EventBus.publish_event(event)
      {:ok, %Thunderline.Event{}}

      iex> Thunderline.EventBus.publish_event(%{name: "test.event", source: :flow, payload: %{}})
      {:ok, %Thunderline.Event{}}

  """
  @spec publish_event(Thunderline.Event.t() | map()) :: {:ok, Thunderline.Event.t()} | {:error, term()}
  defdelegate publish_event(event), to: Thunderline.Thunderflow.EventBus

  @doc """
  Publish an event, raising on failure.

  Returns the event on success or raises an exception on failure.

  ## Examples

      iex> event = Thunderline.Event.new!(name: "test.event", type: :test, source: :flow)
      iex> Thunderline.EventBus.publish_event!(event)
      %Thunderline.Event{}

  """
  @spec publish_event!(Thunderline.Event.t()) :: Thunderline.Event.t() | no_return()
  defdelegate publish_event!(event), to: Thunderline.Thunderflow.EventBus
end
