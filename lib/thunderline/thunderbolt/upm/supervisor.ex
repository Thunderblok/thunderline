defmodule Thunderline.Thunderbolt.UPM.Supervisor do
  @moduledoc """
  Supervision tree for Unified Persistent Model (UPM) components.

  Manages lifecycle of all UPM workers:
  - TrainerWorker (online training loop)
  - DriftMonitor (shadow comparison & quarantine)
  - AdapterSync (snapshot distribution to agents)

  Each trainer gets its own supervised worker tree with independent
  TrainerWorker, ReplayBuffer, and DriftMonitor processes.

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.Supervisor,
        enabled: false,
        default_trainers: [
          [name: "default", mode: :shadow, tenant_id: nil]
        ]

  ## Feature Flag

  UPM is gated by the `:unified_model` feature flag:

      config :thunderline, :features, %{unified_model: false}

  Set to `true` or enable per-tenant to activate UPM training.
  """

  use Supervisor
  require Logger

  alias Thunderline.Feature

  alias Thunderline.Thunderbolt.UPM.{
    TrainerWorker,
    DriftMonitor,
    AdapterSync,
    ObservationRecorder,
    PACTrainingBridge
  }

  @doc """
  Starts the UPM supervisor.

  Returns `{:ok, pid}` if feature flag enabled, otherwise `{:error, :disabled}`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, :disabled}
  def start_link(opts \\ []) do
    # Check feature flag
    if Feature.enabled?(:unified_model, default: false) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    else
      Logger.info("[UPM.Supervisor] UPM disabled (feature flag :unified_model not enabled)")
      :ignore
    end
  end

  @doc """
  Dynamically starts a new trainer under supervision.

  ## Parameters

  - `trainer_opts` - Keyword list with `:name`, `:mode`, `:tenant_id`, etc.

  ## Returns

  - `{:ok, pid}` - Trainer supervision tree started
  - `{:error, reason}` - Failed to start trainer
  """
  @spec start_trainer(keyword()) :: Supervisor.on_start_child()
  def start_trainer(trainer_opts) do
    trainer_id = Keyword.fetch!(trainer_opts, :trainer_id)

    spec = trainer_supervisor_spec(trainer_id, trainer_opts)

    case DynamicSupervisor.start_child(__MODULE__.TrainersSupervisor, spec) do
      {:ok, pid} ->
        Logger.info("[UPM.Supervisor] Started trainer supervision tree: #{trainer_id}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("[UPM.Supervisor] Failed to start trainer #{trainer_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops a running trainer and its supervised workers.
  """
  @spec stop_trainer(binary()) :: :ok | {:error, :not_found}
  def stop_trainer(trainer_id) do
    children = DynamicSupervisor.which_children(__MODULE__.TrainersSupervisor)

    case Enum.find(children, fn {id, _pid, _type, [module]} ->
           module == Supervisor and match?({__MODULE__.TrainerSupervisor, ^trainer_id}, id)
         end) do
      {_id, pid, _, _} ->
        DynamicSupervisor.terminate_child(__MODULE__.TrainersSupervisor, pid)
        Logger.info("[UPM.Supervisor] Stopped trainer: #{trainer_id}")
        :ok

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running trainers.
  """
  @spec list_trainers() :: [binary()]
  def list_trainers do
    __MODULE__.TrainersSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn
      {{__MODULE__.TrainerSupervisor, trainer_id}, _pid, _type, _modules} ->
        trainer_id

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @impl true
  def init(_opts) do
    Logger.info("[UPM.Supervisor] Initializing UPM supervision tree")

    children = [
      # DynamicSupervisor for managing multiple trainers
      {DynamicSupervisor,
       name: __MODULE__.TrainersSupervisor, strategy: :one_for_one, max_restarts: 10},

      # Global AdapterSync worker (handles all snapshot distribution)
      {AdapterSync, []},

      # ObservationRecorder (bridges LoopMonitor → UpmObservation)
      {ObservationRecorder, []},

      # PACTrainingBridge (connects PAC lifecycle → UPM training)
      {PACTrainingBridge, []}
    ]

    # Start supervision tree
    result = Supervisor.init(children, strategy: :one_for_one)

    # Start default trainers from config
    Task.start(fn ->
      Process.sleep(1000)
      start_default_trainers()
    end)

    result
  end

  # Private Helpers

  defp start_default_trainers do
    default_trainers =
      Application.get_env(
        :thunderline,
        [__MODULE__, :default_trainers],
        [[name: "default", mode: :shadow, tenant_id: nil]]
      )

    Enum.each(default_trainers, fn trainer_config ->
      # Ensure trainer resource exists
      case ensure_trainer_resource(trainer_config) do
        {:ok, trainer} ->
          opts = Keyword.put(trainer_config, :trainer_id, trainer.id)
          start_trainer(opts)

        {:error, reason} ->
          Logger.error("""
          [UPM.Supervisor] Failed to create default trainer
            config: #{inspect(trainer_config)}
            error: #{inspect(reason)}
          """)
      end
    end)
  end

  defp ensure_trainer_resource(config) do
    name = Keyword.fetch!(config, :name)
    mode = Keyword.get(config, :mode, :shadow)
    tenant_id = Keyword.get(config, :tenant_id)

    alias Thunderline.Thunderbolt.Resources.UpmTrainer
    require Ash.Query

    query = UpmTrainer |> Ash.Query.filter(name == ^name and tenant_id == ^tenant_id)

    case Ash.read(query) do
      {:ok, [trainer]} ->
        {:ok, trainer}

      {:ok, []} ->
        # Create new trainer
        %{name: name, mode: mode, tenant_id: tenant_id, metadata: %{auto_created: true}}
        |> UpmTrainer.register()
        |> Ash.create()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp trainer_supervisor_spec(trainer_id, trainer_opts) do
    %{
      id: {__MODULE__.TrainerSupervisor, trainer_id},
      start:
        {Supervisor, :start_link,
         [trainer_children(trainer_id, trainer_opts), [strategy: :one_for_one]]},
      type: :supervisor,
      restart: :transient
    }
  end

  defp trainer_children(trainer_id, trainer_opts) do
    [
      # TrainerWorker (includes ReplayBuffer internally)
      {TrainerWorker, Keyword.put(trainer_opts, :trainer_id, trainer_id)},

      # DriftMonitor (shadow comparison & quarantine)
      {DriftMonitor, [trainer_id: trainer_id] ++ drift_monitor_opts(trainer_opts)}
    ]
  end

  defp drift_monitor_opts(trainer_opts) do
    [
      window_duration_ms: Keyword.get(trainer_opts, :drift_window_duration_ms, 3_600_000),
      drift_threshold: Keyword.get(trainer_opts, :drift_threshold, 0.2),
      sample_size: Keyword.get(trainer_opts, :drift_sample_size, 1000),
      quarantine_enabled: Keyword.get(trainer_opts, :quarantine_enabled, true)
    ]
  end
end
