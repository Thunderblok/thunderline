defmodule Thunderline.Thunderblock.Resources.ExecutionTenant do
  @moduledoc """
  ExecutionTenant (formerly Thunderblock.Resources.Community) for execution zone management.

  This infrastructure-level resource handles execution zone provisioning,
  resource allocation and lifecycle orchestration. User-facing community
  semantics now live in Thunderline.Thunderlink.Resources.Community.

  NOTE: Old name kept temporarily via deprecated alias at bottom. Update any
  references to the new module before Q4 2025.
  """

  use Ash.Resource,
  domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  require Logger
  require Ash.Query

  postgres do
    table "thunderblock_communities"
    repo Thunderline.Repo
  end

  code_interface do
    define :create, args: [:community_id, :initial_resources]
    define :update, args: [:execution_zone_id, :resource_allocation, :status]
    define :activate
    define :suspend
    define :destroy
  end

  actions do
    defaults [:read]

    create :create do
      description "Create a new Thunderblock community"

      argument :community_id, :uuid, allow_nil?: false
      argument :initial_resources, :map, default: %{}

      change set_attribute(:community_id, arg(:community_id))
      change set_attribute(:resource_allocation, arg(:initial_resources))
      change set_attribute(:status, :provisioning)

      change after_action(&provision_execution_zone/2)
    end

    update :update do
      require_atomic? false
      description "Update community configuration"

      argument :execution_zone_id, :uuid
      argument :resource_allocation, :map
      argument :status, :atom

      change set_attribute(:execution_zone_id, arg(:execution_zone_id))
      change set_attribute(:resource_allocation, arg(:resource_allocation))
      change set_attribute(:status, arg(:status))
      change set_attribute(:updated_at, &DateTime.utc_now/0)

      change after_action(&update_zone_configuration/2)
    end

    update :activate do
      require_atomic? false
      description "Activate community execution zone"

      change set_attribute(:status, :active)
      change set_attribute(:updated_at, &DateTime.utc_now/0)

      change after_action(&start_execution_services/2)
    end

    update :suspend do
      require_atomic? false
      description "Suspend community execution zone"

      change set_attribute(:status, :suspended)
      change set_attribute(:updated_at, &DateTime.utc_now/0)

      change after_action(&suspend_execution_services/2)
    end

    destroy :destroy do
      require_atomic? false
      description "Destroy community and cleanup resources"

      change before_action(&cleanup_execution_zone/2)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :community_id, :uuid do
      description "Reference to the main community"
      allow_nil? false
    end

    attribute :execution_zone_id, :uuid do
      description "Associated execution zone"
      allow_nil? true
    end

    attribute :resource_allocation, :map do
      description "Resource allocation configuration"
      default %{}
    end

    attribute :performance_metrics, :map do
      description "Performance metrics for the community execution zone"
      default %{}
    end

    attribute :status, :atom do
      description "Community execution status"
      constraints one_of: [:active, :inactive, :suspended, :provisioning, :error]
      default :provisioning
    end

    attribute :created_at, :utc_datetime_usec do
      description "Creation timestamp"
      default &DateTime.utc_now/0
      allow_nil? false
    end

    attribute :updated_at, :utc_datetime_usec do
      description "Last update timestamp"
      default &DateTime.utc_now/0
      allow_nil? false
    end
  end

  # Change implementations

  defp provision_execution_zone(_changeset, community) do
    Logger.info("Provisioning execution zone for community #{community.community_id}")

    try do
      # Create execution zone
      _zone_config = %{
        community_id: community.community_id,
        resource_requirements: community.resource_allocation,
        zone_type: :community_execution
      }

      # This would integrate with actual zone provisioning
      zone_id = generate_zone_id()

      # Update community with zone information
      updated_community =
        community
        |> Ash.Changeset.for_update(:update, %{
          execution_zone_id: zone_id,
          status: :active
        })
        |> Ash.update!()

      Logger.info("Execution zone #{zone_id} provisioned for community #{community.community_id}")

      {:ok, updated_community}
    rescue
      error ->
        Logger.error(
          "Failed to provision execution zone for community #{community.community_id}: #{inspect(error)}"
        )

        # Update status to error
        error_community =
          community
          |> Ash.Changeset.for_update(:update, %{status: :error})
          |> Ash.update!()

        {:ok, error_community}
    end
  end

  defp update_zone_configuration(_changeset, community) do
    if community.execution_zone_id do
      Logger.info("Updating zone configuration for community #{community.community_id}")

      # Update zone configuration
      update_zone_resources(community.execution_zone_id, community.resource_allocation)
    end

    {:ok, community}
  end

  defp start_execution_services(_changeset, community) do
    Logger.info("Starting execution services for community #{community.community_id}")

    if community.execution_zone_id do
      # Start zone services
      start_zone_services(community.execution_zone_id)
    end

    {:ok, community}
  end

  defp suspend_execution_services(_changeset, community) do
    Logger.info("Suspending execution services for community #{community.community_id}")

    if community.execution_zone_id do
      # Suspend zone services
      suspend_zone_services(community.execution_zone_id)
    end

    {:ok, community}
  end

  defp cleanup_execution_zone(changeset, community) do
    Logger.info("Cleaning up execution zone for community #{community.community_id}")

    if community.execution_zone_id do
      # Cleanup zone resources
      cleanup_zone_resources(community.execution_zone_id)
    end

    {:ok, changeset}
  end

  # Helper functions

  defp generate_zone_id do
    "zone_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp update_zone_resources(zone_id, resource_allocation) do
    Logger.debug("Updating resources for zone #{zone_id}: #{inspect(resource_allocation)}")

    # This would interface with actual zone management system
    :ok
  end

  defp start_zone_services(zone_id) do
    Logger.debug("Starting services for zone #{zone_id}")

    # This would start actual zone services
    :ok
  end

  defp suspend_zone_services(zone_id) do
    Logger.debug("Suspending services for zone #{zone_id}")

    # This would suspend actual zone services
    :ok
  end

  defp cleanup_zone_resources(zone_id) do
    Logger.debug("Cleaning up resources for zone #{zone_id}")

    # This would cleanup actual zone resources
    :ok
  end

  # Query helpers

  @doc """
  Find community by community_id.
  """
  def by_community_id(community_id) do
    __MODULE__
    |> Ash.Query.filter(community_id == ^community_id)
    |> Ash.read_one!()
  end

  @doc """
  Find communities by status.
  """
  def by_status(status) do
    __MODULE__
    |> Ash.Query.filter(status == ^status)
    |> Ash.read!()
  end

  @doc """
  Get performance metrics for a community.
  """
  def get_performance_metrics(community_id) do
    case by_community_id(community_id) do
      %{performance_metrics: metrics} when metrics != %{} ->
        {:ok, metrics}

      %{} ->
        {:ok, %{}}

      nil ->
        {:error, :community_not_found}
    end
  end

  @doc """
  Update performance metrics for a community.
  """
  def update_performance_metrics(community_id, new_metrics) do
    case by_community_id(community_id) do
      %{} = community ->
        current_metrics = community.performance_metrics || %{}
        updated_metrics = Map.merge(current_metrics, new_metrics)

        community
        |> Ash.Changeset.for_update(:update, %{
          performance_metrics: updated_metrics
        })
        |> Ash.update()

      nil ->
        {:error, :community_not_found}
    end
  end
end

# Temporary deprecated alias for backward compatibility; remove after refactors complete.
defmodule Thunderblock.Resources.Community do
  @deprecated "Renamed to Thunderline.Thunderblock.Resources.ExecutionTenant"
  @moduledoc false
  @deprecated "Renamed"
  defdelegate by_community_id(id), to: Thunderline.Thunderblock.Resources.ExecutionTenant
  @deprecated "Renamed"
  defdelegate by_status(status), to: Thunderline.Thunderblock.Resources.ExecutionTenant
  @deprecated "Renamed"
  defdelegate get_performance_metrics(id), to: Thunderline.Thunderblock.Resources.ExecutionTenant
  @deprecated "Renamed"
  defdelegate update_performance_metrics(id, metrics), to: Thunderline.Thunderblock.Resources.ExecutionTenant
end
