defmodule Thunderline.Thunderbolt.ReflexHandlers.Supervisor do
  @moduledoc """
  Supervisor for reflex handler GenServers.

  Starts and supervises all reflex handler processes that subscribe
  to `bolt.thunderbit.reflex.*` events via PubSub.
  """

  use Supervisor

  alias Thunderline.Thunderbolt.ReflexHandlers.{Stabilization, Escalation, Delegation}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Stabilization, []},
      {Escalation, []},
      {Delegation, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
