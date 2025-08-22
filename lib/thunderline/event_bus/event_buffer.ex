defmodule Thunderline.EventBus.EventBuffer do
  @moduledoc """
  Rolling in-memory event buffer (ETS) for dashboard streaming.

  Features:
  - Fixed-size ring (configurable :limit, default 500)
  - Normalizes disparate PubSub/domain/telemetry events into a common map
  - Provides subscription broadcasting to LiveViews via PubSub topic "dashboard:events"
  - Cheap snapshot retrieval for initial mount
  """
  use GenServer
  require Logger

  @table __MODULE__
  @default_limit 500
  @topic "dashboard:events"

  # Public API
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def put(raw_event), do: GenServer.cast(__MODULE__, {:put, raw_event})
  def snapshot(limit \\ 100) do
    case :ets.lookup(@table, :events) do
      [{:events, list}] -> Enum.take(list, limit)
      _ -> []
    end
  end

  def topic, do: @topic

  # GenServer callbacks
  @impl true
  def init(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    :ets.insert(@table, {:events, []})
    state = %{limit: limit}
    Logger.info("[EventBuffer] started (limit=#{limit})")
    {:ok, state}
  end

  @impl true
  def handle_cast({:put, raw}, %{limit: limit} = state) do
    event = normalize(raw)
    :ets.update_element(@table, :events, {2, ring_insert(current_events(), event, limit)})
    Phoenix.PubSub.broadcast(Thunderline.PubSub, @topic, {:dashboard_event, event})
    {:noreply, state}
  end

  # Helpers
  defp current_events do
    case :ets.lookup(@table, :events) do
      [{:events, list}] -> list
      _ -> []
    end
  end

  defp ring_insert(list, item, limit) do
    new_list = [item | list]
    if length(new_list) > limit, do: Enum.take(new_list, limit), else: new_list
  end

  # Normalization pipeline
  defp normalize(%{__struct__: _} = struct), do: struct |> Map.from_struct() |> normalize()
  defp normalize(%{type: :status_update} = m), do: base(m, :domain_event)
  defp normalize({:domain_event, domain, payload}) when is_map(payload) do
    payload
    |> Map.put(:domain, domain)
    |> base(:domain_event)
  end
  defp normalize({:agent_event, payload}) when is_map(payload), do: base(Map.put(payload, :domain, :thunderbit), :agent_event)
  defp normalize({:chunk_event, payload}) when is_map(payload), do: base(Map.put(payload, :domain, :thunderbolt), :chunk_event)
  defp normalize({:ash_telemetry, data}) when is_map(data), do: base(Map.put(data, :domain, data.domain || :ash_core), :telemetry)
  defp normalize(map) when is_map(map), do: base(map, Map.get(map, :kind, :generic))
  defp normalize(other), do: base(%{message: inspect(other)}, :unknown)

  defp base(map, kind) do
    ts = map[:timestamp] || System.system_time(:microsecond)
    %{
      id: System.unique_integer([:positive, :monotonic]),
      kind: kind,
      domain: map[:domain] || map[:type] || :system,
      message: map[:message] || summarize(map),
      status: map[:status] || map[:result] || :info,
      source: map[:source] || map[:resource] || to_string(kind),
      timestamp: ts
    }
  end

  defp summarize(map) do
    keys = map |> Map.keys() |> Enum.take(5)
    "event #{Enum.map_join(keys, ",", &to_string/1)}"
  end
end
