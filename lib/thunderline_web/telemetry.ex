defmodule ThunderlineWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router.dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # LiveView Metrics
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_params.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_event.stop.duration",
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Thunderline Custom Metrics
      last_value("thunderline.agents.active"),
      last_value("thunderline.chunks.total"),
      last_value("thunderline.memory.usage"),
      counter("thunderline.events.processed"),
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :dispatch_system_metrics, []},
      {__MODULE__, :dispatch_memory_metrics, []},
      {__MODULE__, :dispatch_agent_metrics, []}
    ]
  end

  def dispatch_system_metrics do
    vm_memory = :erlang.memory()

    :telemetry.execute([:thunderline, :system], %{
      memory_total: vm_memory[:total],
      memory_processes: vm_memory[:processes],
      memory_atoms: vm_memory[:atom],
      node_count: length(Node.list()),
      process_count: :erlang.system_info(:process_count)
    })
  end

  def dispatch_memory_metrics do
    vm_memory = :erlang.memory()

    :telemetry.execute([:thunderline, :memory], %{
      usage: vm_memory[:total]
    })
  end

  def dispatch_agent_metrics do
    # Estimate active agents based on process count and system load
    process_count = :erlang.system_info(:process_count)
    estimated_agents = max(0, process_count - 100)  # Rough estimation

    :telemetry.execute([:thunderline, :agents], %{
      active: estimated_agents
    })

    # Mock some chunk processing
    :telemetry.execute([:thunderline, :chunks], %{
      total: :rand.uniform(1000)
    })

    :telemetry.execute([:thunderline, :events], %{}, %{count: 1})
  end
end
