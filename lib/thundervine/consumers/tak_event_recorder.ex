defmodule Thundervine.TAKEventRecorder do
  @moduledoc ~S"""
  GenServer that subscribes to TAK Runner PubSub streams and persists
  chunk evolution events to Thundervine.

  ## Architecture

  ```
  TAK.Runner → PubSub.broadcast("ca:<run_id>", {:ca_delta, msg})
       ↓
  TAKEventRecorder subscribes → handle_info({:ca_delta, msg})
       ↓
  Convert to TAKChunkEvolved event
       ↓
  Persist to Thundervine.TAKChunkEvent resource
  ```

  ## Usage

  ```elixir
  # Start recorder for a specific TAK run
  {:ok, pid} = Thundervine.TAKEventRecorder.start_link(run_id: "my_run")

  # Or start via supervisor (automatically subscribes)
  children = [
    {Thundervine.TAKEventRecorder, run_id: "my_run"}
  ]
  ```
  """

  use GenServer
  require Logger

  alias Thunderline.Events.TAKChunkEvolved
  alias Thundervine.TAKChunkEvent

  @type state :: %{
          run_id: String.t(),
          zone_id: String.t(),
          stats: map()
        }

  # Client API

  @doc """
  Start a TAK event recorder for a specific run.

  ## Options

  - `:run_id` - TAK run identifier to subscribe to (required)
  - `:zone_id` - Zone identifier for event metadata (default: run_id)
  - `:name` - Optional GenServer name
  """
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = Keyword.get(opts, :name, {:via, Registry, {Thundervine.Registry, {__MODULE__, run_id}}})
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Get recorder statistics.
  """
  def get_stats(pid) when is_pid(pid) do
    GenServer.call(pid, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    zone_id = Keyword.get(opts, :zone_id, run_id)

    # Subscribe to TAK PubSub stream
    :ok = Phoenix.PubSub.subscribe(Thunderline.PubSub, "ca:#{run_id}")

    state = %{
      run_id: run_id,
      zone_id: zone_id,
      stats: %{
        events_received: 0,
        events_persisted: 0,
        events_failed: 0,
        last_tick: nil,
        started_at: DateTime.utc_now()
      }
    }

    Logger.info("[TAKEventRecorder] Started for run_id=#{run_id} zone_id=#{zone_id}")

    {:ok, state}
  end

  @impl true
  def handle_info({:ca_delta, msg}, state) do
    # msg = %{
    #   run_id: run_id,
    #   seq: seq,
    #   generation: gen,
    #   cells: deltas,  # list of %{coord: {x,y}, old: int, new: int}
    #   timestamp: ts
    # }

    new_stats = update_in(state.stats.events_received, &(&1 + 1))

    # Normalize cells to diffs format (coord -> voxel_id)
    diffs =
      Enum.map(msg.cells, fn cell ->
        %{
          voxel_id: cell.coord,
          old: cell.old,
          new: cell.new
        }
      end)

    # Convert PubSub message to TAKChunkEvolved event
    event = %TAKChunkEvolved{
      zone_id: state.zone_id,
      chunk_id: {0, 0, 0},  # Default chunk - could be extracted from run metadata
      tick_id: msg.generation,
      diffs: diffs,
      rule_hash: compute_rule_hash(state.run_id),
      meta: %{
        run_id: msg.run_id,
        seq: msg.seq,
        timestamp: msg.timestamp
      }
    }

    # Persist to Thundervine
    case persist_event(event) do
      {:ok, _record} ->
        new_stats =
          new_stats
          |> update_in([:events_persisted], &(&1 + 1))
          |> Map.put(:last_tick, msg.generation)

        {:noreply, %{state | stats: new_stats}}

      {:error, reason} ->
        Logger.warning("[TAKEventRecorder] Failed to persist event: #{inspect(reason)}")

        new_stats = update_in(new_stats, [:events_failed], &(&1 + 1))
        {:noreply, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Private Helpers

  defp persist_event(%TAKChunkEvolved{} = event) do
    attrs = %{
      zone_id: event.zone_id,
      chunk_coords: Tuple.to_list(event.chunk_id),
      tick_id: event.tick_id,
      diffs: event.diffs,
      rule_hash: event.rule_hash,
      meta: event.meta || %{}
    }

    TAKChunkEvent
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(domain: Thunderline.Thundervine.Domain, authorize?: false)
  end

  defp compute_rule_hash(run_id) do
    # Simple hash of run_id for now
    # In production, this would be the actual CA ruleset hash
    :crypto.hash(:sha256, run_id)
    |> Base.encode16(case: :lower)
    |> String.slice(0..15)
  end
end
