defmodule ThunderlineWeb.ServiceRegistryJSON do
  @moduledoc """
  JSON rendering for service registry endpoints.
  """

  def service(%{service: service}) do
    %{
      id: service.id,
      service_id: service.service_id,
      service_type: service.service_type,
      name: service.name,
      host: service.host,
      port: service.port,
      url: service.url,
      status: service.status,
      capabilities: service.capabilities,
      metadata: service.metadata,
      last_heartbeat_at: service.last_heartbeat_at,
      registered_at: service.registered_at,
      updated_at: service.updated_at
    }
  end

  def services(%{services: services}) do
    %{services: Enum.map(services, &service(%{service: &1}))}
  end

  def error(%{error: error}) when is_binary(error) do
    %{error: error}
  end

  def error(%{error: %Ash.Error.Invalid{} = error}) do
    %{
      error: "Validation failed",
      details: error.errors |> Enum.map(&error_detail/1)
    }
  end

  def error(%{error: error}) do
    %{error: Exception.message(error)}
  end

  defp error_detail(%{message: message, field: field}) when not is_nil(field) do
    %{field: field, message: message}
  end

  defp error_detail(%{message: message}) do
    %{message: message}
  end

  defp error_detail(error) do
    %{message: inspect(error)}
  end

  def ok(%{message: message}) do
    %{ok: true, message: message}
  end
end
