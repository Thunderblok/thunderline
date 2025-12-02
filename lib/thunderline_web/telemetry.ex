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

      # Oban Job Metrics (exposed via LiveDashboard)
      counter("oban.job.start",
        event_name: [:oban, :job, :start],
        tags: [:queue, :worker],
        measurement: :system_time,
        description: "Oban job executions started"
      ),
      summary("oban.job.stop.duration",
        event_name: [:oban, :job, :stop],
        unit: {:native, :millisecond},
        tags: [:queue, :worker, :state],
        description: "Oban job execution duration"
      ),
      counter("oban.job.exception",
        event_name: [:oban, :job, :exception],
        tags: [:queue, :worker, :kind],
        measurement: :duration,
        description: "Oban job exceptions"
      ),

      # Oban Queue Depth Gauges (polled periodically)
      last_value("thunderline.oban.queue.available",
        description: "Jobs available in Oban queue",
        tags: [:queue]
      ),
      last_value("thunderline.oban.queue.executing",
        description: "Jobs currently executing in Oban queue",
        tags: [:queue]
      ),
      last_value("thunderline.oban.queue.scheduled",
        description: "Jobs scheduled for future execution",
        tags: [:queue]
      ),
      last_value("thunderline.oban.queue.retryable",
        description: "Jobs pending retry in Oban queue",
        tags: [:queue]
      ),

      # Thunderline Custom Metrics
      last_value("thunderline.agents.active"),
      last_value("thunderline.chunks.total"),
      last_value("thunderline.memory.usage"),
      counter("thunderline.events.processed"),
      counter("thunderline.gate.auth.result", tags: [:result], measurement: :count),
      counter("thunderline.event.dropped", tags: [:reason, :name], measurement: :count),
      counter("thunderline.grid.zone.claimed", tags: [:zone, :tenant], measurement: :count),
      counter("thunderline.grid.zone.reclaimed", tags: [:zone, :tenant], measurement: :count),
      counter("thunderline.grid.zone.expired", tags: [:zone], measurement: :count),
      counter("thunderline.grid.zone.conflict",
        tags: [:zone, :owner, :attempted_owner],
        measurement: :count
      ),
      summary("thunderline.retention.sweep.duration",
        event_name: [:thunderline, :retention, :sweep],
        measurement: :duration_ms,
        unit: :millisecond,
        tags: [:resource, :dry_run?]
      ),
      last_value("thunderline.retention.sweep.expired",
        event_name: [:thunderline, :retention, :sweep],
        measurement: :expired,
        tags: [:resource]
      ),
      last_value("thunderline.retention.sweep.deleted",
        event_name: [:thunderline, :retention, :sweep],
        measurement: :deleted,
        tags: [:resource]
      ),
      last_value("thunderline.retention.sweep.kept",
        event_name: [:thunderline, :retention, :sweep],
        measurement: :kept,
        tags: [:resource]
      )
    ] ++ Thunderline.Thunderflow.Telemetry.Jobs.metrics()
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :dispatch_system_metrics, []},
      {__MODULE__, :dispatch_memory_metrics, []},
      {__MODULE__, :dispatch_agent_metrics, []},
      {__MODULE__, :dispatch_oban_queue_metrics, []}
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
    mock? = Application.get_env(:thunderline, :mock_metrics, false)

    agents =
      if mock?, do: estimate_agents(), else: Thunderline.Thunderflow.MetricSources.active_agents()

    chunks =
      if mock?, do: mock_chunk_total(), else: Thunderline.Thunderflow.MetricSources.chunk_total()

    :telemetry.execute([:thunderline, :agents], %{active: agents})
    :telemetry.execute([:thunderline, :chunks], %{total: chunks})

    qstats = Thunderline.Thunderflow.MetricSources.queue_depths()

    :telemetry.execute([:thunderline, :events], %{
      pending: qstats.pending,
      processing: qstats.processing,
      failed: qstats.failed,
      dead_letter: qstats.dead_letter,
      total: qstats.total
    })
  end

  defp estimate_agents do
    process_count = :erlang.system_info(:process_count)
    max(0, process_count - 100)
  end

  defp mock_chunk_total, do: :rand.uniform(1000)

  @doc """
  Dispatch Oban queue depth metrics for LiveDashboard.

  Polls all configured Oban queues and emits gauge metrics for each state.
  Safe to call even when Oban is not running - returns zeros.
  """
  def dispatch_oban_queue_metrics do
    queues = Application.get_env(:thunderline, Oban, [])[:queues] || []

    for {queue_name, _opts} <- queues do
      counts = get_oban_queue_counts(queue_name)

      :telemetry.execute(
        [:thunderline, :oban, :queue],
        %{
          available: counts.available,
          executing: counts.executing,
          scheduled: counts.scheduled,
          retryable: counts.retryable
        },
        %{queue: queue_name}
      )
    end
  rescue
    _ -> :ok
  end

  defp get_oban_queue_counts(queue_name) do
    import Ecto.Query, only: [from: 2]

    queue_str = to_string(queue_name)

    try do
      counts =
        from(j in "oban_jobs",
          where: j.queue == ^queue_str,
          group_by: j.state,
          select: {j.state, count(j.id)}
        )
        |> Thunderline.Repo.all()
        |> Map.new()

      %{
        available: Map.get(counts, "available", 0),
        executing: Map.get(counts, "executing", 0),
        scheduled: Map.get(counts, "scheduled", 0),
        retryable: Map.get(counts, "retryable", 0)
      }
    rescue
      _ ->
        %{available: 0, executing: 0, scheduled: 0, retryable: 0}
    end
  end

  @doc """
  Gate authentication telemetry event documentation.

  Event: [:thunderline, :gate, :auth, :result]
    Measurements: %{count: 1}
    Metadata keys:
      :result - :success | :missing | :expired | :deny | :invalid
      :actor_id, :tenant, :scopes, :correlation_id (present only on :success)

  Usage: Emitted once per inbound request by ActorContextPlug.
  Suggested alerts:
    * Spike in :missing or :expired > 2x 5m baseline
    * Sustained :deny/:invalid rate above threshold (potential auth abuse)
    * Drop in :success ratio below SLO
  """
  def gate_auth_event_doc, do: :ok
end
