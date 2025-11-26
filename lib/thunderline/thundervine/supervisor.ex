defmodule Thunderline.Thundervine.Supervisor do
  @moduledoc """
  Thundervine domain supervisor with tick-based activation.

  VINE is the DAG persistence layer - TAK event recording, workflow DAGs, pattern analysis.
  Activates on tick 5 after core orchestration (Bolt) is stable.
  """

  use Supervisor
  @behaviour Thunderline.Thunderblock.DomainActivation

  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    |> tap(fn
      {:ok, _pid} ->
        Thunderline.Thunderblock.DomainActivation.Helpers.maybe_activate(__MODULE__)

      {:error, reason} ->
        Logger.error("[Thunderline.Thundervine.Supervisor] Failed to start: #{inspect(reason)}")
    end)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      # Registry for TAKEventRecorder instances
      {Registry, keys: :unique, name: Thunderline.Thundervine.Registry},

      # DynamicSupervisor for TAK event recorders
      {DynamicSupervisor, name: Thunderline.Thundervine.EventRecorderSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # DomainActivation callbacks

  @impl Thunderline.Thunderblock.DomainActivation
  def domain_name, do: "thundervine"

  @impl Thunderline.Thunderblock.DomainActivation
  def activation_tick, do: 5

  @impl Thunderline.Thunderblock.DomainActivation
  def on_activated(tick_count) do
    Logger.info("[Thundervine] 🧬 VINE GROWING - DAG persistence & TAK recording ONLINE at tick #{tick_count}")

    state = %{
      activated_at: tick_count,
      started_at: DateTime.utc_now(),
      registry_ready: true,
      recorder_supervisor_ready: true,
      active_recorders: 0,
      tick_count: tick_count
    }

    # Emit custom telemetry
    :telemetry.execute(
      [:thunderline, :thundervine, :activated],
      %{tick: tick_count},
      %{domain: "thundervine", services: ["tak_recorder", "dag_persistence"]}
    )

    {:ok, state}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_tick(tick_count, state) do
    # Health check every 35 ticks (35 seconds) - check for stale recorders
    if rem(tick_count, 35) == 0 do
      active_count = length(list_recorders())
      Logger.debug("[Thundervine] 🧬 DAG pulse at tick #{tick_count} - #{active_count} active recorders")
    end

    {:noreply, %{state | tick_count: tick_count}}
  end

  @impl Thunderline.Thunderblock.DomainActivation
  def on_deactivated(reason, state) do
    uptime_ticks = state.tick_count - state.activated_at
    Logger.info(
      "[Thundervine] 🧬 Vine retracting after #{uptime_ticks} ticks, reason: #{inspect(reason)}"
    )

    :ok
  end

  # Public API (preserved from original)

  @doc """
  Start a TAKEventRecorder for a specific TAK run.

  ## Examples

      {:ok, pid} = Thunderline.Thundervine.Supervisor.start_recorder(run_id: "my_run")
  """
  def start_recorder(opts) do
    spec = {Thunderline.Thundervine.TAKEventRecorder, opts}
    DynamicSupervisor.start_child(Thunderline.Thundervine.EventRecorderSupervisor, spec)
  end

  @doc """
  Stop a TAKEventRecorder for a specific run.
  """
  def stop_recorder(run_id) do
    case Registry.lookup(Thunderline.Thundervine.Registry, {Thunderline.Thundervine.TAKEventRecorder, run_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Thunderline.Thundervine.EventRecorderSupervisor, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  List all active TAK event recorders.
  """
  def list_recorders do
    Registry.select(Thunderline.Thundervine.Registry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> Enum.filter(fn
      {Thunderline.Thundervine.TAKEventRecorder, _run_id} -> true
      _ -> false
    end)
    |> Enum.map(fn {_module, run_id} -> run_id end)
  end
end
