# Thunderline Error Classes

> **Status**: HC-03 Specification | **Version**: 1.0 | **Last Updated**: 2025-11-25

This document defines the canonical error classification system for Thunderline, covering error types, retry behaviors, and dead letter queue (DLQ) policies.

---

## 1. Error Classification

Errors in Thunderline are classified into three main categories that determine retry behavior:

| Class | Description | Retry? | Example |
|-------|-------------|--------|---------|
| `:transient` | Temporary failures that may succeed on retry | ✅ Yes | Network timeout, DB connection drop |
| `:permanent` | Failures that will never succeed | ❌ No (DLQ) | Invalid schema, missing required field |
| `:unknown` | Unclassified errors | ⚠️ Limited | Unexpected exceptions |

---

## 2. Common Error Atoms

### 2.1 Resource Errors

| Error | Class | Description |
|-------|-------|-------------|
| `:not_found` | `:permanent` | Resource does not exist |
| `:already_exists` | `:permanent` | Resource already created |
| `:community_not_found` | `:permanent` | Community resource missing |
| `:invalid_loader` | `:permanent` | Loader function invalid |
| `:not_implemented` | `:permanent` | Feature not yet available |

### 2.2 Validation Errors

| Error | Class | Description |
|-------|-------|-------------|
| `:invalid_name` | `:permanent` | Event name format invalid |
| `:short_name` | `:permanent` | Event name has <2 segments |
| `:reserved_violation` | `:permanent` | Used reserved prefix incorrectly |
| `:missing_correlation_id` | `:permanent` | No correlation ID provided |
| `:bad_correlation_id` | `:permanent` | Invalid UUID format |
| `:invalid_taxonomy_version` | `:permanent` | Version must be positive integer |
| `:invalid_event_version` | `:permanent` | Version must be positive integer |
| `:invalid_meta` | `:permanent` | Meta must be a map |
| `:unsupported_event` | `:permanent` | Non-Event struct passed to EventBus |
| `:invalid_event_format` | `:permanent` | Cannot normalize event |

### 2.3 Processing Errors

| Error | Class | Description |
|-------|-------|-------------|
| `:timeout` | `:transient` | Operation timed out |
| `:no_subscriber_available` | `:transient` | No consumer ready for message |
| `:unexpected_ack` | `:transient` | ACK received for unknown message |
| `:normalization_failed` | `:permanent` | Event normalization error |

### 2.4 Action Errors

| Error | Class | Description |
|-------|-------|-------------|
| `:unknown_action` | `:permanent` | Action not recognized |
| `:already_started` | `:transient` | Process already running |

---

## 3. Structured Error Tuples

Errors can also be structured tuples for additional context:

```elixir
# Simple atom
{:error, :not_found}

# Tuple with context
{:error, {:forbidden_category, {:bolt, "ui.command.something"}}}
{:error, {:missing, :name}}
{:error, {:invalid, :payload}}
{:error, {:invalid_format, "bad.name"}}
{:error, {:normalization_failed, %RuntimeError{}}}
```

### 3.1 Tuple Error Patterns

| Pattern | Class | Description |
|---------|-------|-------------|
| `{:missing, field}` | `:permanent` | Required field not provided |
| `{:invalid, field}` | `:permanent` | Field value invalid |
| `{:invalid_format, value}` | `:permanent` | Value format incorrect |
| `{:forbidden_category, {source, name}}` | `:permanent` | Category not allowed for domain |
| `{:already_exists, id}` | `:permanent` | Duplicate resource |
| `{:normalization_failed, exception}` | `:permanent` | Event normalization error |

---

## 4. Retry Policy

### 4.1 Policy Structure

```elixir
%Thunderline.Thunderflow.RetryPolicy{
  category: atom(),           # Policy category name
  max_attempts: pos_integer(), # Maximum retry attempts
  strategy: :none | :exponential  # Backoff strategy
}
```

### 4.2 Default Policies

| Category | Max Attempts | Strategy | Use Case |
|----------|--------------|----------|----------|
| `:ml_run` | 5 | `:exponential` | ML pipeline events |
| `:ml_trial` | 3 | `:exponential` | ML trial events |
| `:ui_command` | 2 | `:none` | User-initiated commands |
| `:default` | 3 | `:exponential` | All other events |

### 4.3 Policy Resolution

Policies are resolved based on event name prefix:

```elixir
# From RetryPolicy.for_name/1
"ml.run.*"     → :ml_run (5 attempts, exponential)
"ml.trial.*"   → :ml_trial (3 attempts, exponential)  
"ui.command.*" → :ui_command (2 attempts, no backoff)
*              → :default (3 attempts, exponential)
```

### 4.4 Exponential Backoff

Formula: `base_delay * 2^(attempt-1)` with jitter

```elixir
# From Thunderline.Thunderflow.Support.Backoff
Attempt 1: ~100ms
Attempt 2: ~200ms
Attempt 3: ~400ms
Attempt 4: ~800ms
Attempt 5: ~1600ms
```

---

## 5. Dead Letter Queue (DLQ)

### 5.1 When Events Go to DLQ

Events are moved to DLQ when:
1. Retry budget exhausted (max attempts reached)
2. Error classified as `:permanent`
3. Error type is `:unknown` and retries exceeded

### 5.2 DLQ Entry Structure

```elixir
%{
  id: String.t(),           # Original event ID
  table: atom(),            # Source Mnesia table
  attempts: integer(),      # Number of attempts made
  created_at: DateTime.t(), # Original event creation
  failed_at: DateTime.t(),  # When DLQ'd
  reason: String.t(),       # Failure reason
  pipeline_type: atom(),    # :general, :realtime, :cross_domain
  priority: atom(),         # Event priority
  meta: map()               # DLQ metadata
}
```

### 5.3 DLQ Tables

| Table | Pipeline Type |
|-------|---------------|
| `Thunderflow.MnesiaProducer` | `:general` |
| `Thunderflow.CrossDomainEvents` | `:cross_domain` |
| `Thunderflow.RealTimeEvents` | `:realtime` |

### 5.4 DLQ Telemetry

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:thunderline, :event, :dlq, :size]` | `%{count: n}` | `%{threshold, previous_count}` |
| `[:thunderline, :pipeline, :dlq]` | `%{count: 1}` | `%{reason, event_name}` |

### 5.5 Alerting

DLQ alerts broadcast on `thunderline:dlq:alerts`:

```elixir
# Threshold exceeded
{:dlq_threshold_exceeded, %{count: 105, threshold: 100, ...}}

# Threshold cleared
{:dlq_threshold_cleared, %{count: 95, threshold: 100, ...}}
```

Default threshold: 100 entries (configurable via `:thunderline, DLQ, :threshold`)

---

## 6. Error Handling Patterns

### 6.1 EventBus Error Handling

```elixir
# Always pattern match on publish results
case Thunderline.EventBus.publish_event(event) do
  {:ok, published_event} ->
    # Success path
    handle_success(published_event)
    
  {:error, reason} ->
    # Error path - log and handle
    Logger.warning("Event publish failed: #{inspect(reason)}")
    handle_error(reason)
end
```

### 6.2 Validator Error Handling

```elixir
# In production (mode = :drop)
# Invalid events are:
# 1. Logged as warning
# 2. Dropped (not published)
# 3. Audit event emitted: "audit.event_drop"
# 4. Telemetry emitted: [:thunderline, :event, :dropped]
```

### 6.3 Broadway Error Handling

```elixir
# In Broadway message handlers
def handle_message(_processor, message, _context) do
  case process(message.data) do
    {:ok, result} ->
      Message.put_data(message, result)
      
    {:error, reason} ->
      # Let Broadway handle retry/DLQ based on RetryPolicy
      Message.failed(message, reason)
  end
end
```

---

## 7. Error Classification API

### 7.1 Future: Error Classifier (HC-09)

```elixir
# Planned API for central error classification
defmodule Thunderline.Thunderflow.ErrorClassifier do
  @spec classify(term()) :: :transient | :permanent | :unknown
  def classify({:error, :timeout}), do: :transient
  def classify({:error, :not_found}), do: :permanent
  def classify({:error, {:invalid, _}}), do: :permanent
  def classify(_), do: :unknown
end
```

### 7.2 Manual Classification

Until HC-09 is implemented, classify errors manually:

```elixir
defp classify_error({:error, :timeout}), do: :transient
defp classify_error({:error, :connection_refused}), do: :transient
defp classify_error({:error, :not_found}), do: :permanent
defp classify_error({:error, {:invalid, _}}), do: :permanent
defp classify_error(_), do: :unknown
```

---

## 8. Monitoring & Observability

### 8.1 DLQ Stats API

```elixir
# Get current DLQ statistics
Thunderline.Thunderflow.DLQ.stats()
# => %{count: 5, threshold: 100, recent: [...]}

# Get DLQ size
Thunderline.Thunderflow.DLQ.size()
# => 5

# Get recent failures
Thunderline.Thunderflow.DLQ.recent(10)
# => [%{id: "...", reason: "...", ...}, ...]
```

### 8.2 Telemetry Handlers

```elixir
# Attach handler for DLQ size changes
:telemetry.attach(
  "dlq-monitor",
  [:thunderline, :event, :dlq, :size],
  fn _event, %{count: count}, metadata, _config ->
    if count > metadata.threshold do
      Logger.error("DLQ threshold exceeded: #{count}/#{metadata.threshold}")
    end
  end,
  nil
)
```

---

## 9. Best Practices

### 9.1 Error Design

1. **Use atoms for simple errors**: `:not_found`, `:timeout`
2. **Use tuples for context**: `{:invalid, :email}`, `{:forbidden, resource_id}`
3. **Prefer specific over generic**: `:community_not_found` over `:not_found`
4. **Include recovery hints** in error metadata when possible

### 9.2 Retry Design

1. **UI commands**: Low retry count (2), no backoff (fast fail)
2. **ML operations**: Higher retry count (5), exponential backoff
3. **External calls**: Always add timeout handling
4. **Idempotent operations**: Safe to retry with exponential backoff

### 9.3 DLQ Hygiene

1. **Monitor DLQ size** via telemetry/dashboards
2. **Review failed events** regularly (weekly ops review)
3. **Clear after investigation**: Don't let DLQ grow unbounded
4. **Alert on threshold**: Set meaningful thresholds per environment

---

## References

- `lib/thunderline/thunderflow/retry_policy.ex` - Retry policy definitions
- `lib/thunderline/thunderflow/dlq.ex` - DLQ observability helpers
- `lib/thunderline/thunderflow/event_validator.ex` - Validation and error handling
- `lib/thunderline/thunderflow/support/backoff.ex` - Backoff calculations
- `EVENT_TAXONOMY.md` - Event naming and validation rules
