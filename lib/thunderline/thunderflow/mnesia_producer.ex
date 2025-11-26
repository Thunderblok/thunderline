defmodule Thunderline.Thunderflow.MnesiaProducer do
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

  # alias Memento.Table  # unused
  alias Memento.Transaction
  alias Thunderline.Thunderflow.RetryPolicy

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

    case fetch_and_claim_events(state.table, min(new_demand, state.max_batch_size)) do
      {:ok, []} ->
        # No events available, update demand and wait for next poll
        {:noreply, [], %{state | demand: new_demand}}

      {:ok, events} ->
        messages = convert_events_to_messages(events, state.ack_ref, state.table)
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
      case fetch_and_claim_events(state.table, min(state.demand, state.max_batch_size)) do
        {:ok, []} ->
          {:noreply, [], state}

        {:ok, events} ->
          messages = convert_events_to_messages(events, state.ack_ref, state.table)
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
      revert_processing_to_failed(state.table)
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

    ensure_table_exists(table)

    record_tuple =
      build_record_tuple(table, data, %{
        id: generate_event_id(),
        data: data,
        created_at: DateTime.utc_now(),
        status: :pending,
        attempts: 0,
        pipeline_type: pipeline_type,
        priority: priority
      })

    case :mnesia.transaction(fn -> :mnesia.write(record_tuple) end) do
      {:atomic, :ok} ->
        Logger.debug("MnesiaProducer: Enqueued event #{elem(record_tuple, 1)} into #{table}")
        :ok

      {:aborted, reason} ->
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

    ensure_table_exists(table)

    tuples =
      Enum.map(events, fn data ->
        build_record_tuple(table, data, %{
          id: generate_event_id(),
          data: data,
          created_at: DateTime.utc_now(),
          status: :pending,
          attempts: 0,
          pipeline_type: pipeline_type,
          priority: priority
        })
      end)

    case :mnesia.transaction(fn -> Enum.each(tuples, &:mnesia.write/1) end) do
      {:atomic, :ok} ->
        Logger.debug("MnesiaProducer: Enqueued #{length(events)} events into #{table}")
        :ok

      {:aborted, reason} ->
        Logger.error("MnesiaProducer: Failed to enqueue events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get queue statistics for monitoring.
  """
  def queue_stats(table \\ __MODULE__) do
    with {:atomic, stats} <-
           :mnesia.transaction(fn ->
             attrs = :mnesia.table_info(table, :attributes)
             status_index = Enum.find_index(attrs, &(&1 == :status))
             # we just reuse for guard building
             _dead_letter_index = status_index

             {pending, processing, failed, dead_letter} =
               Enum.reduce(
                 [:pending, :processing, :failed, :dead_letter],
                 {0, 0, 0, 0},
                 fn status, {p, pr, f, dl} ->
                   count = select_count_by_status(table, status, status_index, length(attrs))

                   case status do
                     :pending -> {count, pr, f, dl}
                     :processing -> {p, count, f, dl}
                     :failed -> {p, pr, count, dl}
                     :dead_letter -> {p, pr, f, count}
                   end
                 end
               )

             %{
               pending: pending,
               processing: processing,
               failed: failed,
               dead_letter: dead_letter,
               total: pending + processing + failed + dead_letter
             }
           end) do
      stats
    else
      _ -> %{pending: 0, processing: 0, failed: 0, dead_letter: 0, total: 0}
    end
  end

  # Private functions

  defp ensure_table_exists(table) do
    case Memento.Table.create(table) do
      {:atomic, :ok} ->
        Logger.info("MnesiaProducer: Created table #{table}")
        :ok

      :ok ->
        Logger.info("MnesiaProducer: Created table #{table}")
        :ok

      {:error, {:already_exists, _}} ->
        :ok

      {:aborted, {:already_exists, _}} ->
        :ok

      other ->
        Logger.error("MnesiaProducer: Failed to create table #{table}: #{inspect(other)}")
        {:error, other}
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  # Fetch & claim pending events atomically, flipping status to :processing to avoid duplicates
  defp fetch_and_claim_events(table, limit) when limit > 0 do
    try do
      attrs = :mnesia.table_info(table, :attributes)
      status_index = Enum.find_index(attrs, &(&1 == :status))
      _attempts_index = Enum.find_index(attrs, &(&1 == :attempts))

      case :mnesia.transaction(fn ->
             pending = select_raw_records(table, :pending, status_index, length(attrs), limit)

             # Flip status to :processing in-place
             Enum.each(pending, fn record ->
               tuple_list = Tuple.to_list(record)
               # tuple_list = [table | attr_vals]
               attr_vals = tl(tuple_list)

               updated_attr_vals =
                 attr_vals
                 |> List.update_at(status_index, fn _ -> :processing end)

               updated_record = List.to_tuple([table | updated_attr_vals])
               :mnesia.write(updated_record)
             end)

             pending
           end) do
        {:atomic, records} when is_list(records) -> {:ok, records}
        {:atomic, _} -> {:ok, []}
        {:aborted, reason} -> {:error, reason}
      end
    rescue
      error ->
        Logger.error("MnesiaProducer: Failed to fetch & claim events: #{inspect(error)}")
        {:error, error}
    end
  end

  defp fetch_and_claim_events(_table, _limit), do: {:ok, []}

  defp convert_events_to_messages(records, ack_ref, table) do
    Enum.map(records, fn record ->
      # We only rely on the canonical base attributes order defined in each table
      # id & data are always first two attributes after table name; created_at 3rd; attempts 5th; etc.
      # Safer dynamic extraction using table info
      attrs = :mnesia.table_info(table, :attributes)
      values = Tuple.to_list(record) |> tl()
      attr_map = Enum.zip(attrs, values) |> Map.new()

      %Broadway.Message{
        data: Map.get(attr_map, :data),
        metadata: %{
          event_id: Map.get(attr_map, :id),
          created_at: Map.get(attr_map, :created_at),
          attempts: Map.get(attr_map, :attempts),
          pipeline_type: Map.get(attr_map, :pipeline_type),
          priority: Map.get(attr_map, :priority),
          table: table
        },
        acknowledger: {__MODULE__, ack_ref, %{event_id: Map.get(attr_map, :id), table: table}}
      }
    end)
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  # Broadway acknowledger implementation

  @impl Broadway.Acknowledger
  def ack(_ack_ref, successful, failed) do
    # Broadway passes back the same tuple we set on the message: {mod, ack_ref, metadata_map}
    # Avoid get_in/Access on a tuple (was raising FunctionClauseError). Pattern match instead.
    Enum.each(successful, fn %{
                               acknowledger:
                                 {__MODULE__, _ref, %{event_id: event_id, table: table}}
                             } ->
      delete_event(table, event_id)
    end)

    Enum.each(failed, fn %{acknowledger: {__MODULE__, _ref, %{event_id: event_id, table: table}}} =
                           msg ->
      handle_failed_event(table, event_id, msg.status, msg)
    end)

    :ok
  end

  defp delete_event(table, event_id) do
    :mnesia.transaction(fn ->
      case :mnesia.read(table, event_id) do
        [] -> :ok
        [record] -> :mnesia.delete_object(record)
      end
    end)
  end

  defp handle_failed_event(table, event_id, status, message \\ nil)
       when is_tuple(status) or is_atom(status) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(table, event_id) do
          [] ->
            {:noop, nil}

          [record] ->
            attrs = :mnesia.table_info(table, :attributes)
            values = Tuple.to_list(record) |> tl()
            attr_map = Enum.zip(attrs, values) |> Map.new()

            policy =
              attr_map
              |> Map.get(:data)
              |> RetryPolicy.for_event()

            current_attempts = attr_map.attempts || 0

            metadata_attempt =
              case message do
                %Broadway.Message{metadata: metadata} ->
                  metadata[:attempts] || metadata[:attempt]

                _ ->
                  nil
              end

            next_attempt =
              case metadata_attempt do
                nil -> current_attempts + 1
                val -> max(val, current_attempts + 1)
              end

            cond do
              match?({:dlq, _}, status) or RetryPolicy.exhausted?(policy, next_attempt) ->
                updated_record =
                  rewrite_record(table, attrs, attr_map,
                    attempts: next_attempt,
                    status: :dead_letter
                  )

                :mnesia.write(updated_record)
                {:dead_letter, nil}

              match?({:retry, _}, status) ->
                {:retry, delay} = status

                updated_record =
                  rewrite_record(table, attrs, attr_map,
                    attempts: next_attempt,
                    status: :retrying
                  )

                :mnesia.write(updated_record)
                {:schedule_retry, delay}

              true ->
                updated_record =
                  rewrite_record(table, attrs, attr_map,
                    attempts: next_attempt,
                    status: :failed
                  )

                :mnesia.write(updated_record)
                {:failed, nil}
            end
        end
      end)

    case result do
      {:atomic, {:schedule_retry, delay}} ->
        schedule_retry(table, event_id, delay)

      _ ->
        :ok
    end
  end

  defp rewrite_record(table, attrs, attr_map, overrides) do
    overrides_map = Map.new(overrides)
    updated_attr_map = Map.merge(attr_map, overrides_map)
    updated_values = Enum.map(attrs, &Map.get(updated_attr_map, &1))
    List.to_tuple([table | updated_values])
  end

  defp schedule_retry(_table, _event_id, delay) when delay <= 0 do
    requeue_event(_table, _event_id)
  end

  defp schedule_retry(table, event_id, delay) do
    Task.start(fn ->
      Process.sleep(delay)
      requeue_event(table, event_id)
    end)

    :ok
  end

  defp requeue_event(table, event_id) do
    :mnesia.transaction(fn ->
      case :mnesia.read(table, event_id) do
        [] ->
          :ok

        [record] ->
          attrs = :mnesia.table_info(table, :attributes)
          values = Tuple.to_list(record) |> tl()
          attr_map = Enum.zip(attrs, values) |> Map.new()

          if attr_map.status in [:retrying, :failed] do
            updated_record = rewrite_record(table, attrs, attr_map, status: :pending)
            :mnesia.write(updated_record)
          end

          :ok
      end
    end)
  end

  # --- Internal helpers ----------------------------------------------------

  defp build_record_tuple(table, incoming_data, base_values) do
    attrs = :mnesia.table_info(table, :attributes)

    # Provide extended attribute values if the table expects them
    extended_values =
      case table do
        Thunderline.Thunderflow.CrossDomainEvents ->
          %{
            from_domain:
              Map.get(incoming_data, :from_domain) || Map.get(incoming_data, "from_domain"),
            to_domain: Map.get(incoming_data, :to_domain) || Map.get(incoming_data, "to_domain")
          }

        Thunderline.Thunderflow.RealTimeEvents ->
          %{
            event_type: Map.get(incoming_data, :type) || Map.get(incoming_data, "type"),
            latency_requirement: Map.get(incoming_data, :latency_requirement) || :normal
          }

        _ ->
          %{}
      end

    full_values = Map.merge(base_values, extended_values)

    attr_vals = Enum.map(attrs, &Map.get(full_values, &1))
    List.to_tuple([table | attr_vals])
  end

  defp select_raw_records(table, status, status_index, attr_len, limit) do
    # Build dynamic match spec
    vars = for i <- 1..attr_len, do: String.to_atom("$#{i}")
    status_var = Enum.at(vars, status_index)
    pattern = List.to_tuple([table | vars])
    spec = [{pattern, [{:==, status_var, status}], [:"$_"]}]

    case :mnesia.select(table, spec, limit, :read) do
      {records, _cont} when is_list(records) -> records
      :"$end_of_table" -> []
      other when is_list(other) -> other
      _ -> []
    end
  end

  defp select_count_by_status(table, status, status_index, attr_len) do
    vars = for i <- 1..attr_len, do: String.to_atom("$#{i}")
    status_var = Enum.at(vars, status_index)
    pattern = List.to_tuple([table | vars])
    spec = [{pattern, [{:==, status_var, status}], [true]}]

    case :mnesia.select(table, spec) do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp revert_processing_to_failed(table) do
    :mnesia.transaction(fn ->
      attrs = :mnesia.table_info(table, :attributes)
      status_index = Enum.find_index(attrs, &(&1 == :status))
      vars = for i <- 1..length(attrs), do: String.to_atom("$#{i}")
      status_var = Enum.at(vars, status_index)
      pattern = List.to_tuple([table | vars])
      spec = [{pattern, [{:==, status_var, :processing}], [:"$_"]}]

      case :mnesia.select(table, spec) do
        list when is_list(list) ->
          Enum.each(list, fn record ->
            values = Tuple.to_list(record) |> tl()
            attr_map = Enum.zip(attrs, values) |> Map.new()

            updated_attr_vals =
              attrs
              |> Enum.map(fn attr ->
                case attr do
                  :status -> :failed
                  :attempts -> attr_map.attempts + 1
                  _ -> Map.get(attr_map, attr)
                end
              end)

            :mnesia.write(List.to_tuple([table | updated_attr_vals]))
          end)

        _ ->
          :ok
      end
    end)
  end
end
