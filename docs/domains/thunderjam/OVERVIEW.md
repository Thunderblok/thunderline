# Thunderjam Domain Overview

**Vertex Position**: Control Plane Ring, Position 6

**Purpose**: Quality of Service (QoS) and Rate Limiting domain - manages resource consumption, fairness, and backpressure across the system.

## Charter

Thunderjam is responsible for **protecting system resources** through rate limiting, throttling, and QoS policies. It ensures fair resource allocation, prevents abuse, and maintains system stability under load.

## Core Responsibilities

### 1. **Rate Limiting**
- Token bucket algorithms
- Sliding window counters
- Per-actor rate limits
- Per-resource rate limits
- Burst allowances

### 2. **QoS Policies**
- Priority queues (high/medium/low)
- Fairness algorithms (round-robin, weighted fair queueing)
- Service-level agreements (SLA) enforcement
- Quota management

### 3. **Backpressure Management**
- Broadway pipeline backpressure
- Circuit breakers
- Adaptive rate limiting
- Load shedding

### 4. **Abuse Detection**
- Anomaly detection (spike detection)
- Pattern-based blocking
- Automatic cooldown periods
- Integration with Thundersec for bans

### 5. **Metrics & Monitoring**
- Rate limit hit rates
- Quota utilization
- Queue depths
- Latency distribution

## Ash Resources

### RateLimit
```elixir
defmodule Thunderline.Thunderjam.RateLimit do
  use Ash.Resource,
    domain: Thunderline.Thunderjam,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :resource_type, :atom                     # :api_calls, :events, :db_writes
    attribute :max_per_second, :integer, allow_nil?: false
    attribute :max_per_minute, :integer
    attribute :max_per_hour, :integer
    attribute :burst_size, :integer, default: 0
    attribute :enabled, :boolean, default: true
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
    
    read :check_limit do
      argument :actor_id, :uuid, allow_nil?: false
      argument :resource_type, :atom, allow_nil?: false
      prepare CheckRateLimitPreparation
    end
  end
end
```

### Quota
```elixir
defmodule Thunderline.Thunderjam.Quota do
  use Ash.Resource,
    domain: Thunderline.Thunderjam,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :actor_id, :uuid, allow_nil?: false
    attribute :resource_type, :atom, allow_nil?: false
    attribute :limit, :integer, allow_nil?: false
    attribute :used, :integer, default: 0
    attribute :resets_at, :utc_datetime
  end
  
  actions do
    defaults [:create, :read, :update]
    
    update :consume do
      argument :amount, :integer, allow_nil?: false
      validate compare(:used, less_than: :limit)
      change atomic_update(:used, expr(used + ^arg(:amount)))
    end
    
    update :reset do
      change set_attribute(:used, 0)
      change set_attribute(:resets_at, expr(now()))
    end
  end
end
```

### PriorityQueue
```elixir
defmodule Thunderline.Thunderjam.PriorityQueue do
  use Ash.Resource,
    domain: Thunderline.Thunderjam,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :priority, :atom do
      constraints one_of: [:critical, :high, :medium, :low]
      default :medium
    end
    attribute :max_size, :integer, default: 1000
    attribute :current_size, :integer, default: 0
  end
end
```

## Rate Limiting Algorithms

### Token Bucket

```elixir
defmodule Thunderline.Thunderjam.TokenBucket do
  @moduledoc """
  Token bucket algorithm for rate limiting.
  Allows bursts up to bucket_size, refills at rate tokens_per_second.
  """
  
  defstruct [:bucket_size, :tokens_per_second, :tokens, :last_refill]
  
  def new(bucket_size, tokens_per_second) do
    %__MODULE__{
      bucket_size: bucket_size,
      tokens_per_second: tokens_per_second,
      tokens: bucket_size,
      last_refill: System.monotonic_time(:millisecond)
    }
  end
  
  def consume(%__MODULE__{} = bucket, tokens_needed) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - bucket.last_refill
    
    # Refill tokens based on elapsed time
    refill_amount = (elapsed_ms / 1000.0) * bucket.tokens_per_second
    new_tokens = min(bucket.tokens + refill_amount, bucket.bucket_size)
    
    if new_tokens >= tokens_needed do
      # Allow request
      {:ok, %{bucket | tokens: new_tokens - tokens_needed, last_refill: now}}
    else
      # Rate limit exceeded
      {:error, :rate_limit_exceeded, bucket}
    end
  end
end
```

### Sliding Window Counter

```elixir
defmodule Thunderline.Thunderjam.SlidingWindow do
  @moduledoc """
  Sliding window counter for precise rate limiting.
  Tracks requests in fixed time windows.
  """
  
  def check_rate_limit(actor_id, resource_type, limit, window_seconds) do
    now = System.system_time(:second)
    window_start = now - window_seconds
    
    # Count requests in window
    count = count_requests(actor_id, resource_type, window_start, now)
    
    if count < limit do
      record_request(actor_id, resource_type, now)
      :ok
    else
      {:error, :rate_limit_exceeded}
    end
  end
  
  defp count_requests(actor_id, resource_type, window_start, now) do
    # Query ETS table for requests in time window
    :ets.select_count(:rate_limit_requests, [
      {
        {actor_id, resource_type, :"$1"},
        [{:andalso, {:>=, :"$1", window_start}, {:"=<", :"$1", now}}],
        [true]
      }
    ])
  end
  
  defp record_request(actor_id, resource_type, timestamp) do
    :ets.insert(:rate_limit_requests, {{actor_id, resource_type, timestamp}})
  end
end
```

## Integration Points

### Vertical Edge: Jam → Vine (Rate Limited Provenance)

```elixir
# Jam checks rate limit before allowing provenance write
case Thunderjam.check_rate_limit(actor_id, :provenance_writes) do
  :ok ->
    Thundervine.record_provenance(event)
  {:error, :rate_limit_exceeded} ->
    # Queue for later or drop
    {:error, "Provenance rate limit exceeded"}
end
```

### Horizontal Edge: Sec → Jam (Auth-Based Limits)

```elixir
# Sec provides authentication tier
auth_context = Thundersec.authenticate(request)

# Jam applies tier-specific limits
limit = case auth_context.tier do
  :premium -> 10_000
  :standard -> 1_000
  :free -> 100
end

Thunderjam.apply_rate_limit(auth_context.actor_id, limit)
```

### Horizontal Edge: Jam → Crown (Violation Feedback)

```elixir
# Jam detects repeated violations
violations = Thunderjam.get_violations(actor_id, last: {:hours, 1})

if Enum.count(violations) > 10 do
  # Notify Crown to update policy
  Thunderflow.EventBus.publish_event!(%{
    name: "qos.abuse_detected",
    domain: "jam",
    source: :jam,
    payload: %{actor_id: actor_id, violations: violations}
  })
end
```

## QoS Policies

### Priority-Based Processing

```elixir
defmodule Thunderline.Thunderjam.PriorityProcessor do
  use GenServer
  
  def handle_info(:process_queues, state) do
    # Process critical queue first
    process_queue(:critical, state)
    process_queue(:high, state)
    process_queue(:medium, state)
    process_queue(:low, state)
    
    schedule_next_processing()
    {:noreply, state}
  end
  
  defp process_queue(priority, state) do
    # Dequeue and process items based on priority
    items = dequeue_batch(priority, batch_size: 10)
    Enum.each(items, &process_item/1)
  end
end
```

### Fair Queueing

```elixir
defmodule Thunderline.Thunderjam.FairQueue do
  @moduledoc """
  Weighted fair queueing - ensures no actor monopolizes resources.
  """
  
  def dequeue_fair(queues, weights) do
    # Round-robin with weights
    queues
    |> Enum.zip(weights)
    |> Enum.flat_map(fn {queue, weight} ->
      Enum.take(queue, weight)
    end)
  end
end
```

## Telemetry Events

```elixir
[:thunderline, :jam, :rate_limit, :check]        # Rate limit check
[:thunderline, :jam, :rate_limit, :exceeded]     # Limit exceeded
[:thunderline, :jam, :quota, :consumed]          # Quota consumed
[:thunderline, :jam, :queue, :enqueued]          # Item queued
[:thunderline, :jam, :queue, :dequeued]          # Item dequeued
[:thunderline, :jam, :backpressure, :applied]    # Backpressure triggered
```

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|--------------|--------------|------------|
| Rate limit check (ETS) | 50μs | 200μs | 100k/s |
| Rate limit check (DB) | 5ms | 20ms | 1k/s |
| Quota consume | 10ms | 50ms | 500/s |
| Queue enqueue | 1ms | 5ms | 10k/s |

## Testing Strategy

### Unit Tests
- Token bucket refill logic
- Sliding window boundary conditions
- Priority queue ordering
- Quota overflow handling

### Integration Tests
- End-to-end rate limiting
- Multi-actor fairness
- Backpressure propagation

### Chaos Tests
- Burst traffic patterns
- Quota exhaustion scenarios
- Queue overflow handling

## Development Phases

### Phase 1: Foundation
- [ ] Create domain module
- [ ] Define Ash resources (RateLimit, Quota, PriorityQueue)
- [ ] Implement token bucket algorithm
- [ ] ETS-based rate limit cache

### Phase 2: Integration
- [ ] Integration with Thundersec (auth-based limits)
- [ ] Integration with Thundervine (provenance rate limiting)
- [ ] Broadway backpressure integration
- [ ] Telemetry instrumentation

### Phase 3: Advanced Features
- [ ] Adaptive rate limiting (auto-adjust based on load)
- [ ] Anomaly detection (spike detection)
- [ ] Multi-region quota sharing
- [ ] Real-time monitoring dashboard

## References

- [Prism Topology](../../architecture/PRISM_TOPOLOGY.md)
- [Horizontal Rings](../../architecture/HORIZONTAL_RINGS.md)
- [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket)
