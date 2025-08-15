defmodule Thunderflow.MnesiaProducer do
  @moduledoc """
  Broadway producer that uses Mnesia (via Memento) as the message queue.

  This producer polls Mnesia tables for events to process, providing:
  - Persistent message storage without external dependencies
  - Built-in clustering and replication
  - ACID transactions for reliable event processing
  - Configurable polling intervals and batch sizes
  """

  use GenStage
  require Logger

  alias Memento.Table
  alias Memento.Transaction

  @behaviour Broadway.Producer
  @behaviour Broadway.Acknowledger

  defmodule State do
    @moduledoc false
    defstruct [
      :table,
      :demand,
      :poll_interval,
      :max_batch_size,
      :ack_ref,
      :broadway_name
    ]
  end

  # Mnesia table schema for events
  use Memento.Table,
    attributes: [
      :id,
      :data,
      :created_at,
      :status,
      :attempts,
      :pipeline_type,
      :priority
    ],
    index: [:status, :pipeline_type, :priority, :created_at],
    type: :ordered_set

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl GenStage
  def init(opts) do
    table = Keyword.get(opts, :table, __MODULE__)
    poll_interval = Keyword.get(opts, :poll_interval, 1000)
    max_batch_size = Keyword.get(opts, :max_batch_size, 50)
    broadway_name = Keyword.get(opts, :broadway_name)

    # Ensure table exists
    ensure_table_exists(table)

    # Schedule initial poll
    schedule_poll(poll_interval)

    state = %State{
      table: table,
      demand: 0,
      poll_interval: poll_interval,
      max_batch_size: max_batch_size,
      ack_ref: make_ref(),
      broadway_name: broadway_name
    }

    {:producer, state}
  end

  @impl GenStage
  def handle_demand(incoming_demand, %State{demand: pending_demand} = state) do
    new_demand = incoming_demand + pending_demand

    case fetch_events(state.table, min(new_demand, state.max_batch_size)) do
      {:ok, []} ->
        # No events available, update demand and wait for next poll
        {:noreply, [], %{state | demand: new_demand}}

      {:ok, events} ->
        messages = convert_events_to_messages(events, state.ack_ref)
        remaining_demand = max(0, new_demand - length(messages))

        Logger.debug("MnesiaProducer: Delivering #{length(messages)} events")

        {:noreply, messages, %{state | demand: remaining_demand}}

      {:error, reason} ->
        Logger.error("MnesiaProducer: Failed to fetch events: #{inspect(reason)}")
        {:noreply, [], %{state | demand: new_demand}}
    end
  end

  @impl GenStage
  def handle_info(:poll, state) do
    # Schedule next poll
    schedule_poll(state.poll_interval)

    # If there's demand and no recent activity, try to fetch events
    if state.demand > 0 do
      case fetch_events(state.table, min(state.demand, state.max_batch_size)) do
        {:ok, []} ->
          {:noreply, [], state}

        {:ok, events} ->
          messages = convert_events_to_messages(events, state.ack_ref)
          remaining_demand = max(0, state.demand - length(messages))

          {:noreply, messages, %{state | demand: remaining_demand}}

        {:error, reason} ->
          Logger.error("MnesiaProducer: Failed to fetch events: #{inspect(reason)}")
          {:noreply, [], state}
      end
    else
      {:noreply, [], state}
    end
  end

  @impl GenStage
  def handle_info(msg, state) do
    Logger.debug("MnesiaProducer: Unexpected message #{inspect(msg)}")
    {:noreply, [], state}
  end

  # Broadway.Producer callbacks

  @impl Broadway.Producer
  def prepare_for_start(_module, broadway_config) do
    {[], broadway_config}
  end

  @impl Broadway.Producer
  def prepare_for_draining(%State{} = state) do
    # Mark any in-flight events as failed so they can be retried
    Transaction.execute(fn ->
      # Use dynamic pattern matching based on table structure
      match_pattern =
        case state.table do
          Thunderflow.CrossDomainEvents ->
            {{state.table, :_, :_, :_, :processing, :_, :_, :_, :_}, [], [:"$_"]}

          Thunderflow.RealTimeEvents ->
            {{state.table, :_, :_, :_, :processing, :_, :_, :_, :_}, [], [:"$_"]}

          _ ->
            # Default 7-attribute pattern for basic MnesiaProducer table
            {{state.table, :_, :_, :_, :processing, :_, :_, :_}, [], [:"$_"]}
        end

      Memento.Query.select(state.table, [match_pattern])
      |> Enum.each(fn event ->
        updated_event = %{event | status: :failed, attempts: event.attempts + 1}
        Memento.Query.write(updated_event)
      end)
    end)

    {:noreply, [], state}
  end

  # Public API for adding events to the queue

  @doc """
  Add a single event to the Mnesia queue for processing.
  """
  def enqueue_event(table \\ __MODULE__, data, opts \\ []) do
    pipeline_type = Keyword.get(opts, :pipeline_type, :general)
    priority = Keyword.get(opts, :priority, :normal)

    event = %__MODULE__{
      id: generate_event_id(),
      data: data,
      created_at: DateTime.utc_now(),
      status: :pending,
      attempts: 0,
      pipeline_type: pipeline_type,
      priority: priority
    }

    case Transaction.execute(fn -> Memento.Query.write(event) end) do
      {:ok, _} ->
        Logger.debug("MnesiaProducer: Enqueued event #{event.id}")
        :ok

      {:error, reason} ->
        Logger.error("MnesiaProducer: Failed to enqueue event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Add multiple events to the queue in a single transaction.
  """
  def enqueue_events(table \\ __MODULE__, events, opts \\ []) do
    pipeline_type = Keyword.get(opts, :pipeline_type, :general)
    priority = Keyword.get(opts, :priority, :normal)

    mnesia_events =
      Enum.map(events, fn data ->
        %__MODULE__{
          id: generate_event_id(),
          data: data,
          created_at: DateTime.utc_now(),
          status: :pending,
          attempts: 0,
          pipeline_type: pipeline_type,
          priority: priority
        }
      end)

    case Transaction.execute(fn ->
           Enum.each(mnesia_events, &Memento.Query.write/1)
         end) do
      {:ok, _} ->
        Logger.debug("MnesiaProducer: Enqueued #{length(events)} events")
        :ok

      {:error, reason} ->
        Logger.error("MnesiaProducer: Failed to enqueue events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get queue statistics for monitoring.
  """
  def queue_stats(table \\ __MODULE__) do
    case Transaction.execute(fn ->
           # Use dynamic pattern matching based on table structure
           {pending_pattern, processing_pattern, failed_pattern} =
             case table do
               Thunderflow.CrossDomainEvents ->
                 {
                   {{table, :_, :_, :_, :pending, :_, :_, :_, :_}, [], [true]},
                   {{table, :_, :_, :_, :processing, :_, :_, :_, :_}, [], [true]},
                   {{table, :_, :_, :_, :failed, :_, :_, :_, :_}, [], [true]}
                 }

               Thunderflow.RealTimeEvents ->
                 {
                   {{table, :_, :_, :_, :pending, :_, :_, :_, :_}, [], [true]},
                   {{table, :_, :_, :_, :processing, :_, :_, :_, :_}, [], [true]},
                   {{table, :_, :_, :_, :failed, :_, :_, :_, :_}, [], [true]}
                 }

               _ ->
                 # Default 7-attribute patterns for basic MnesiaProducer table
                 {
                   {{table, :_, :_, :_, :pending, :_, :_, :_}, [], [true]},
                   {{table, :_, :_, :_, :processing, :_, :_, :_}, [], [true]},
                   {{table, :_, :_, :_, :failed, :_, :_, :_}, [], [true]}
                 }
             end

           pending = Memento.Query.select(table, [pending_pattern]) |> length()
           processing = Memento.Query.select(table, [processing_pattern]) |> length()
           failed = Memento.Query.select(table, [failed_pattern]) |> length()

           %{
             pending: pending,
             processing: processing,
             failed: failed,
             total: pending + processing + failed
           }
         end) do
      {:ok, stats} -> stats
      {:error, _} -> %{pending: 0, processing: 0, failed: 0, total: 0}
    end
  end

  # Private functions

  defp ensure_table_exists(table) do
    case Memento.Table.create(table) do
      :ok ->
        Logger.info("MnesiaProducer: Created table #{table}")
        :ok

      {:error, {:already_exists, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("MnesiaProducer: Failed to create table #{table}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp fetch_events(table_name, limit) do
    try do
      # Correct Mnesia match specification format
      # {Pattern, Guards, Result}
      query = [
        {{table_name, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"},
         [{:==, :"$4", :pending}], [:"$_"]}
      ]

      case :mnesia.transaction(fn ->
             :mnesia.select(table_name, query, limit, :read)
           end) do
        {:atomic, {events, _continuation}} when is_list(events) ->
          {:ok, events}

        {:atomic, :"$end_of_table"} ->
          {:ok, []}

        {:atomic, events} when is_list(events) ->
          {:ok, events}

        {:aborted, reason} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("MnesiaProducer: Failed to fetch events: #{inspect(error)}")
        {:error, error}
    end
  end

  defp convert_events_to_messages(events, ack_ref) do
    Enum.map(events, fn event ->
      %Broadway.Message{
        data: event.data,
        metadata: %{
          event_id: event.id,
          created_at: event.created_at,
          attempts: event.attempts,
          pipeline_type: event.pipeline_type,
          priority: event.priority
        },
        acknowledger: {__MODULE__, ack_ref, %{event_id: event.id}}
      }
    end)
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  # Broadway acknowledger implementation

  @impl Broadway.Acknowledger
  def ack(ack_ref, successful, failed) do
    # Handle successful messages
    Enum.each(successful, fn message ->
      event_id = get_in(message.acknowledger, [2, :event_id])
      delete_event(event_id)
    end)

    # Handle failed messages - increment attempts and potentially move to DLQ
    Enum.each(failed, fn message ->
      event_id = get_in(message.acknowledger, [2, :event_id])
      handle_failed_event(event_id, message.status)
    end)

    :ok
  end

  defp delete_event(event_id) do
    case Transaction.execute(fn ->
           case Memento.Query.read(__MODULE__, event_id) do
             nil -> :ok
             event -> Memento.Query.delete_record(event)
           end
         end) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("MnesiaProducer: Failed to delete event #{event_id}: #{inspect(reason)}")
        :error
    end
  end

  defp handle_failed_event(event_id, status) do
    case Transaction.execute(fn ->
           case Memento.Query.read(__MODULE__, event_id) do
             nil ->
               :ok

             event ->
               new_attempts = event.attempts + 1

               cond do
                 new_attempts >= 3 ->
                   # Move to dead letter queue
                   %{event | status: :dead_letter, attempts: new_attempts}
                   |> Memento.Query.write()

                 true ->
                   # Retry later
                   %{event | status: :failed, attempts: new_attempts}
                   |> Memento.Query.write()
               end
           end
         end) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "MnesiaProducer: Failed to handle failed event #{event_id}: #{inspect(reason)}"
        )

        :error
    end
  end
end
