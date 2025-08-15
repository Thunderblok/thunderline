defmodule Thunderline.Thunderbolt.ThunderCell.ClusterSupervisor do
  @moduledoc """
  Dynamic supervisor for managing multiple ThunderCell cluster instances.
  Each cluster operates independently with its own CA rules and configuration.
  """

  use DynamicSupervisor
  require Logger

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_cluster(cluster_config) do
    child_spec = {
      Thunderline.Thunderbolt.ThunderCell.Cluster,
      cluster_config
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started ThunderCell cluster: #{inspect(cluster_config.cluster_id)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.info("ThunderCell cluster already started: #{inspect(cluster_config.cluster_id)}")
        {:ok, pid}

      error ->
        Logger.error("Failed to start ThunderCell cluster: #{inspect(error)}")
        error
    end
  end

  def stop_cluster(cluster_id) do
    case Process.whereis(cluster_id) do
      nil ->
        Logger.warning("Cluster not found: #{inspect(cluster_id)}")
        {:error, :not_found}

      pid ->
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("Stopped ThunderCell cluster: #{inspect(cluster_id)}")
            :ok

          error ->
            Logger.error("Failed to stop ThunderCell cluster: #{inspect(error)}")
            error
        end
    end
  end

  def list_clusters do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      case GenServer.call(pid, :get_cluster_stats) do
        {:ok, stats} -> stats
        _ -> %{cluster_id: :unknown, pid: pid}
      end
    end)
  end

  def get_cluster_count do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  # ====================================================================
  # DynamicSupervisor callbacks
  # ====================================================================

  @impl true
  def init(_opts) do
    Logger.info("Starting ThunderCell ClusterSupervisor...")

    # Use :one_for_one strategy - if a cluster crashes, restart only that cluster
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end
end
