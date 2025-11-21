defmodule Thundervine.Supervisor do
  @moduledoc """
  Supervisor for Thundervine persistence and DAG management.

  Manages:
  - TAKEventRecorder instances for active TAK runs
  - Future: DAG compaction workers, pattern analyzers
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[Thundervine.Supervisor] Starting Thundervine persistence layer")

    children = [
      # Registry for TAKEventRecorder instances
      {Registry, keys: :unique, name: Thundervine.Registry},

      # DynamicSupervisor for TAK event recorders
      {DynamicSupervisor, name: Thundervine.EventRecorderSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Start a TAKEventRecorder for a specific TAK run.

  ## Examples

      {:ok, pid} = Thundervine.Supervisor.start_recorder(run_id: "my_run")
  """
  def start_recorder(opts) do
    spec = {Thundervine.TAKEventRecorder, opts}
    DynamicSupervisor.start_child(Thundervine.EventRecorderSupervisor, spec)
  end

  @doc """
  Stop a TAKEventRecorder for a specific run.
  """
  def stop_recorder(run_id) do
    case Registry.lookup(Thundervine.Registry, {Thundervine.TAKEventRecorder, run_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Thundervine.EventRecorderSupervisor, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  List all active TAK event recorders.
  """
  def list_recorders do
    Registry.select(Thundervine.Registry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> Enum.filter(fn
      {Thundervine.TAKEventRecorder, _run_id} -> true
      _ -> false
    end)
    |> Enum.map(fn {_module, run_id} -> run_id end)
  end
end
