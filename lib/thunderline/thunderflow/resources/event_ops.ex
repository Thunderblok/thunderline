defmodule Thunderline.Thunderflow.Resources.EventOps do
  @moduledoc """
  EventOps Resource - Switchable event processing entrypoint (simple vs Reactor).

  Embedded Ash resource to normalize how callers invoke event processing while
  allowing toggling of orchestration via TL_ENABLE_REACTOR env var.
  Lives under Thunderflow (event ingress boundary).
  """

  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: :embedded

  code_interface do
    define :process_event, action: :process_event
  end

  actions do
    defaults []

    action :process_event, :map do
      description "Process a single event via configured processor (simple or Reactor)"
      argument :event, :map, allow_nil?: false

      run fn input, _ctx ->
        event = get_in(input, [:arguments, :event])

        result = Thunderline.Thundercrown.Orchestrator.dispatch_event(event, "thunderflow")

        case result do
          {:ok, _} -> {:ok, %{status: :processed}}
          {:error, reason} -> {:error, %{status: :error, reason: reason}}
          other -> {:ok, %{result: other}}
        end
      end
    end
  end
end
