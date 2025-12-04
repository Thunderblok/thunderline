defmodule Thunderline.Thundergrid.API do
  @moduledoc """
  Thundergrid authoritative zone & placement API (WARHORSE Phase 1 skeleton).

  Responsibilities:
    * claim_zone/2 - attempt to acquire ownership of a zone for a tenant/actor
    * placement_for/1 - return placement metadata for a zone
    * watch_zone/2 - subscribe caller to zone change events (via EventBus / PubSub)

  Phase 1: ETS-backed registry with simple compare-and-set semantics & telemetry.
  Future: persistence via Block (Postgres) and conflict resolution strategies.
  """
  use GenServer
  alias Phoenix.PubSub
  require Logger

  @pubsub Thunderline.PubSub
  @table :thundergrid_zones

  # Client API

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @zone_ttl_ms 60_000
  @doc "Claim a zone for a tenant. Returns {:ok, meta} | {:error, :owned} | {:error, :conflict}"
  def claim_zone(zone_id, tenant) when is_binary(zone_id) and is_binary(tenant) do
    GenServer.call(__MODULE__, {:claim, zone_id, tenant})
  end

  @doc "Fetch placement metadata for a zone (owner, ts)."
  def placement_for(zone_id) when is_binary(zone_id) do
    case :ets.lookup(@table, zone_id) do
      [{^zone_id, meta}] -> {:ok, meta}
      _ -> {:error, :not_found}
    end
  end

  @doc "Subscribe current process to zone change events."
  def watch_zone(zone_id, _opts \\ []) when is_binary(zone_id) do
    topic = zone_topic(zone_id)
    :ok = PubSub.subscribe(@pubsub, topic)
    {:ok, topic}
  end

  # Server callbacks
  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, read_concurrency: true])
    schedule_reap()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:claim, zone_id, tenant}, _from, state) do
    now = System.system_time(:millisecond)

    reply =
      case :ets.lookup(@table, zone_id) do
        [] ->
          meta = %{zone: zone_id, owner: tenant, since: now}
          true = :ets.insert(@table, {zone_id, meta})
          publish(:zone_claimed, meta)
          {:ok, meta}

        [{^zone_id, %{owner: ^tenant} = meta}] ->
          {:ok, meta}

        [{^zone_id, %{since: since} = meta}] ->
          if expired?(since, now) do
            # Reclaim stale zone
            new_meta = %{
              zone: zone_id,
              owner: tenant,
              since: now,
              prev_owner: meta.owner,
              reclaimed: true
            }

            true = :ets.insert(@table, {zone_id, new_meta})
            publish(:zone_reclaimed, new_meta)
            {:ok, new_meta}
          else
            conflict_meta = %{
              zone: zone_id,
              owner: meta.owner,
              attempted_owner: tenant,
              since: meta.since
            }

            publish(:zone_conflict, conflict_meta)
            {:error, :owned}
          end
      end

    :telemetry.execute([:thunderline, :grid, :claim_zone], %{count: 1}, %{
      zone: zone_id,
      tenant: tenant,
      result: elem(reply, 0)
    })

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:reap_expired, state) do
    now = System.system_time(:millisecond)

    expired =
      for {zone_id, %{since: since} = meta} <- :ets.tab2list(@table),
          expired?(since, now),
          do: {zone_id, meta}

    Enum.each(expired, fn {zone_id, meta} ->
      :ets.delete(@table, zone_id)
      publish(:zone_expired, Map.put(meta, :expired_at, now))
    end)

    schedule_reap()
    {:noreply, state}
  end

  # Helpers
  defp publish(event, meta) do
    event_name = "grid." <> Atom.to_string(event)

    with {:ok, ev} <-
           Thunderline.Event.new(
             name: event_name,
             source: :flow,
             payload: %{domain: "thundergrid", meta: meta},
             meta: %{pipeline: :realtime}
           ) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[Thundergrid.API] publish #{event_name} failed: #{inspect(reason)} zone=#{meta.zone}"
          )
      end
    end

    PubSub.broadcast(@pubsub, zone_topic(meta.zone), {event, meta})
    telemetry_event(event, meta)
  end

  defp zone_topic(zone_id), do: "grid:zone:" <> zone_id
  defp expired?(since, now), do: now - since > @zone_ttl_ms
  defp schedule_reap, do: Process.send_after(self(), :reap_expired, @zone_ttl_ms)

  defp telemetry_event(:zone_claimed, meta),
    do: :telemetry.execute([:thunderline, :grid, :zone, :claimed], %{count: 1}, meta)

  defp telemetry_event(:zone_reclaimed, meta),
    do: :telemetry.execute([:thunderline, :grid, :zone, :reclaimed], %{count: 1}, meta)

  defp telemetry_event(:zone_expired, meta),
    do: :telemetry.execute([:thunderline, :grid, :zone, :expired], %{count: 1}, meta)

  defp telemetry_event(:zone_conflict, meta),
    do: :telemetry.execute([:thunderline, :grid, :zone, :conflict], %{count: 1}, meta)

  defp telemetry_event(_, _), do: :ok
end
