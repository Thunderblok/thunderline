defmodule Thunderline.Thunderbolt.Training.Supervisor do
  @moduledoc """
  Supervisor for ML Training Pipeline components.

  ## Architecture

  ```
  Training.Supervisor
       │
       ├── TrajectoryLogger (GenServer)
       │      └── ETS-backed trajectory storage
       │
       ├── TPEClient (GenServer)
       │      └── Python Port to Optuna TPE
       │
       └── [Future: TrainingOrchestrator]
              └── Coordinates training runs
  ```

  ## Supervision Strategy

  Uses `:one_for_one` - each child is independent:
  - TrajectoryLogger failure doesn't affect TPEClient
  - TPEClient failure doesn't lose collected trajectories

  ## Usage

      # Start supervisor (typically done via application supervision tree)
      {:ok, sup} = Training.Supervisor.start_link([])

      # Check status
      Training.Supervisor.status()

      # Get child PIDs
      Training.Supervisor.child_pids()

  ## Configuration

  Set via application config or supervisor opts:

      config :thunderline, Thunderline.Thunderbolt.Training.Supervisor,
        trajectory_logger: [
          backend: :ets,
          export_path: "priv/training_data/trajectories",
          max_steps: 100_000
        ],
        tpe_client: [
          python_path: "python3.13"
        ],
        enable_tpe: true
  """

  use Supervisor
  require Logger

  @doc """
  Starts the training supervisor.

  ## Options

  - `:name` - Supervisor name (default: __MODULE__)
  - `:trajectory_logger` - Options for TrajectoryLogger
  - `:tpe_client` - Options for TPEClient
  - `:enable_tpe` - Whether to start TPEClient (default: true)
  """
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the status of all training components.
  """
  @spec status() :: map()
  def status do
    children = Supervisor.which_children(__MODULE__)

    %{
      supervisor: __MODULE__,
      children:
        Enum.map(children, fn {id, pid, type, _modules} ->
          %{
            id: id,
            pid: pid,
            type: type,
            alive?: is_pid(pid) and Process.alive?(pid)
          }
        end),
      trajectory_stats: get_trajectory_stats(),
      tpe_studies: get_tpe_studies()
    }
  end

  @doc """
  Returns a map of child IDs to PIDs.
  """
  @spec child_pids() :: map()
  def child_pids do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.map(fn {id, pid, _type, _modules} -> {id, pid} end)
    |> Map.new()
  end

  @doc """
  Restarts a specific child by ID.
  """
  @spec restart_child(atom()) :: :ok | {:error, term()}
  def restart_child(child_id) do
    case Supervisor.terminate_child(__MODULE__, child_id) do
      :ok ->
        case Supervisor.restart_child(__MODULE__, child_id) do
          {:ok, _pid} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  # ===========================================================================
  # Supervisor Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    # Merge with application config
    app_config = Application.get_env(:thunderline, __MODULE__, [])
    opts = Keyword.merge(app_config, opts)

    # Build child specs
    children = build_children(opts)

    Logger.info("[Training.Supervisor] Starting with #{length(children)} children")

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_children(opts) do
    trajectory_opts = opts[:trajectory_logger] || []
    tpe_opts = opts[:tpe_client] || []
    enable_tpe = Keyword.get(opts, :enable_tpe, true)

    children = [
      # TrajectoryLogger - always start
      {Thunderline.Thunderbolt.Training.TrajectoryLogger, trajectory_opts}
    ]

    # TPEClient - optional based on config
    children =
      if enable_tpe do
        children ++ [{Thunderline.Thunderbolt.Training.TPEClient, tpe_opts}]
      else
        Logger.info("[Training.Supervisor] TPEClient disabled by config")
        children
      end

    children
  end

  defp get_trajectory_stats do
    try do
      Thunderline.Thunderbolt.Training.TrajectoryLogger.stats()
    rescue
      _ -> %{error: "not_running"}
    catch
      :exit, _ -> %{error: "not_running"}
    end
  end

  defp get_tpe_studies do
    try do
      case Thunderline.Thunderbolt.Training.TPEClient.list_studies() do
        {:ok, result} -> result
        {:error, reason} -> %{error: reason}
      end
    rescue
      _ -> %{error: "not_running"}
    catch
      :exit, _ -> %{error: "not_running"}
    end
  end
end
