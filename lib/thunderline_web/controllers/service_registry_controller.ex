defmodule ThunderlineWeb.ServiceRegistryController do
  @moduledoc """
  REST API for service registration and discovery.

  Endpoints:
  - POST /api/registry/register - Register a new service
  - PATCH /api/registry/:service_id/heartbeat - Send heartbeat
  - GET /api/registry/services - List all services
  - GET /api/registry/services/:service_id - Get specific service
  - GET /api/registry/services/type/:type - List services by type
  - GET /api/registry/services/healthy - List healthy services
  - DELETE /api/registry/:service_id - Deregister service
  """
  use ThunderlineWeb, :controller
  alias Thunderline.ServiceRegistry.Service
  require Logger

  action_fallback ThunderlineWeb.FallbackController

  @doc """
  Register a new service.

  POST /api/registry/register

  Body:
  {
    "service_id": "cerebros-1",
    "service_type": "cerebros",
    "name": "Cerebros Training Service #1",
    "host": "localhost",
    "port": 8000,
    "capabilities": {
      "gpu_available": true,
      "max_concurrent_jobs": 2
    },
    "metadata": {
      "version": "1.0.0"
    }
  }
  """
  def register(conn, params) do
    Logger.info("Service registration request: #{inspect(params)}")

    with {:ok, service} <-
           Service.register(%{
             service_id: params["service_id"],
             service_type: String.to_existing_atom(params["service_type"]),
             name: params["name"],
             host: params["host"] || "localhost",
             port: params["port"],
             capabilities: params["capabilities"] || %{},
             metadata: params["metadata"] || %{}
           }) do
      Logger.info("Service registered: #{service.service_id} (#{service.name}) at #{service.url}")

      conn
      |> put_status(:created)
      |> render(:service, service: service)
    end
  end

  @doc """
  Send heartbeat for a service.

  PATCH /api/registry/:service_id/heartbeat

  Body:
  {
    "status": "healthy",
    "capabilities": {...},
    "metadata": {...}
  }
  """
  def heartbeat(conn, %{"service_id" => service_id} = params) do
    Logger.debug("Heartbeat from service: #{service_id}")

    with {:ok, service} <- Service.find_by_service_id(service_id),
         {:ok, updated_service} <-
           Service.heartbeat(service, %{
             status: parse_status(params["status"]),
             capabilities: params["capabilities"] || service.capabilities,
             metadata: params["metadata"] || service.metadata
           }) do
      render(conn, :service, service: updated_service)
    end
  end

  @doc """
  List all services.

  GET /api/registry/services
  """
  def list(conn, _params) do
    services = Service.list!()
    render(conn, :services, services: services)
  end

  @doc """
  Get a specific service.

  GET /api/registry/services/:service_id
  """
  def show(conn, %{"service_id" => service_id}) do
    with {:ok, service} <- Service.find_by_service_id(service_id) do
      render(conn, :service, service: service)
    end
  end

  @doc """
  List services by type.

  GET /api/registry/services/type/:type
  """
  def list_by_type(conn, %{"type" => type}) do
    service_type = String.to_existing_atom(type)
    services = Service.list_by_type!(service_type)
    render(conn, :services, services: services)
  end

  @doc """
  List healthy services.

  GET /api/registry/services/healthy
  """
  def list_healthy(conn, _params) do
    services = Service.list_healthy!()
    render(conn, :services, services: services)
  end

  @doc """
  Deregister a service.

  DELETE /api/registry/:service_id
  """
  def deregister(conn, %{"service_id" => service_id}) do
    Logger.info("Deregistering service: #{service_id}")

    with {:ok, service} <- Service.find_by_service_id(service_id),
         :ok <- Service.destroy(service) do
      Logger.info("Service deregistered: #{service_id}")
      render(conn, :ok, message: "Service deregistered successfully")
    end
  end

  defp parse_status(nil), do: nil
  defp parse_status(status) when is_atom(status), do: status
  defp parse_status(status) when is_binary(status), do: String.to_existing_atom(status)
end
