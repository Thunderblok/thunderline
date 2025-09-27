defmodule ThunderlineWeb.HealthController do
  @moduledoc """
  HealthController - System health check endpoint

  Provides health status for:
  - System components
  - Database connectivity
  - External dependencies
  - Service availability
  """

  use ThunderlineWeb, :controller

  alias Thunderline.DashboardMetrics

  @doc """
  Basic health check endpoint
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
end
