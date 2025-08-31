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

  @pubsub Thunderline.PubSub
  @table :thundergrid_zones

  # Client API

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Claim a zone for a tenant. Returns {:ok, meta} | {:error, :owned}"
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
  def watch_zone(zone_id, opts \\ []) when is_binary(zone_id) do
    topic = zone_topic(zone_id)
    :ok = PubSub.subscribe(@pubsub, topic)
    {:ok, topic}
  end

  # Server callbacks
  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, read_concurrency: true])
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
        [{^zone_id, %{owner: ^tenant} = meta}] -> {:ok, meta}
        [{^zone_id, _other}] -> {:error, :owned}
      end
    :telemetry.execute([:thunderline, :grid, :claim_zone], %{count: 1}, %{zone: zone_id, tenant: tenant, result: elem(reply,0)})
    {:reply, reply, state}
  end

  # Helpers
  defp publish(event, meta) do
    Thunderline.EventBus.emit(:grid_event, %{event_name: "grid." <> Atom.to_string(event), domain: "thundergrid", meta: meta})
    PubSub.broadcast(@pubsub, zone_topic(meta.zone), {event, meta})
  end

  defp zone_topic(zone_id), do: "grid:zone:" <> zone_id
end
