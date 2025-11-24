defmodule Thunderline.Thundergate.ServiceRegistry do
  @moduledoc """
  Domain for managing service registration and discovery.

  This domain handles:
  - Service registration (services register themselves on startup)
  - Service discovery (find services by type or capabilities)
  - Health monitoring (periodic heartbeat checks)
  - Service coordination (route requests to healthy services)
  """
  use Ash.Domain

  resources do
    resource Thunderline.Thundergate.ServiceRegistry.Service
  end
end
