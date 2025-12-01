defmodule Thunderline.Thunderbolt.ReflexHandlers do
  @moduledoc """
  Umbrella module for Thunderbolt reflex event handlers.

  HC-Ω-8: Reflex handlers subscribe to `bolt.thunderbit.reflex.*` events
  and route them to appropriate domain actions based on trigger type.

  ## Handler Modules

  - `Stabilization` - Handles stability events, adjusts PAC traits toward equilibrium
  - `Escalation` - Handles chaos/critical events, triggers evolution or GC
  - `Delegation` - Handles complex events, delegates to Reactor sagas or Thunderwall

  ## Event Flow

      Thunderbit.Reflex
           │
           ▼ emit
      EventBus (bolt.thunderbit.reflex.*)
           │
           ▼ broadcast
      ┌────┴────┐
      │         │
    Handlers    │
      ▼         ▼
    Stabilization
    Escalation
    Delegation
           │
           ▼
    Domain Actions
    (PAC, Wall, Block)

  ## Supervision

  Add handler supervisor to application tree:

      {Thunderline.Thunderbolt.ReflexHandlers.Supervisor, []}

  ## Telemetry

  All handlers emit telemetry under `[:thunderline, :bolt, :reflex_handler, ...]`
  """

  alias Thunderline.Thunderbolt.ReflexHandlers.{Stabilization, Escalation, Delegation}

  @doc """
  Start all reflex handlers under supervision.
  Returns the supervisor pid.
  """
  def start_handlers(opts \\ []) do
    Thunderline.Thunderbolt.ReflexHandlers.Supervisor.start_link(opts)
  end

  @doc """
  Route an event to the appropriate handler based on trigger type.
  Used for direct dispatch (bypasses PubSub for testing).
  """
  @spec route_event(map()) :: {:ok, atom()} | {:error, term()}
  def route_event(%{trigger: trigger} = event) when is_atom(trigger) do
    handler =
      case trigger do
        # Stabilization triggers
        t when t in [:low_stability, :trust_boost, :recovery, :stabilize] ->
          Stabilization

        # Escalation triggers
        t when t in [:chaos_spike, :critical_threshold, :evolution_needed, :cascade_risk] ->
          Escalation

        # Delegation triggers
        t when t in [:complex_decision, :cross_domain, :saga_required, :quarantine_needed] ->
          Delegation

        # Default to Stabilization for unknown triggers
        _ ->
          Stabilization
      end

    handler.handle_event(event)
    {:ok, handler}
  end

  def route_event(%{} = event) do
    # No trigger specified, route to Stabilization as default
    Stabilization.handle_event(event)
    {:ok, Stabilization}
  end

  def route_event(_), do: {:error, :invalid_event}

  @doc """
  List all registered handler modules.
  """
  def handlers do
    [Stabilization, Escalation, Delegation]
  end

  @doc """
  Check if handlers are running.
  """
  def handlers_running? do
    case Process.whereis(Thunderline.Thunderbolt.ReflexHandlers.Supervisor) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
