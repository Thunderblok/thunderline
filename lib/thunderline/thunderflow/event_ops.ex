defmodule Thunderline.Integrations.EventOps do
  @moduledoc """
  Ash resource that provides gated access to Reactor-based event processing.

  By default (TL_ENABLE_REACTOR=false), uses simple EventProcessor.
  When TL_ENABLE_REACTOR=true, uses Reactor-based orchestration.

  This allows us to A/B test orchestration approaches without code changes.
  """

  use Ash.Resource, data_layer: :embedded

  actions do
    defaults []

    action :process_event, :map do
      description "Process a single event via configurable processor (simple or Reactor)"
      argument :event, :map, allow_nil?: false

      run fn input, _ctx ->
        event = get_in(input, [:arguments, :event])

        result =
          if reactor_enabled?() do
            case Code.ensure_loaded(Thunderline.Reactors.RealtimeReactor) do
              {:module, _} -> Reactor.run(Thunderline.Reactors.RealtimeReactor, %{event: event})
              _ -> Thunderline.EventProcessor.process_event(event)
            end
          else
            Thunderline.EventProcessor.process_event(event)
          end

        case result do
          {:ok, _} -> {:ok, %{status: :processed}}
          {:error, reason} -> {:error, %{status: :error, reason: reason}}
          other -> {:ok, %{result: other}}
        end
      end
    end
  end
  # Optional convenience interface
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
