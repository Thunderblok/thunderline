defmodule Jido.Bus.Adapters.InMemory.Subscription do
  @moduledoc false

  @type child_spec_source ::
          Supervisor.child_spec()
          | {module(), atom(), list()}
          | {module(), keyword()}
          | module()
          | pid()

  @doc """
  Normalises a subscriber description into a `Supervisor.child_spec/1` compatible map.

  The upstream adapter expects to start subscribers under a dynamic supervisor but the
  published release of `jido` no longer ships the helper that performed this translation.
  This shim accepts the most common forms the adapter historically supported (module,
  MFA tuple, explicit child spec map, or an existing pid) and turns them into a standard
  child spec so the adapter can keep working.
  """
  @spec child_spec(child_spec_source()) :: Supervisor.child_spec()
  def child_spec(%{start: _} = spec) do
    spec
    |> Map.put_new(:id, make_ref())
    |> Map.put_new(:type, :worker)
  end

  def child_spec({module, function, args})
      when is_atom(module) and is_atom(function) and is_list(args) do
    %{
      id: {module, function, args},
      start: {module, function, args},
      type: :worker,
      shutdown: 5000
    }
  end

  def child_spec({module, opts}) when is_atom(module) and is_list(opts) do
    cond do
      function_exported?(module, :child_spec, 1) ->
        module.child_spec(opts)

      function_exported?(module, :start_link, 1) ->
        %{
          id: {module, opts},
          start: {module, :start_link, [opts]},
          type: :worker,
          shutdown: 5000
        }

      function_exported?(module, :start_link, 0) ->
        %{
          id: module,
          start: {module, :start_link, []},
          type: :worker,
          shutdown: 5000
        }

      true ->
        raise ArgumentError, "cannot derive child spec for #{inspect(module)}"
    end
  end

  def child_spec(module) when is_atom(module) do
    cond do
      function_exported?(module, :child_spec, 1) -> module.child_spec([])
      function_exported?(module, :child_spec, 0) -> module.child_spec()
      function_exported?(module, :start_link, 1) ->
        %{
          id: module,
          start: {module, :start_link, [[]]},
          type: :worker,
          shutdown: 5000
        }

      function_exported?(module, :start_link, 0) ->
        %{
          id: module,
          start: {module, :start_link, []},
          type: :worker,
          shutdown: 5000
        }

      true ->
        raise ArgumentError, "cannot derive child spec for #{inspect(module)}"
    end
  end

  def child_spec(pid) when is_pid(pid) do
    raise ArgumentError, "cannot derive child spec for pid #{inspect(pid)}"
  end
end

defmodule Jido.Bus.Adapters.InMemory.PersistentSubscription do
  @moduledoc false

  alias __MODULE__.Subscriber

  @enforce_keys [:name, :stream_id]
  defstruct name: nil,
            stream_id: nil,
            partition_by: nil,
            start_from: :origin,
            concurrency_limit: 1,
            checkpoint: 0,
            subscribers: []

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          stream_id: term(),
          partition_by: term() | nil,
          start_from: :origin | :current | non_neg_integer(),
          concurrency_limit: pos_integer() | nil,
          checkpoint: non_neg_integer(),
          subscribers: [Subscriber.t()]
        }

  defmodule Subscriber do
    @moduledoc false
    @enforce_keys [:pid]
    defstruct pid: nil, in_flight: MapSet.new(), checkpoint: 0

    @type t :: %__MODULE__{pid: pid(), in_flight: MapSet.t(non_neg_integer()), checkpoint: non_neg_integer()}
  end

  @doc false
  @spec subscribe(t(), pid(), non_neg_integer()) :: t()
  def subscribe(%__MODULE__{} = subscription, pid, checkpoint) when is_pid(pid) do
    checkpoint = normalize_checkpoint(checkpoint)

    new_entry = %Subscriber{pid: pid, checkpoint: checkpoint}

    subscription
    |> prune_dead_subscribers()
    |> Map.update!(:subscribers, fn subscribers -> subscribers ++ [new_entry] end)
    |> Map.put(:checkpoint, checkpoint)
  end

  @doc false
  @spec publish(t(), Jido.Bus.RecordedSignal.t()) :: {:ok, t()} | {:error, :no_subscriber_available}
  def publish(%__MODULE__{} = subscription, signal) do
    subscription = prune_dead_subscribers(subscription)

    case pick_subscriber(subscription) do
      {nil, _before, _after} ->
        {:error, :no_subscriber_available}

      {%Subscriber{} = subscriber, before, rest} ->
        send(subscriber.pid, {:signal, signal})

        subscriber = %Subscriber{
          subscriber
          | in_flight: MapSet.put(subscriber.in_flight, signal.signal_number)
        }

        updated = before ++ [subscriber] ++ rest
        {:ok, %__MODULE__{subscription | subscribers: updated}}
    end
  end

  @doc false
  @spec ack(t(), non_neg_integer()) :: t() | {:error, :unexpected_ack}
  def ack(%__MODULE__{} = subscription, signal_number) when is_integer(signal_number) do
    {updated, found?, latest_checkpoint} =
      Enum.reduce(subscription.subscribers, {[], false, subscription.checkpoint || 0}, fn
        subscriber, {acc, found?, checkpoint_acc} ->
          if not found? and MapSet.member?(subscriber.in_flight, signal_number) do
            updated_subscriber = %Subscriber{
              subscriber
              | in_flight: MapSet.delete(subscriber.in_flight, signal_number),
                checkpoint: max(subscriber.checkpoint, signal_number)
            }

            {[updated_subscriber | acc], true, max(checkpoint_acc, updated_subscriber.checkpoint)}
          else
            {[subscriber | acc], found?, checkpoint_acc}
          end
      end)

    if found? do
      %__MODULE__{
        subscription
        | subscribers: Enum.reverse(updated),
          checkpoint: max(subscription.checkpoint || 0, latest_checkpoint)
      }
    else
      {:error, :unexpected_ack}
    end
  end

  @doc false
  @spec unsubscribe(t(), pid()) :: t()
  def unsubscribe(%__MODULE__{} = subscription, pid) do
    %__MODULE__{subscription | subscribers: Enum.reject(subscription.subscribers, &(&1.pid == pid))}
  end

  @doc false
  @spec has_subscriber?(t(), pid()) :: boolean()
  def has_subscriber?(%__MODULE__{} = subscription, pid) do
    Enum.any?(subscription.subscribers, fn %Subscriber{pid: existing_pid} -> existing_pid == pid end)
  end

  defp prune_dead_subscribers(%__MODULE__{} = subscription) do
    filtered =
      Enum.filter(subscription.subscribers, fn %Subscriber{pid: pid} ->
        is_pid(pid) and Process.alive?(pid)
      end)

    %__MODULE__{subscription | subscribers: filtered}
  end

  defp pick_subscriber(%__MODULE__{subscribers: []}), do: {nil, [], []}

  defp pick_subscriber(%__MODULE__{subscribers: subscribers} = subscription) do
    concurrency = subscription.concurrency_limit || 1

    {before, remaining} =
      Enum.split_while(subscribers, fn %Subscriber{in_flight: in_flight} ->
        MapSet.size(in_flight) >= concurrency
      end)

    case remaining do
      [selected | tail] -> {selected, before, tail}
      [] -> {nil, before, []}
    end
  end

  defp normalize_checkpoint(nil), do: 0
  defp normalize_checkpoint(value) when is_integer(value) and value >= 0, do: value
  defp normalize_checkpoint(_), do: 0
end
