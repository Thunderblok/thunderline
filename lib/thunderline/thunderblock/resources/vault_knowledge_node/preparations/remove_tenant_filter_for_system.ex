defmodule Thunderline.Thunderblock.Resources.VaultKnowledgeNode.Preparations.RemoveTenantFilterForSystem do
  @moduledoc """
  Preparation that removes tenant filtering for system actors with maintenance scope.

  This allows system actors to access resources across all tenants for maintenance purposes,
  bypassing the normal tenant isolation enforced by the multitenancy strategy.
  """
  use Ash.Resource.Preparation

  @doc false
  def prepare(query, _opts, %{actor: %{role: :system, scope: :maintenance}}) do
    # For system actors with maintenance scope, remove tenant filtering
    # We do this by removing the tenant filter that was added automatically
    Ash.Query.unset(query, :tenant)
  end

  def prepare(query, _opts, _context) do
    # For all other actors, keep the default tenant filtering behavior
    query
  end
end
