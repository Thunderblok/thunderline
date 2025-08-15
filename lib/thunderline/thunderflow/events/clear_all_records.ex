defmodule Thunderline.Thunderflow.Events.ClearAllRecords do
  @moduledoc """
  Implementation for clearing all records before event replay.

  This module is responsible for clearing all relevant records across
  all Thunderline domains when performing event replay to rebuild
  the complete system state from the event log.
  """

  use AshEvents.ClearRecordsForReplay

  @impl true
  def clear_records!(opts) do
    # Define the order of clearing to respect dependencies
    # Start with dependent resources first, then core resources

    clear_order = [
      # Monitoring and derived state (no dependencies) - now in ThunderFlow
      {Thunderline.Thunderflow, [
        :audit_log, :error_log, :system_metric, :performance_trace,
        :health_check, :alert_rule, :system_action,
        :thunderbit_monitor, :thunderbolt_monitor
      ]},

      # Communication (now in ThunderLink)
      {Thunderline.Thunderlink, [
        :message, :channel, :community, :role,
        :federation_socket, :pac_home
      ]},

      # Task management (now in ThunderBolt)
      {Thunderline.Thunderbolt, [
        :task_execution, :task_assignment, :macro_command
      ]},

      # Spatial computing (now in ThunderBolt)
      {Thunderline.Thunderbolt, [
        :zone_event, :chunk_state, :zone_boundary,
        :spatial_coordinate, :grid_resource, :grid_zone, :zone
      ]},

      # Resource management (ThunderBolt)
      {Thunderline.Thunderbolt, [
        :orchestration_event, :resource_allocation,
        :chunk_health, :activation_rule, :chunk
      ]},

      # Storage & persistence (ThunderBlock)
      {Thunderline.Thunderblock, [
        :system_event, :task_orchestrator, :zone_container,
        :rate_limit_policy, :load_balancing_rule, :supervision_tree,
        :execution_container, :distributed_state, :cluster_node
      ]},

      # External integration (ThunderGate)
      {Thunderline.Thundergate, [
        :federated_message, :realm_identity, :federated_realm,
        :external_service, :data_adapter
      ]},

      # Event processing (ThunderFlow)
      {Thunderline.Thunderflow, [
        :consciousness_flow, :event_stream
      ]},

      # Policy and governance (ThunderGate)
      {Thunderline.Thundergate, [
        :policy_rule, :decision_framework
      ]},

      # Orchestration (ThunderCrown)
      {Thunderline.Thundercrown, [
        :workflow_orchestrator, :mcp_bus, :ai_policy
      ]},

      # Core system management (ThunderBolt)
      {Thunderline.Thunderbolt, [
        :timing_event, :workflow_dag, :task_node,
        :system_policy, :agent
      ]},

      # AI behavior system (ThunderBolt)
      {Thunderline.Thunderbolt, [
        :execution_context, :swarm_configuration,
        :condition_node, :composite_node, :behavior_node,
        :action_node, :agent, :thunderbit
      ]},

      # Memory and knowledge (ThunderBlock)
      {Thunderline.Thunderblock, [
        :query_optimization, :cache_entry, :embedding_vector,
        :memory_record, :memory_node, :knowledge_node,
        :experience, :decision, :action, :user_token,
        :agent, :user
      ]}
    ]

    # Clear records in the specified order
    Enum.each(clear_order, fn {domain_module, resources} ->
      clear_domain_resources(domain_module, resources, opts)
    end)

    :ok
  end

  defp clear_domain_resources(domain_module, resource_names, opts) do
    Enum.each(resource_names, fn resource_name ->
      try do
        resource_module = Module.concat(domain_module, resource_name_to_module(resource_name))

        # Check if the resource module exists and has the required functions
        if Code.ensure_loaded?(resource_module) and function_exported?(resource_module, :destroy, 2) do
          clear_resource_records(resource_module, opts)
        else
          # Log that resource doesn't exist yet - this is expected during development
          IO.puts("Skipping #{inspect(resource_module)} - not yet implemented")
        end
      rescue
        error ->
          # Log the error but continue with other resources
          IO.puts("Error clearing #{domain_module}.#{resource_name}: #{inspect(error)}")
      end
    end)
  end

  defp clear_resource_records(resource_module, _opts) do
    try do
      # Get all records and destroy them
      resource_module
      |> Ash.Query.new()
      |> Ash.read!()
      |> Enum.each(fn record ->
        Ash.destroy!(record)
      end)

      IO.puts("Cleared all records from #{inspect(resource_module)}")
    rescue
      error ->
        IO.puts("Error clearing records from #{inspect(resource_module)}: #{inspect(error)}")
    end
  end

  defp resource_name_to_module(resource_name) when is_atom(resource_name) do
    resource_name
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
