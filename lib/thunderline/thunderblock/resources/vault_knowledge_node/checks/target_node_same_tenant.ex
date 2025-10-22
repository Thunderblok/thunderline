defmodule Thunderline.Thunderblock.Resources.VaultKnowledgeNode.Checks.TargetNodeSameTenant do
  @moduledoc """
  Policy check to ensure the target node in a relationship is in the same tenant.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts) do
    "target node must be in the same tenant"
  end

  @impl true
  def match?(_actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    target_node_id = Ash.Changeset.get_argument(changeset, :target_node_id)
    current_tenant_id = Ash.Changeset.get_attribute(changeset, :tenant_id)

    if is_nil(target_node_id) or is_nil(current_tenant_id) do
      false
    else
      # Fetch target node without authorization to check its tenant
      # We need to pass the tenant context since the resource is tenant-scoped
      case Ash.get(Thunderline.Thunderblock.Resources.VaultKnowledgeNode, target_node_id,
             authorize?: false,
             tenant: current_tenant_id
           ) do
        {:ok, target_node} ->
          target_node.tenant_id == current_tenant_id

        {:error, _} ->
          false
      end
    end
  end

  def match?(_actor, _context, _opts), do: false
end
