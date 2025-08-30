defmodule Thunderline.Thunderbolt.CA.RunnerSupervisor do
  @moduledoc """
  DynamicSupervisor supervising CA `Runner` processes.

  Feature gated by `Thunderline.Feature.enabled?(:ca_viz)` – the supervisor
  simply starts empty if disabled.
  """
  use DynamicSupervisor

  alias Thunderline.Thunderbolt.CA.Runner

  def start_link(opts \\ []), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Start (or ignore if already started) a CA run with given run_id and options"
  def start_run(run_id, opts \\ []) do
    spec = {Runner, Keyword.put(opts, :run_id, run_id)}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc "Stop a CA run by run_id (no-op if not running)"
  def stop_run(run_id) do
    case Registry.lookup(Thunderline.Thunderbolt.CA.Registry, run_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
