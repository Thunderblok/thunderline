defmodule ThunderlineWeb.HealthController do
  @moduledoc """
  HealthController - System health check endpoints for container orchestration.

  Provides Kubernetes-style health probes:
  - `/health` (alias `/healthz`) - Liveness probe: Is the process alive?
  - `/ready` (alias `/readyz`) - Readiness probe: Can the service handle traffic?

  Liveness checks are lightweight (process alive, basic VM).
  Readiness checks include database, mnesia, broadway, pubsub connectivity.
  """

  use ThunderlineWeb, :controller

  @doc """
  Liveness probe - lightweight check that the VM is responsive.
  Returns 200 if the process can respond, 503 otherwise.
  Used by orchestrators to determine if the container should be restarted.
  """
  def liveness(conn, _params) do
    # Liveness is intentionally minimal - just confirm the VM is responsive
    conn
    |> put_status(200)
    |> json(%{
      status: :alive,
      timestamp: DateTime.utc_now(),
      node: Node.self(),
      version: app_version()
    })
  end

  @doc """
  Readiness probe - comprehensive check that the service can handle traffic.
  Returns 200 if all dependencies are healthy, 503 otherwise.
  Used by orchestrators to determine if traffic should be routed to this instance.
  """
  def readiness(conn, _params) do
    health_status = perform_health_check()
    status_code = if health_status.status == :healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  @doc """
  Full health check endpoint (backward compatible with existing /health).
  Equivalent to readiness probe with additional metadata.
  """
  def check(conn, _params) do
    health_status = perform_health_check()
    status_code = if health_status.status == :healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  ## Private Functions

  defp perform_health_check do
    checks = [
      {:database, check_database()},
      {:mnesia, check_mnesia()},
      {:broadway, check_broadway()},
      {:pubsub, check_pubsub()},
      {:memory, check_memory()}
    ]

    failed_checks = Enum.filter(checks, fn {_name, status} -> status != :ok end)

    overall_status = if length(failed_checks) == 0, do: :healthy, else: :unhealthy

    %{
      status: overall_status,
      timestamp: DateTime.utc_now(),
      checks: Map.new(checks),
      failed_count: length(failed_checks),
      version: Application.spec(:thunderline, :vsn) |> to_string(),
      node: Node.self()
    }
  end

  defp check_database do
    try do
      # Simple database connectivity check
      case Thunderline.Thunderblock.Health.ping() do
        :ok -> :ok
        {:error, _} -> :error
      end
    rescue
      _ -> :error
    end
  end

  defp check_mnesia do
    try do
      case :mnesia.system_info(:is_running) do
        :yes -> :ok
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end

  defp check_broadway do
    # Check if Broadway producers are running
    try do
      broadway_processes = Process.whereis(Thunderflow.EventPipeline)
      if broadway_processes, do: :ok, else: :error
    rescue
      _ -> :error
    end
  end

  defp check_pubsub do
    try do
      case Process.whereis(Thunderline.PubSub) do
        nil -> :error
        _pid -> :ok
      end
    rescue
      _ -> :error
    end
  end

  defp check_memory do
    try do
      memory_info = :erlang.memory()
      total_memory = memory_info[:total]

      # Flag as unhealthy if memory usage is very high (> 1GB for example)
      if total_memory > 1_073_741_824 do
        :warning
      else
        :ok
      end
    rescue
      _ -> :error
    end
  end

  defp app_version do
    Application.spec(:thunderline, :vsn) |> to_string()
  end
end
