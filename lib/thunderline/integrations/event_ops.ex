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
    
    generic :process_event, :map do
      description "Process a single event via configurable processor (simple or Reactor)"
      argument :event, :map, allow_nil?: false
      
      run fn %{event: event}, _context ->
        if reactor_enabled?() do
          # Reactor path (when feature flag enabled)
          case Code.ensure_loaded(Thunderline.Reactors.RealtimeReactor) do
            {:module, _} ->
              Reactor.run(Thunderline.Reactors.RealtimeReactor, %{event: event})
            {:error, _} ->
              # Fallback to simple processor if Reactor module not available
              Thunderline.EventProcessor.process_event(event)
          end
        else
          # Simple processor path (default)
          Thunderline.EventProcessor.process_event(event)
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