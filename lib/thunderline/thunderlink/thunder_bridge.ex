defmodule Thunderline.ThunderBridge do
  @moduledoc """
  DEPRECATED – Use `Thundergate.ThunderBridge` instead.

  This module is a thin shim that delegates to the authoritative bridge in
  the Gate domain. All calls emit a deprecation telemetry counter to track
  migration progress. This shim should be removed after callers migrate.

  ## Migration Guide

  Replace calls from:
      Thunderline.ThunderBridge.get_system_state()

  To:
      Thundergate.ThunderBridge.get_system_state()

  All methods have identical signatures and return values.
  """

  require Logger

  @deprecated "Use Thundergate.ThunderBridge instead"

  # Core GenServer lifecycle
  def start_link(opts \\ []),
    do: tap_deprecated(:start_link, fn -> Thundergate.ThunderBridge.start_link(opts) end)

  # System state & metrics
  def get_system_state,
    do: tap_deprecated(:get_system_state, fn -> Thundergate.ThunderBridge.get_system_state() end)

  def get_system_metrics,
    do:
      tap_deprecated(:get_system_metrics, fn -> Thundergate.ThunderBridge.get_system_metrics() end)

  # Dashboard API
  def get_thunderbolt_registry,
    do:
      tap_deprecated(:get_thunderbolt_registry, fn ->
        Thundergate.ThunderBridge.get_thunderbolt_registry()
      end)

  def get_thunderbit_observer,
    do:
      tap_deprecated(:get_thunderbit_observer, fn ->
        Thundergate.ThunderBridge.get_thunderbit_observer()
      end)

  def execute_command(command, params \\ []),
    do:
      tap_deprecated(:execute_command, fn ->
        Thundergate.ThunderBridge.execute_command(command, params)
      end)

  def subscribe_dashboard_events(subscriber_pid),
    do:
      tap_deprecated(:subscribe_dashboard_events, fn ->
        Thundergate.ThunderBridge.subscribe_dashboard_events(subscriber_pid)
      end)

  def get_performance_metrics,
    do:
      tap_deprecated(:get_performance_metrics, fn ->
        Thundergate.ThunderBridge.get_performance_metrics()
      end)

  def get_evolution_stats,
    do:
      tap_deprecated(:get_evolution_stats, fn ->
        Thundergate.ThunderBridge.get_evolution_stats()
      end)

  # CA Streaming
  def start_ca_streaming(opts \\ []),
    do:
      tap_deprecated(:start_ca_streaming, fn ->
        Thundergate.ThunderBridge.start_ca_streaming(opts)
      end)

  def stop_ca_streaming,
    do:
      tap_deprecated(:stop_ca_streaming, fn -> Thundergate.ThunderBridge.stop_ca_streaming() end)

  # Agent/Chunk CRUD
  def get_agent_state(agent_id),
    do:
      tap_deprecated(:get_agent_state, fn ->
        Thundergate.ThunderBridge.get_agent_state(agent_id)
      end)

  def spawn_agent(agent_data),
    do: tap_deprecated(:spawn_agent, fn -> Thundergate.ThunderBridge.spawn_agent(agent_data) end)

  def update_agent(agent_id, updates),
    do:
      tap_deprecated(:update_agent, fn ->
        Thundergate.ThunderBridge.update_agent(agent_id, updates)
      end)

  def list_agents(filters \\ %{}),
    do: tap_deprecated(:list_agents, fn -> Thundergate.ThunderBridge.list_agents(filters) end)

  def get_chunks(filters \\ %{}),
    do: tap_deprecated(:get_chunks, fn -> Thundergate.ThunderBridge.get_chunks(filters) end)

  def create_chunk(chunk_data),
    do:
      tap_deprecated(:create_chunk, fn -> Thundergate.ThunderBridge.create_chunk(chunk_data) end)

  # Subscription & Events
  def subscribe(pid \\ self()),
    do: tap_deprecated(:subscribe, fn -> Thundergate.ThunderBridge.subscribe(pid) end)

  def broadcast_event(topic, event),
    do:
      tap_deprecated(:broadcast_event, fn ->
        Thundergate.ThunderBridge.broadcast_event(topic, event)
      end)

  # Legacy JSON API
  def get_agents_json,
    do: tap_deprecated(:get_agents_json, fn -> Thundergate.ThunderBridge.get_agents_json() end)

  def get_chunks_json,
    do: tap_deprecated(:get_chunks_json, fn -> Thundergate.ThunderBridge.get_chunks_json() end)

  # Event publishing
  def publish(event),
    do: tap_deprecated(:publish, fn -> Thundergate.ThunderBridge.publish(event) end)

  # Private: emit deprecation telemetry and execute
  defp tap_deprecated(function_name, fun) do
    :telemetry.execute(
      [:thunderline, :deprecated_module, :used],
      %{count: 1},
      %{
        module: __MODULE__,
        function: function_name,
        target: Thundergate.ThunderBridge
      }
    )

    Logger.warning(
      "[DEPRECATED] #{__MODULE__}.#{function_name}/_ called; use Thundergate.ThunderBridge"
    )

    fun.()
  end
end
