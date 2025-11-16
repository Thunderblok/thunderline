# Thunderclock Domain Overview

**Vertex Position**: Data Plane Ring, Position 7

**Purpose**: Timers & Scheduling domain - manages time-based triggers, cron jobs, and temporal state across the system.

## Charter

Thunderclock is the **temporal heartbeat** of Thunderline. It provides precise timers, scheduled jobs, delayed execution, and time-based state management. All time-sensitive operations flow through Thunderclock.

## Core Responsibilities

### 1. **Timer Management**
- One-shot timers (execute once at specific time)
- Recurring timers (periodic execution)
- Cron-based schedules
- Timer persistence and recovery

### 2. **Delayed Execution**
- Delay messages/events by N seconds/minutes/hours
- Schedule future actions
- Retry backoff timers

### 3. **Time-Based State Machines**
- Timeout transitions
- TTL (time-to-live) enforcement
- Expiration policies

### 4. **Clock Synchronization**
- NTP integration (optional)
- Monotonic time for intervals
- UTC time for timestamps

### 5. **Temporal Queries**
- "Show me all jobs scheduled in next hour"
- "List expired resources"
- "Find overdue tasks"

## Ash Resources

### Timer
```elixir
defmodule Thunderline.Thunderclock.Timer do
  use Ash.Resource,
    domain: Thunderline.Thunderclock,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :fire_at, :utc_datetime, allow_nil?: false
    attribute :fired_at, :utc_datetime
    attribute :recurring, :boolean, default: false
    attribute :interval_seconds, :integer                # For recurring timers
    attribute :action, :map, allow_nil?: false           # Action to execute
    attribute :status, :atom do
      constraints one_of: [:scheduled, :firing, :fired, :cancelled, :failed]
      default :scheduled
    end
    attribute :retries, :integer, default: 0
    attribute :max_retries, :integer, default: 3
  end
  
  relationships do
    belongs_to :policy, Thunderline.Thundercrown.Policy
  end
  
  state_machine do
    initial_states [:scheduled]
    default_initial_state :scheduled
    
    transitions do
      transition :fire, from: :scheduled, to: :firing
      transition :complete, from: :firing, to: :fired
      transition :retry, from: :firing, to: :scheduled
      transition :fail, from: :firing, to: :failed
      transition :cancel, from: [:scheduled, :firing], to: :cancelled
    end
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
    
    create :schedule do
      argument :fire_at, :utc_datetime, allow_nil?: false
      argument :action, :map, allow_nil?: false
      change set_attribute(:status, :scheduled)
    end
    
    update :fire do
      change transition_state(:fire)
      change ExecuteTimerAction
    end
  end
end
```

### CronJob
```elixir
defmodule Thunderline.Thunderclock.CronJob do
  use Ash.Resource,
    domain: Thunderline.Thunderclock,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :cron_expression, :string, allow_nil?: false  # "0 * * * *"
    attribute :action, :map, allow_nil?: false
    attribute :enabled, :boolean, default: true
    attribute :last_run_at, :utc_datetime
    attribute :next_run_at, :utc_datetime
    attribute :timezone, :string, default: "UTC"
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
    
    update :execute do
      change set_attribute(:last_run_at, expr(now()))
      change ComputeNextRunTime
      change ExecuteCronAction
    end
  end
end
```

### DelayedJob
```elixir
defmodule Thunderline.Thunderclock.DelayedJob do
  use Ash.Resource,
    domain: Thunderline.Thunderclock,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :execute_at, :utc_datetime, allow_nil?: false
    attribute :action_module, :atom, allow_nil?: false
    attribute :action_name, :atom, allow_nil?: false
    attribute :action_params, :map, default: %{}
    attribute :priority, :integer, default: 5
    attribute :executed, :boolean, default: false
  end
  
  actions do
    defaults [:create, :read, :update]
    
    read :due_now do
      filter expr(execute_at <= ^DateTime.utc_now() and not executed)
    end
  end
end
```

## Core GenServers

### Clock.Ticker

```elixir
defmodule Thunderline.Thunderclock.Ticker do
  use GenServer
  
  @tick_interval_ms 1_000  # 1 second
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(state) do
    schedule_tick()
    {:ok, state}
  end
  
  def handle_info(:tick, state) do
    # Emit system-wide tick event
    Thunderflow.EventBus.publish_event!(%{
      name: "system.clock.tick",
      domain: "clock",
      source: :clock,
      payload: %{timestamp: DateTime.utc_now()}
    })
    
    # Check for due timers
    fire_due_timers()
    
    schedule_tick()
    {:noreply, state}
  end
  
  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
  
  defp fire_due_timers do
    now = DateTime.utc_now()
    
    Thunderclock.Timer
    |> Ash.Query.filter(fire_at <= ^now and status == :scheduled)
    |> Ash.read!()
    |> Enum.each(fn timer ->
      Task.start(fn -> fire_timer(timer) end)
    end)
  end
  
  defp fire_timer(timer) do
    Thunderclock.Timer
    |> Ash.Changeset.for_update(:fire, timer)
    |> Ash.update!()
  end
end
```

### Clock.CronScheduler

```elixir
defmodule Thunderline.Thunderclock.CronScheduler do
  use GenServer
  
  @check_interval_ms 60_000  # Check every minute
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(state) do
    schedule_check()
    {:ok, state}
  end
  
  def handle_info(:check_jobs, state) do
    execute_due_cron_jobs()
    schedule_check()
    {:noreply, state}
  end
  
  defp schedule_check do
    Process.send_after(self(), :check_jobs, @check_interval_ms)
  end
  
  defp execute_due_cron_jobs do
    now = DateTime.utc_now()
    
    Thunderclock.CronJob
    |> Ash.Query.filter(enabled == true and next_run_at <= ^now)
    |> Ash.read!()
    |> Enum.each(fn job ->
      Task.start(fn -> execute_cron_job(job) end)
    end)
  end
  
  defp execute_cron_job(job) do
    Thunderclock.CronJob
    |> Ash.Changeset.for_update(:execute, job)
    |> Ash.update!()
  end
end
```

## Integration Points

### Vertical Edge: Crown → Clock (Policy-Driven Timers)

```elixir
# Crown defines retention policy
policy = Thundercrown.Policy.create!(%{
  name: "delete_old_events",
  retention_days: 30
})

# Clock creates timer to enforce policy
Thunderclock.Timer.schedule!(%{
  name: "enforce_retention_#{policy.id}",
  fire_at: DateTime.add(DateTime.utc_now(), 86400, :second),  # 24 hours
  recurring: true,
  interval_seconds: 86400,
  action: %{
    module: Thunderflow,
    function: :delete_events_older_than,
    args: [30, :days]
  },
  policy_id: policy.id
})
```

### Horizontal Edge: Clock → Block (Timer-Triggered Execution)

```elixir
# Clock fires timer
timer = Thunderclock.Timer.get!(timer_id)

# Block executes action
case timer.action do
  %{module: mod, function: func, args: args} ->
    apply(mod, func, args)
  
  %{workflow_id: wid} ->
    Thunderblock.execute_workflow(wid)
end
```

### Horizontal Edge: Vine → Clock (Provenance-Based Scheduling)

```elixir
# Vine detects event pattern requiring future action
Thundervine.on_pattern_match(:user_inactive_7_days, fn event ->
  # Schedule reminder email in 24 hours
  Thunderclock.DelayedJob.create!(%{
    execute_at: DateTime.add(DateTime.utc_now(), 86400, :second),
    action_module: MyApp.Emails,
    action_name: :send_reminder,
    action_params: %{user_id: event.payload.user_id}
  })
end)
```

## Use Cases

### 1. Event Retention Enforcement

```elixir
# Schedule daily cleanup job
CronJob.create!(%{
  name: "cleanup_old_events",
  cron_expression: "0 2 * * *",  # 2 AM daily
  action: %{
    module: Thunderflow,
    function: :delete_events_older_than,
    args: [30, :days]
  }
})
```

### 2. Delayed Notifications

```elixir
# User signs up, send welcome email in 1 hour
DelayedJob.create!(%{
  execute_at: DateTime.add(DateTime.utc_now(), 3600, :second),
  action_module: MyApp.Emails,
  action_name: :send_welcome,
  action_params: %{user_id: user.id}
})
```

### 3. State Machine Timeouts

```elixir
# Order payment times out after 15 minutes
Timer.schedule!(%{
  name: "order_timeout_#{order.id}",
  fire_at: DateTime.add(order.created_at, 900, :second),
  action: %{
    module: MyApp.Orders,
    function: :cancel_unpaid,
    args: [order.id]
  }
})
```

### 4. Recurring Health Checks

```elixir
# Check service health every 5 minutes
CronJob.create!(%{
  name: "health_check_service_#{service.id}",
  cron_expression: "*/5 * * * *",
  action: %{
    module: MyApp.HealthChecks,
    function: :check_service,
    args: [service.id]
  }
})
```

## Telemetry Events

```elixir
[:thunderline, :clock, :tick]                      # System tick (every second)
[:thunderline, :clock, :timer, :scheduled]         # Timer scheduled
[:thunderline, :clock, :timer, :fired]             # Timer fired
[:thunderline, :clock, :timer, :failed]            # Timer failed
[:thunderline, :clock, :cron, :executed]           # Cron job executed
[:thunderline, :clock, :delayed_job, :executed]    # Delayed job executed
```

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|--------------|--------------|------------|
| Schedule timer | 5ms | 20ms | 1k/s |
| Fire timer | 10ms | 50ms | 500/s |
| Check due timers | 50ms | 200ms | N/A |
| Execute cron job | 100ms | 500ms | N/A |

## Testing Strategy

### Unit Tests
- Cron expression parsing
- Next run time calculation
- Timer state transitions
- Recurring timer logic

### Integration Tests
- End-to-end timer scheduling and firing
- Cron job execution
- Delayed job execution
- Policy-driven timers

### Chaos Tests
- Clock drift handling
- Timer recovery after crash
- Duplicate firing prevention

## Development Phases

### Phase 1: Foundation
- [ ] Create domain module
- [ ] Define Ash resources (Timer, CronJob, DelayedJob)
- [ ] Implement Ticker GenServer
- [ ] Basic timer scheduling

### Phase 2: Advanced Features
- [ ] CronScheduler GenServer
- [ ] Recurring timers
- [ ] State machine timeout integration
- [ ] Telemetry instrumentation

### Phase 3: Production Hardening
- [ ] Timer persistence and recovery
- [ ] Distributed timer coordination
- [ ] Clock drift detection
- [ ] Performance optimization

## References

- [Prism Topology](../../architecture/PRISM_TOPOLOGY.md)
- [Vertical Edges](../../architecture/VERTICAL_EDGES.md)
- [Horizontal Rings](../../architecture/HORIZONTAL_RINGS.md)
