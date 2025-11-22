defmodule Thunderline.Thundercrown.Jobs.ScheduledWorkflowProcessor do
  @moduledoc """
  Scheduled workflow processor
  Handles delayed execution of orchestrated workflows
  """

  use Oban.Worker,
    queue: :scheduled_workflows,
    max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = _job) do
    Logger.info("Processing scheduled workflow: #{inspect(args)}")

    case args do
      %{"workflow_id" => workflow_id, "config" => config} ->
        execute_scheduled_workflow(workflow_id, config)

      _ ->
        {:error, "Invalid job args: missing workflow_id or config"}
    end
  end

  defp execute_scheduled_workflow(workflow_id, config) do
    Logger.info("Executing scheduled workflow: #{workflow_id}")

    # Determine workflow type and execute accordingly
    case Map.get(config, "workflow_type") do
      "cross_domain_sync" ->
        trigger_cross_domain_sync(workflow_id, config)

      "health_check" ->
        trigger_health_check(workflow_id, config)

      "maintenance" ->
        trigger_maintenance_workflow(workflow_id, config)

      "backup" ->
        trigger_backup_workflow(workflow_id, config)

      _ ->
        Logger.warning("Unknown scheduled workflow type: #{inspect(config)}")
        {:error, "Unknown workflow type"}
    end
  end

  defp trigger_cross_domain_sync(workflow_id, config) do
    domains = Map.get(config, "domains", [:thunderbit, :thunderflow, :thunderlink])

    Enum.each(domains, fn domain ->
      Thunderline.Thunderblock.Jobs.DomainSyncProcessor.new(%{
        "workflow_id" => workflow_id,
        "domain" => domain,
        "sync_type" => Map.get(config, "sync_type", "full_sync")
      })
      |> Oban.insert()
    end)

    :ok
  end

  defp trigger_health_check(workflow_id, config) do
    # Trigger health checks across domains
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "scheduled_health_checks",
      {:health_check_requested,
       %{
         workflow_id: workflow_id,
         scope: Map.get(config, "scope", "all_domains"),
         timestamp: DateTime.utc_now()
       }}
    )

    :ok
  end

  defp trigger_maintenance_workflow(workflow_id, config) do
    # Trigger maintenance operations
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "scheduled_maintenance",
      {:maintenance_requested,
       %{
         workflow_id: workflow_id,
         operations: Map.get(config, "operations", []),
         timestamp: DateTime.utc_now()
       }}
    )

    :ok
  end

  defp trigger_backup_workflow(workflow_id, config) do
    # Trigger backup operations
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "scheduled_backups",
      {:backup_requested,
       %{
         workflow_id: workflow_id,
         backup_type: Map.get(config, "backup_type", "incremental"),
         timestamp: DateTime.utc_now()
       }}
    )

    :ok
  end
end
