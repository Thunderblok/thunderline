defmodule Thunderline.Thunderbolt.Sagas.Registry do
  @moduledoc """
  Registry for tracking active Reactor saga executions.

  This registry allows querying which sagas are currently running,
  their correlation IDs, and their process IDs for monitoring and
  potential termination.
  """

  def child_spec(_opts) do
    Registry.child_spec(
      keys: :unique,
      name: __MODULE__
    )
  end
end
