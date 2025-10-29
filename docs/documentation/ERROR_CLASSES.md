# 🧪 Error Classification & Handling (Draft v0.2)

> High Command Items: HC-03 (Error taxonomy portion) & HC-09 (Classifier + DLQ)  
> Status: Expanded draft — adds struct contract, mapping heuristics, governance workflow, telemetry enrichment plan.

## 1. Purpose
Create a unified error class system to drive: 
- Consistent Broadway retry vs DLQ routing
- Telemetry aggregation & SLO definition (error budgets)
- User vs system error separation for UI messaging
- Policy-based escalation (alerting for systemic faults)

## 2. Core Dimensions
| Dimension | Values | Drives |
|----------|--------|-------|
| Origin | `user`, `system`, `external`, `infrastructure` | Messaging & ownership |
| Class | `validation`, `transient`, `permanent`, `timeout`, `dependency`, `security` | Retry / DLQ strategy |
| Severity | `info`, `warn`, `error`, `critical` | Alert thresholds |
| Visibility | `user_safe`, `internal_only` | Exposure filtering |

## 3. Canonical Class Definitions
| Class | Definition | Retry Policy | DLQ? | Example |
|-------|-----------|-------------|------|---------|
| `validation` | Input/domain rule violation | none | no | Missing required email address |
| `transient` | Likely recoverable with time/backoff | limited (exp backoff) | escalate after max attempts | SMTP 421 temporary local problem |
| `permanent` | Will not succeed on retry | none | normal (if from async) | SMTP 550 mailbox unavailable |
| `timeout` | Operation exceeded time bound | limited (few attempts) | yes if repeated | External API latency spike |
| `dependency` | Downstream system failure (unavailable) | extended (different backoff) | yes after threshold | Database pool exhaustion |
| `security` | AuthN/Z, policy, integrity event | none | audit channel | Unauthorized access attempt |

Augmented Severity Guidance:
- `info`: Non-actionable, expected occasional conditions (e.g., voluntary cancellation).
- `warn`: Degraded operation; triggers investigation if sustained.
- `error`: User-visible failure or automatic compensation executed.
- `critical`: Immediate page/alert; data loss risk, systemic outage, or security implication.

## 4. Mapping Strategy (Draft)
Classifier contract:
```elixir
@spec classify(term(), map()) :: %Thunderline.Thunderflow.ErrorClass{}
```
Context keys (suggested):
| Key | Type | Purpose |
|-----|------|---------|
| `:module` | atom | Originating module for heuristics |
| `:operation` | atom | Action name / semantic op |
| `:attempt` | integer | Current retry attempt (0-based) |
| `:event` | %Thunderline.Event{} | Event being processed, if any |
| `:external_service` | atom | Name of downstream dependency |
| `:elapsed_ms` | integer | Duration of operation when failure occurred |

Struct example produced:
```elixir
%Thunderline.Thunderflow.ErrorClass{
  origin: :system,
  class: :transient,
  severity: :error,
  visibility: :internal_only,
  code: "SMTP_TEMPFAIL",
  reason: "421 Temporary failure",
  raw: error
}
```

Mapping Heuristics (initial):
| Pattern | Classification |
|---------|----------------|
| `%Ecto.Changeset{valid?: false}` | origin: user, class: validation, severity: info/warn (depending on frequency) |
| `%Thunderline.AuthError{reason: :unauthorized}` | origin: user, class: security, severity: warn |
| `%Mint.TransportError{reason: :timeout}` | origin: external, class: timeout |
| `%SMTP.Response{code: c} when c in 400..451` | origin: external, class: transient |
| `%SMTP.Response{code: c} when c in 500..599` | origin: external, class: permanent |
| `%RuntimeError{message: m}` containing "timeout" | class: timeout |
| `{:bypass, :dependency_unavailable}` tuple | origin: infrastructure, class: dependency |
| Unknown struct/tuple | origin: system, class: transient (default) |

## 5. Retry Matrix (Initial)
| Class | Max Attempts | Backoff (ms) | Jitter | Metric Tag |
|-------|--------------|--------------|--------|------------|
| transient | 5 | 500 * 2^n | yes | retry.transient |
| timeout | 3 | 1000 * 2^n | yes | retry.timeout |
| dependency | 7 | 1000 * 1.5^n | yes | retry.dependency |
| permanent | 0 | - | - | fail.permanent |
| validation | 0 | - | - | fail.validation |
| security | 0 | - | - | fail.security |

## 6. DLQ Policy
Message enters Dead Letter Queue when:
- Exceeds max attempts for class (transient/timeout/dependency)
- Classified `security` (rerouted to audit stream instead of standard DLQ)
- Unclassified / unknown errors (auto-tag `unknown`, alert)

DLQ Event (proposed): `system.dlq.message` payload:
```elixir
%{queue: binary, event_id: binary, class: atom, reason: binary, attempts: integer}
```

## 7. Telemetry Naming
```
[:thunderline, :error, :classified]
[:thunderline, :retry, :start|:stop]
[:thunderline, :dlq, :enqueue]
```
Metadata includes: `class`, `origin`, `severity`, `queue`, `attempt`.

## 8. Integration Points
- Broadway pipeline middleware (custom `:handle_failed`) consults classifier.
- Reactor steps wrap external calls & convert native exceptions.
- LiveView UI references mapping for user-safe messages.

## 9. Governance Workflow
1. New error pattern emerges (log/telemetry spike) → open issue tagged `error-taxonomy`.
2. Provide sample stack trace / struct, frequency, impact.
3. Propose mapping (origin/class/severity/visibility) + rationale.
4. PR adds clause to classifier + test + updates docs table if new class value.
5. Observability steward reviews SLO impact; merge on approval.

Escalation: Re-classification of existing mapping requires sign-off from owning domain steward + observability steward (to prevent silent SLO drift).

## 10. Open TODOs (HC-09 Completion)
- [ ] Implement `Thunderline.Thunderflow.ErrorClassifier` module & struct definition
- [ ] Broadway integration (retry + DLQ producers) with per-class backoff config
- [ ] Add tests for mapping of SMTP codes & Mint timeouts
- [ ] Define metrics dashboards (error rate, class breakdown, DLQ depth, retry success %) 
- [ ] Security error audit log linkage (append to audit resource or dedicated channel)
- [ ] Emit additional telemetry: `[:thunderline,:error,:burst_detected]` (future adaptive backoff)
- [ ] Add linter that warns on `raise` of plain RuntimeError in app code (encourage structured errors)

- Correlate error bursts with event categories
- Adaptive backoff based on historical success probability
- Structured error code registry file

## 12. Example Implementation Sketch
```elixir
defmodule Thunderline.Thunderflow.ErrorClassifier do
  alias Thunderline.Thunderflow.ErrorClass
  @spec classify(term(), map()) :: ErrorClass.t()
  def classify(%Ecto.Changeset{} = cs, ctx) do
    error_class(:user, :validation, severity: :info, visibility: :user_safe, code: "ECTO_INVALID", reason: changeset_summary(cs), raw: cs, ctx: ctx)
  end
  def classify(%Mint.TransportError{reason: :timeout} = err, ctx), do: error_class(:external, :timeout, code: "MINT_TIMEOUT", reason: inspect(err.reason), raw: err, ctx: ctx)
  def classify(%RuntimeError{message: msg} = err, ctx) when is_binary(msg) and String.contains?(msg, "timeout"), do: error_class(:system, :timeout, code: "RUNTIME_TIMEOUT", reason: msg, raw: err, ctx: ctx)
  def classify(other, ctx), do: error_class(:system, :transient, code: "UNKNOWN", reason: short(other), raw: other, ctx: ctx)

  defp error_class(origin, class, opts) do
    ctx = Keyword.get(opts, :ctx, %{})
    %ErrorClass{
      origin: origin,
      class: class,
      severity: Keyword.get(opts, :severity, default_severity(class)),
      visibility: Keyword.get(opts, :visibility, :internal_only),
      code: Keyword.fetch!(opts, :code),
      reason: Keyword.fetch!(opts, :reason),
      raw: Keyword.fetch!(opts, :raw),
      context: Map.take(ctx, [:module, :operation, :attempt, :external_service, :event])
    }
  end

  defp default_severity(:validation), do: :info
  defp default_severity(:transient), do: :error
  defp default_severity(:permanent), do: :error
  defp default_severity(:timeout), do: :warn
  defp default_severity(:dependency), do: :error
  defp default_severity(:security), do: :warn
  defp default_severity(_), do: :error

  defp short(term) do
    term |> inspect(limit: 80) |> String.slice(0, 160)
  end
  defp changeset_summary(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, "; ", fn {field, {msg, _}} -> to_string(field) <> " " <> msg end)
  end
end
```

## 13. Domain-Specific Parser Error Codes (Integrated Addendum)

The following parser / DSL specific errors were previously tracked in a separate addendum file (`ERROR_CLASSES_APPEND.md`). They are now canonical and SHOULD be emitted using the classifier with `origin: :user`, appropriate `class` (`validation` or `permanent` depending on retry semantics), and a stable `code`.

| Code | Class | HTTP Mapping | Description | Mitigation |
|------|-------|--------------|-------------|------------|
| E-PARSE-RULE-001 | parse.rule.syntax | 400 | CA rule line failed grammar parse | Surface first error segment, suggest canonical form `B3/S23 rate=30Hz` |
| E-PARSE-SPEC-001 | parse.spec.syntax | 400 | Workflow spec failed grammar parse | Provide failing line number & remaining text snippet |
| E-PARSE-SPEC-002 | parse.spec.unknown_after | 422 | `after=` references undeclared node | Ensure topological order; reorder or declare parent first |

Classification Guidance:
* Syntax errors: `origin: :user`, `class: :validation`, `severity: :info` (single occurrence) escalating to `:warn` on sustained frequency.
* Unknown reference (`E-PARSE-SPEC-002`): `origin: :user`, `class: :validation`, may elevate to `:error` if emitted post-production deployment (indicates tooling gap).

Telemetry Extension:
Emit `[:thunderline,:parser,:error]` with metadata: `code`, `class`, `line`, `attempt` (if re-processed), and `sampled_stack: boolean`.

## 14. AI Event / Error Cross-Link

With the introduction of `ai_emit/2` and `emit_batch_meta/2` in `Thunderline.EventBus`, AI tool chain failures SHOULD classify errors with additional context keys:
* `:ai_stage` – one of `:tool_start | :tool_result | :conversation_delta | :model_token`
* `:correlation_id` – taken from batch or event correlation (see Event Taxonomy section on correlation propagation)

Recommended AI-Specific Codes (reserve namespace, implement when encountered):
| Code | Scenario | Suggested Mapping |
|------|----------|-------------------|
| AI-TOOL-TIMEOUT | Tool execution exceeded SLA | origin: external (if remote) or system, class: timeout |
| AI-TOOL-BAD-OUTPUT | Output failed schema validation | origin: system, class: validation, visibility: internal_only |
| AI-TOOL-RATE-LIMIT | Upstream model rate limited | origin: external, class: transient |
| AI-STREAM-DROP | Streaming token channel interrupted | origin: infrastructure, class: transient |

---
Document consolidation complete (v0.3 draft). Remove `ERROR_CLASSES_APPEND.md` once all references updated.

---

---
Expanded draft complete. Implement classifier + integration in HC-09 PR series.


## Parser Error Classes (Incremental Addendum)

| Code | Class | HTTP Mapping | Description | Mitigation |
|------|-------|--------------|-------------|------------|
| E-PARSE-RULE-001 | parse.rule.syntax | 400 | CA rule line failed grammar parse | Surface first error segment, suggest canonical form B3/S23 rate=30Hz |
| E-PARSE-SPEC-001 | parse.spec.syntax | 400 | Workflow spec failed grammar parse | Provide failing line number & remaining text snippet |
| E-PARSE-SPEC-002 | parse.spec.unknown_after | 422 | after= references undeclared node | Ensure topological order; reorder or declare parent first |

Add to main ERROR_CLASSES.md on next consolidation sweep.