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

  actions do
    defaults []

    action :process_event, :map do
      description "Process a single event via configured processor (simple or Reactor)"
      argument :event, :map, allow_nil?: false

      run fn input, _ctx ->
        event = get_in(input, [:arguments, :event])
        result =
          if reactor_enabled?() do
            case Code.ensure_loaded(Thunderline.Reactors.RealtimeReactor) do
              {:module, _} -> Reactor.run(Thunderline.Reactors.RealtimeReactor, %{event: event})
              _ -> Thunderline.Thunderflow.Processor.process_event(event)
            end
          else
            Thunderline.Thunderflow.Processor.process_event(event)
          end

        case result do
          {:ok, _} -> {:ok, %{status: :processed}}
          {:error, reason} -> {:error, %{status: :error, reason: reason}}
          other -> {:ok, %{result: other}}
        end
      end
    end
  end

  code_interface do
    define :process_event, action: :process_event
  end

  defp reactor_enabled? do
    case System.get_env("TL_ENABLE_REACTOR") do
      "true" -> true
      "1" -> true
      _ -> false
    end
  end
end
