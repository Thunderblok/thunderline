defmodule Thunderline.EventBus.BroadwayProducer do
  @moduledoc """
  Broadway producer that consumes events from the Thunderline EventBus.

  Subscribes to event patterns and delivers matching events as Broadway messages
  for processing by downstream consumers.

  ## Configuration

  Pass configuration when starting the Broadway pipeline:

      producer: [
        module: {Thunderline.EventBus.BroadwayProducer,
                 event_pattern: "ui.command.**",
                 bus_name: :default_bus}
      ]

  ## Options

  - `:event_pattern` - Event type pattern to subscribe to (supports wildcards)
  - `:bus_name` - Name of the EventBus to subscribe to (default: `:default_bus`)
  - `:persistent?` - Whether subscription should be persistent (default: `false`)
  """

  use GenStage

  alias Thunderline.EventBus

  require Logger

  def init(opts) do
    event_pattern = Keyword.fetch!(opts, :event_pattern)
    bus_name = Keyword.get(opts, :bus_name, :default_bus)
    persistent? = Keyword.get(opts, :persistent?, false)

    # Subscribe to EventBus with self() as target
    {:ok, subscription_id} =
      EventBus.subscribe(
        bus_name,
        event_pattern,
        dispatch: {:pid, target: self()},
        persistent?: persistent?
      )

    state = %{
      subscription_id: subscription_id,
      bus_name: bus_name,
      event_pattern: event_pattern,
      demand: 0,
      queue: :queue.new()
    }

    {:producer, state}
  end

  def handle_demand(incoming_demand, %{demand: current_demand, queue: queue} = state) do
    total_demand = current_demand + incoming_demand
    {events, new_queue, remaining_demand} = take_events(queue, total_demand, [])

    {:noreply, events, %{state | demand: remaining_demand, queue: new_queue}}
  end

  def handle_info({:event, event}, %{queue: queue, demand: demand} = state) do
    # Wrap event in Broadway message
    message = %Broadway.Message{
      data: event,
      acknowledger: {__MODULE__, :ack_ref, :ack_data}
    }

    new_queue = :queue.in(message, queue)

    if demand > 0 do
      {events, remaining_queue, remaining_demand} = take_events(new_queue, demand, [])
      {:noreply, events, %{state | queue: remaining_queue, demand: remaining_demand}}
    else
      {:noreply, [], %{state | queue: new_queue}}
    end
  end

  def handle_info({:signal, _signal}, state) do
    # Handle EventBus signals (e.g., subscription confirmations)
    {:noreply, [], state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message in BroadwayProducer", message: inspect(msg))
    {:noreply, [], state}
  end

  # Broadway acknowledger callbacks
  def ack(:ack_ref, successful, failed) do
    # Log acknowledgments
    unless Enum.empty?(successful) do
      Logger.debug("Acknowledged #{length(successful)} events")
    end

    unless Enum.empty?(failed) do
      Logger.warning("Failed to process #{length(failed)} events",
        failures: Enum.map(failed, fn {msg, reason} -> {msg.data.id, reason} end)
      )
    end

    :ok
  end

  # Private functions

  defp take_events(queue, 0, acc), do: {Enum.reverse(acc), queue, 0}

  defp take_events(queue, demand, acc) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        take_events(new_queue, demand - 1, [event | acc])

      {:empty, queue} ->
        {Enum.reverse(acc), queue, demand}
    end
  end
end
