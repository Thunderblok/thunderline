# Google-Connected PAC ERP - Implementation Roadmap

> **Status**: Planning Phase  
> **Target MVP**: 5-day sprint  
> **Domain**: Small business ERP automation via PAC agent + Google Workspace

## Architecture Alignment

This roadmap leverages Thunderline's 7-domain architecture:
- **ThunderBlock (Vault)**: Persistent storage (RLS-enabled Postgres)
- **ThunderFlow**: Event pipelines (Broadway + Mnesia queues)
- **ThunderCrown**: Policy engine (permit issuance)
- **ThunderBolt**: Worker/skill system (Oban + Jido)
- **ThunderGate**: External connectors (Google OAuth/APIs)
- **ThunderGrid**: GraphQL API (AshGraphQL)
- **ThunderLink**: Mesh coordination + device enrollment

---
 
## Status Overview (Week 42)

| Track | Status | Dependency Readiness |
| --- | --- | --- |
| Identity & DID Foundations | 🟡 In Progress | Awaiting decision between `did_kit` NIF and pure Elixir `web5_ex`; see [`documentation/README.md`](documentation/README.md) refresh plan. |
| Google OAuth Connector | 🔴 Blocked | Service account policy review pending Crown sign-off; OAuth redirect URI reviewed but not deployed. |
| Gmail Ingress Pipeline | ⚪ Not Started | Depends on OAuth connector token availability. |
| ERP Schema Migrations | 🟡 In Progress | Ash migration draft authored; waiting for RLS policy review. |
| Device Enrollment Flow | 🟢 Ready | ThunderLink heartbeat instrumentation merged; awaiting Ops dry-run. |
 
## Phase 0: Identity & Business Setup

### Web5 DID Integration
**New Domain**: `Thunderline.ThunderBlock.Identity`

```elixir
# Resources needed:
- BusinessDID (organization identity)
- UserDID (individual identity)  
- DeviceDID (enrolled devices)
- DIDDocument (resolver cache)
```

**Actions**:
1. Add `did_kit` or `web5` dependency for `did:web` resolution
2. Create Ash resources with policies: DID creation, verification, rotation
3. Migration: `business_dids`, `user_dids`, `device_dids` tables
4. Integrate with VaultUser (link user_did ↔ vault_user_id)

**Deliverable**: Business can generate DID, admin creates user DIDs

---

## Phase 1: Thunderblock Provisioning

### 1.1 Enhanced Vault Schema

**Expand ThunderBlock resources**:

```elixir
# ERP Domain Resources (new):
- Contact (CRM contacts/companies)
- Company (CRM organizations)
- Invoice (generated invoices)
- InvoiceLine (line items)
- Inventory (stock management)
- Order (purchase orders)
- Task (ERP task tracking)
- Meeting (calendar events)
- Document (file metadata from Drive)
- Artifact (PAC-generated outputs)
- Journal (audit log entries)

# Enhanced existing:
- Agent (add mailbox_channel_id, acl_policy_id)
- AgentMemory (vector embeddings via pgvector)
- Channel (add channel_type: :mailbox | :ops | :alerts)
```

**RLS Policies** (per resource):
```sql
-- Example for invoices
CREATE POLICY invoice_org_isolation ON invoices
  USING (org_did = current_setting('app.org_did')::text);

CREATE POLICY invoice_user_access ON invoices
  USING (
    user_did = current_setting('app.user_did')::text OR
    EXISTS (SELECT 1 FROM user_roles WHERE ...)
  );
```

**Action**: 
- Generate migrations via `mix ash_postgres.generate_migrations --name add_erp_schema`
- Add policies to each resource
- Create test fixtures

### 1.2 PAC Agent Provisioning

**New**: `Thunderline.ThunderBlock.Agents.PAC` module

```elixir
defmodule Thunderline.ThunderBlock.Agents.PAC do
  @moduledoc """
  Personal AI Controller (PAC) agent provisioning and lifecycle.
  Coordinates ERP operations across Vault resources.
  """
  
  def provision(attrs) do
    # 1. Create Agent record with profile
    # 2. Create mailbox Channel
    # 3. Initialize AgentMemory (vector store)
    # 4. Generate default ACLs via Crown
    # 5. Emit provisioning event
  end
end
```

**Deliverable**: Admin can provision PAC via GraphQL mutation

### 1.3 Device Enrollment (ThunderLink)

**Enhance**: `Thunderline.ThunderLink.Device` module

```elixir
- Device resource: device_did, mtls_cert, tunnel_status, enrolled_at
- Enrollment flow: generate device DID → mTLS cert → Gate tunnel
- Heartbeat: device sends health metrics to Link
```

**Action**: 
- Add device enrollment endpoint to ThunderGate
- Link monitors device connectivity
- Crown issues device-scoped policies

---

## Phase 2: Google Integration

### 2.1 OAuth & Service Principals

**New Domain**: `Thunderline.ThunderGate.Connectors.Google`

**Modules**:
```elixir
Google.OAuth
  - handle_callback/1 (OAuth consent flow)
  - refresh_token/1 (token rotation)
  - revoke_token/1 (instant revocation)

Google.ServiceAccount
  - load_credentials/1 (from Vault KMS or Secret Manager)
  - rotate_key/1 (scheduled via Crown policy)
```

**Vault Storage**:
```elixir
# New resource: OAuthToken
- provider: :google
- scope: text[] (e.g., ["https://www.googleapis.com/auth/drive.readonly"])
- access_token: encrypted
- refresh_token: encrypted (Cloak)
- expires_at: utc_datetime
- org_did: reference
- revoked_at: utc_datetime (nullable)
```

**Crown Policies**:
```json
{
  "id": "google-connector-policy",
  "allows": {
    "scopes": [
      "https://www.googleapis.com/auth/drive.readonly",
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/calendar.readonly",
      "https://www.googleapis.com/auth/bigquery.readonly"
    ],
    "rate_limits": {
      "requests_per_hour": 10000,
      "burst": 100
    },
    "retention_days": 90,
    "redactions": ["email", "phone"]
  },
  "denies": {
    "default": true
  }
}
```

### 2.2 Google API Connectors

**Connectors to Build** (using `Req` per guidelines):

```elixir
Google.Drive
  - list_files/2 (watch for changes via webhooks)
  - download_file/1
  - get_file_metadata/1

Google.Gmail
  - list_messages/2 (with labels)
  - get_message/1
  - send_draft/1

Google.Calendar
  - list_events/2 (upcoming meetings)
  - create_event/1

Google.BigQuery
  - execute_query/1
  - get_table_schema/1

Google.CloudStorage
  - list_objects/1
  - get_object/1

Google.Analytics4
  - get_report/1 (GA4 metrics)
```

**Event Normalization**:
```elixir
# Gate maps Google payloads → Thunderline.Event
Google.Drive.file_created → %Event{
  domain: "thundergate",
  event_type: "ingress.google.drive.file_created",
  payload: %{file_id: ..., name: ..., mime_type: ...},
  source_system: "google_drive",
  occurred_at: ...
}
```

**Action**:
- Create connector modules in `lib/thunderline/thundergate/connectors/google/`
- Add tests with mocked Google API responses
- Wire to ThunderFlow pipelines

### 2.3 Broadway Pipelines (ThunderFlow)

**New Pipelines**:

```elixir
# lib/thunderline/thunderflow/pipelines/google_ingress_pipeline.ex
defmodule Thunderline.Thunderflow.Pipelines.GoogleIngressPipeline do
  use Broadway
  
  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, queue: "ingress.google"},
        stages: 10
      ],
      processors: [
        default: [stages: 50]
      ],
      batchers: [
        realtime: [batch_size: 10, batch_timeout: 1000],
        batch: [batch_size: 100, batch_timeout: 5000],
        maintenance: [batch_size: 500, batch_timeout: 30_000]
      ]
    )
  end
  
  def handle_message(_processor, message, _context) do
    # 1. Crown policy check (scope, rate limit)
    # 2. Normalize payload
    # 3. Route to appropriate batcher
    message
    |> validate_google_event()
    |> classify_routing()
  end
  
  def handle_batch(:realtime, messages, _batch_info, _context) do
    # Handle Gmail messages, Calendar invites immediately
    Enum.each(messages, &process_realtime/1)
  end
end
```

**Routing Logic**:
- `ingress.google.gmail.*` → realtime batcher
- `ingress.google.drive.*` → batch batcher (files)
- `ingress.google.bigquery.*` → maintenance batcher
- Policy violations → DLQ

**Action**:
- Create pipeline modules
- Add to application supervision tree (feature-flagged)
- Wire to Vault actions

---

## Phase 3: ERP Brain (PAC Logic)

### 3.1 PAC Control Loop

**New Module**: `Thunderline.ThunderBolt.PAC.Coordinator`

```elixir
defmodule Thunderline.ThunderBolt.PAC.Coordinator do
  use GenServer
  
  @moduledoc """
  PAC control loop: observes events, applies policies, proposes actions.
  Runs on ThunderBlock.Timing ticks (realtime/batch/maintenance).
  Note: Timer/scheduler functionality consolidated into ThunderBlock.Timing.
  """
  
  def handle_info({:tick, :realtime}, state) do
    # 1. Pull new emails, calendar events from Vault
    # 2. Classify via Bolt skills
    # 3. Propose actions (create task, draft invoice, schedule meeting)
    # 4. Crown policy check
    # 5. Human approval or auto-execute
    # 6. Emit action events to Flow
  end
  
  def handle_info({:tick, :batch}, state) do
    # Hourly: embeddings, doc indexing, inventory reconcile
  end
  
  def handle_info({:tick, :maintenance}, state) do
    # Nightly: snapshots, BigQuery rollups
  end
end
```

**Crown Permit Example**:
```json
{
  "pac_id": "pac-123",
  "permits": [
    {
      "action": "vault.invoices.create",
      "requires_approval": true,
      "max_amount": 10000
    },
    {
      "action": "vault.tasks.create",
      "requires_approval": false
    },
    {
      "action": "gate.gmail.send_draft",
      "requires_approval": true
    }
  ]
}
```

### 3.2 Bolt Skills (ERP Operations)

**New Skills**:

```elixir
# lib/thunderline/thunderbolt/skills/email_classifier.ex
defmodule Thunderline.ThunderBolt.Skills.EmailClassifier do
  use Jido.Action
  
  def run(%{email: email}, _context) do
    # Classify email → :lead | :invoice | :support | :spam
    # Use Bumblebee/Axon for local inference
    {:ok, %{classification: :lead, confidence: 0.92}}
  end
end

# lib/thunderline/thunderbolt/skills/invoice_generator.ex
defmodule Thunderline.ThunderBolt.Skills.InvoiceGenerator do
  def run(%{order: order}, _context) do
    # Generate PDF from template
    # Return artifact + file blob
  end
end

# lib/thunderline/thunderbolt/skills/inventory_reconciler.ex
defmodule Thunderline.ThunderBolt.Skills.InventoryReconciler do
  def run(%{csv_path: path}, _context) do
    # Parse CSV, reconcile with Vault inventory
    # Emit discrepancy events
  end
end
```

**Action**: 
- Create skill modules in `lib/thunderline/thunderbolt/skills/erp/`
- Add tests with sample payloads
- Register skills with Jido dispatcher

### 3.3 GraphQL ERP API (ThunderGrid)

**Expand AshGraphQL Schema**:

```elixir
# lib/thunderline/thunderblock/domain.ex
use AshGraphql, domains: [__MODULE__]

graphql do
  queries do
    get :contact, :read
    list :contacts, :read
    get :invoice, :read
    list :open_invoices, :open_invoices  # custom read action
    list :today_meetings, :today_meetings
    list :untriaged_emails, :untriaged
  end
  
  mutations do
    create :create_contact, :create
    update :approve_invoice, :approve  # triggers PAC action
    create :schedule_meeting, :create
  end
end
```

**Custom Queries**:
```elixir
# In Invoice resource:
read :open_invoices do
  prepare fn query, _context ->
    Ash.Query.filter(query, status == :draft or status == :sent)
  end
end
```

**Action**:
- Define GraphQL schemas for all ERP resources
- Add mutations that trigger Reactor sagas
- Create GraphiQL playground endpoint

---

## Phase 4: Operations & Monitoring

### 4.1 Human-in-the-Loop Approvals

**New Saga**: `Thunderline.ThunderBolt.Sagas.ApprovalSaga`

```elixir
defmodule Thunderline.ThunderBolt.Sagas.ApprovalSaga do
  use Reactor, extensions: [Reactor.Dsl]
  
  input :proposed_action
  input :pac_id
  input :approver_did
  
  step :create_approval_request do
    # Create ApprovalRequest in Vault
    # Emit notification event
  end
  
  step :await_approval, wait_for: :approval_signal do
    # Block until user approves/rejects via GraphQL mutation
    # Timeout after 24 hours
  end
  
  step :execute_action, async?: true do
    # Crown validates permit
    # Flow dispatches action
    # Vault records execution
  end
  
  compensate :rollback_action do
    # If execution fails, mark as failed
    # Notify user
  end
end
```

**Approval UI** (Control Pane):
- LiveView dashboard showing pending approvals
- One-tap approve/reject
- Approval history timeline

### 4.2 SLO Dashboards (Eye Metrics)

**Telemetry Metrics** (via ThunderFlow.Observability):

```elixir
# Data freshness per connector
[:thunderline, :gate, :google, :sync_lag]  # milliseconds

# DLQ rate
[:thunderline, :flow, :dlq, :rate]  # events/sec

# ERP operation latency
[:thunderline, :bolt, :invoice_generation, :duration]  # milliseconds

# Policy denials
[:thunderline, :crown, :denials, :count]

# Device health
[:thunderline, :link, :device, :health_score]
```

**Grafana Dashboards**:
- Connector sync status (green/yellow/red)
- Pipeline throughput + backlog
- PAC action success rate
- Approval SLA compliance

### 4.3 Revocation & Security

**Immediate Revocation**:
```elixir
# Revoke Google connector
ThunderGate.Connectors.Google.OAuth.revoke_token(token_id)

# Revoke device
ThunderLink.Device.offboard(device_did)
# → Kills mTLS tunnel
# → Crown invalidates all device permits
# → Flow drains in-flight events safely
```

**Scheduled Key Rotation** (Oban job):
```elixir
defmodule Thunderline.ThunderGate.Jobs.RotateGoogleKeysWorker do
  use Oban.Worker, queue: :maintenance
  
  def perform(_job) do
    # Rotate service account keys
    # Update Vault KMS
    # Emit rotation event
  end
end
```

---

## MVP Artifacts (5-Day Sprint)

### Sprint Progress Matrix

| Deliverable | Owner | Status | Dependency Notes |
| --- | --- | --- | --- |
| DID resolver baseline | Platform Engineering | 🟡 In Progress | Library selection (Rust NIF vs pure Elixir) pending security review. |
| Drive + Gmail connectors (read-only) | Gate Squad | 🔴 Blocked | Requires OAuth token vaulting once Crown approves connector policy. |
| ERP schema migrations | ThunderBlock | 🟡 In Progress | Ash migrations drafted; RLS policy audit scheduled. |
| Device enrollment flow | Link Squad | 🟢 Ready | Enrollment endpoint merged; Ops dry-run planned Day 2. |
| Gmail ingress pipeline | Flow Squad | ⚪ Not Started | Waiting on OAuth connector readiness. |

### Day 1: Foundation
- [ ] DID integration (did:web resolver)
- [ ] Business DID + admin user DID provisioned
- [ ] Google OAuth callback endpoint
- [ ] Drive + Gmail connectors (read-only)
- [ ] Basic Flow pipeline (ingress.google.*)

### Day 2: Vault & RLS
- [ ] ERP schema migrations (Contact, Invoice, Order, etc.)
- [ ] RLS policies per resource
- [ ] PAC agent provisioning via GraphQL
- [ ] Device enrollment flow
- [ ] Link mesh health checks

### Day 3: Skills & Actions
- [ ] Email classifier skill (Bumblebee)
- [ ] Invoice generator skill (PDF)
- [ ] Doc extractor skill (totals/vendor)
- [ ] Vault actions wired to Flow pipelines
- [ ] Draft invoice flow (end-to-end)

### Day 4: BigQuery & Calendar
- [ ] Calendar connector + events pipeline
- [ ] BigQuery connector + batch pipeline
- [ ] Inventory reconcile job
- [ ] GraphQL ERP queries (openInvoices, todayMeetings)
- [ ] Ops alerts channel

### Day 5: Approvals & Polish
- [ ] ApprovalSaga with human-in-the-loop
- [ ] Limited auto-execute policies (email labeling)
- [ ] Control Pane LiveView (approval dashboard)
- [ ] First live invoice generated + sent
- [ ] SLO dashboard in Grafana

---

## Security Checklist

✅ **Data Isolation**
- Only Gate touches Google APIs
- Only Crown issues permits
- Only Flow publishes cross-domain events
- Only Vault writes durable state

✅ **Minimal Scopes**
- OAuth scopes limited to read-only initially
- Service account keys rotated monthly
- Connector-specific encryption keys

✅ **PII Controls**
- Redaction rules in Crown policies
- Contact email/phone hashing optional
- Separate KMS keys per connector

✅ **Audit Trail**
- Every PAC action → Event + Journal entry
- Immutable audit log (AshEvents)
- Retention policies enforced

✅ **Revocation**
- Instant token revocation (Gate)
- Device offboarding (Link + Crown)
- Cached tokens invalidated
- Pipelines drain safely

---

## Open Questions / Decisions Needed

1. **Web5 Library**: Use `did_kit` (Rust NIF) or pure Elixir `web5_ex`?
2. **Vector Store**: pgvector vs. separate Qdrant/Weaviate for AgentMemory?
3. **PDF Generation**: Use `puppeteer_pdf` (headless Chrome) or Elixir `gutenex`?
4. **A2A Protocol**: Implement Agent2Agent spec for Vertex collaboration?
5. **UI Framework**: Keep Phoenix LiveView or add React Control Pane?
6. **Deployment**: Docker Compose (dev) + Nomad/K8s (prod)?

---

## Success Metrics

### Technical
- **Connector Uptime**: 99.5% (Gate health checks)
- **Pipeline Throughput**: 10k events/hour (Flow capacity)
- **Policy Latency**: <50ms (Crown permit checks)
- **Vault Query P95**: <100ms (RLS overhead)
- **DLQ Rate**: <0.1% (data quality)

### Business
- **Time-to-Invoice**: <5 minutes (PO → PDF)
- **Approval SLA**: <4 hours (human response)
- **PAC Accuracy**: >95% (email classification)
- **User Satisfaction**: >4.5/5 (Control Pane UX)
- **Cost per Transaction**: <$0.01 (compute efficiency)

---

### Current Sprint Commitments (Week 42)

1. Finalize OAuth connector policy packet for Crown sign-off (Gate Squad, due Day 2).
2. Deliver Ash RLS review for ERP schema migrations and capture approvals in runbook (ThunderBlock, due Day 3).
3. Conduct device enrollment dry-run and publish heartbeat telemetry snapshot (Link Squad, due Day 3).
4. Prepare libcluster load harness execution plan aligning with Flow pipeline go/no-go (Flow Squad, due Day 4).

## Next Steps

**Immediate Actions** (this sprint):
1. ✅ Complete vault security tests (14 remaining failures)
2. ⬜ Add DID integration (did:web resolver)
3. ⬜ Create ERP schema migrations
4. ⬜ Build Google OAuth connector
5. ⬜ Wire first Flow pipeline (Gmail)

**Follow-on Work** (next sprint):
- PAC control loop + Reactor saga
- Bolt ERP skills
- GraphQL ERP API expansion
- Control Pane LiveView
- SLO dashboards

---

**Clarus ordo, celer actio** ⚡️
