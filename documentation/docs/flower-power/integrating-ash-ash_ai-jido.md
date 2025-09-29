# Integrating Ash, ash_ai, and Jido in Thunderline’s Training Pipeline

This guide documents how Thunderline models domain data using Ash, exposes governance-approved actions as MCP tools via ash_ai under the Thundercrown domain, ingests telemetry with Broadway → JSONL for Cerebros, orchestrates NAS with Ash resources and Jido plans under policy guards, and maps persistent state to PAC/ECSx runtime systems.

Audience
- Domain engineers and platform maintainers working across Thundercrown (governance), Thunderflow (events), Thunderbolt (ML/execution), Thunderblock (storage), Thundergate (auth), Thunderlink (realtime), and Thundergrid (spatial).

Scope
- Policy-first Ash resources with deny-by-default
- ash_ai tool exposure as MCP under Thundercrown
- Telemetry ingestion with Broadway → JSONL (+ OTel)
- NAS lifecycle resources (ModelRun/Trial/Artifact)
- Jido cognitive loop under Ash policies
- PAC/ECSx runtime sync + 3D CA visualization
- Observability and security integration

Prerequisites
- Review:
  - documentation/docs/flower-power/{architecture,prereqs,configuration,contracts,observability,security}.md
  - lib/thunderline/thundercrown/{domain.ex,resources/*}
  - lib/thunderline_web/router.ex (MCP scope), Thundergate auth resources

## 1) Policy‑first Ash resources

Deny-by-default posture through Ash.Policy.Authorizer and field-level policies. Example (Thunderbit-like agent):

```elixir
defmodule Thunderline.Thunderbolt.Resources.Thunderbit do
  use Ash.Resource,
    extensions: [AshPostgres.DataLayer, AshPolicyAuthorizer],
    authorizers: [Ash.Policy.Authorizer],
    domain: Thunderline.Thunderbolt.Domain

  attributes do
    uuid_primary_key :id
    attribute :behavior_type, :atom, allow_nil?: false
    attribute :status, :atom, default: :dormant
    attribute :energy, :integer, default: 100
    attribute :secret_key, :string, sensitive?: true
  end

  actions do
    create :create, accept: [:behavior_type]
    update :activate, changes: [set_attribute(:status, :active)]
    destroy :delete
    read :read
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :system)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  field_policies do
    field_policy :secret_key do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end
```

Notes
- Any non-specified action is denied.
- If any field_policies exist, fields without explicit policy are masked.
- Tag sensitive attributes as `sensitive?: true` for extra safety.

## 2) Exposing Ash actions as MCP tools with ash_ai (Thundercrown)

Thundercrown is the governance/orchestration domain that owns MCP integration.

- Domain: lib/thunderline/thundercrown/domain.ex (already present)
  - Uses `AshAi` and exposes curated tools:

```elixir
defmodule Thunderline.Thundercrown.Domain do
  use Ash.Domain, extensions: [AshAi]

  resources do
    resource Thunderline.Thundercrown.Resources.OrchestrationUI
    resource Thunderline.Thundercrown.Resources.AgentRunner
  end

  tools do
    # Governance-approved tool
    tool :run_agent, Thunderline.Thundercrown.Resources.AgentRunner, :run
  end
end
```

- Router scope: lib/thunderline_web/router.ex (already present)
  - The MCP router is mounted under `/mcp` with an auth-aware pipeline:

```elixir
scope "/mcp" do
  pipe_through [:mcp] # includes AshAuthentication.Strategy.ApiKey.Plug (optional strict)
  forward "/", AshAi.Mcp.Router,
    tools: [:run_agent],
    protocol_version_statement: System.get_env("MCP_PROTOCOL_VERSION", "2024-11-05"),
    otp_app: :thunderline
end
```

- Actor identity:
  - The `:mcp` pipeline should authenticate the actor (API key or session token) to enforce Ash policies.
  - Ash policies then gate tool invocation per user/tenant.

## 3) Telemetry ingestion with Broadway → JSONL

Ingest user/system telemetry with backpressure, batching, and OTel spans.

```elixir
defmodule Thunderline.TelemetryPipeline do
  use Broadway
  alias Broadway.Message

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        # For dev; in prod use Kafka/RabbitMQ producers
        module: {Broadway.Phoenix.PubSub.Producer, name: :event_bus, subscription: "user:telemetry"}
      ],
      processors: [default: [concurrency: 4]],
      batchers: [default: [batch_size: 50, batch_timeout: 500]]
    )
  end

  def handle_message(_, %Message{data: event} = msg, _) do
    event
    |> sanitize_event()
    |> Jason.encode!()
    |> Kernel.<>("\n")
    |> then(&File.write!("cerebros_feed.jsonl", &1, [:append]))

    msg
  end

  defp sanitize_event(ev), do: Map.drop(ev, ["email", "auth_token", "ip"])
end
```

- Add in your Application start:
```elixir
:ok = OpentelemetryBroadway.setup()
```

- Red-team guidance:
  - Validate payloads, drop malicious inputs, and mask PII before persistence.

## 4) NAS resources: ModelRun, Trial, Artifact (Thunderbolt)

Represent NAS lifecycle declaratively:

```elixir
defmodule Thunderline.Thunderbolt.Resources.ModelRun do
  use Ash.Resource, extensions: [AshPostgres.DataLayer, AshPolicyAuthorizer],
    domain: Thunderline.Thunderbolt.Domain

  attributes do
    uuid_primary_key :id
    attribute :status, :atom, default: :pending
    attribute :started_at, :utc_datetime
    attribute :ended_at, :utc_datetime
  end

  relationships do
    has_many :trials, Thunderline.Thunderbolt.Resources.Trial
    has_many :artifacts, Thunderline.Thunderbolt.Resources.Artifact
  end

  actions do
    create :start_run do
      description "Kick off a new NAS run"
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :record_trial_result do
      accept [:trial_id, :metrics]
      change manage_relationship(:trials, type: :append, resource: Thunderline.Thunderbolt.Resources.Trial)
    end

    update :finalize_run do
      change set_attribute(:status, :completed)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
    end
  end
end
```

- A runner (Oban job or Jido plan) reads DatasetSpec, creates a ModelRun, spawns Trials, records results, and finalizes.

> ℹ️ **Implementation delta (Sep 2025):** The production `ModelRun` resource now enforces a non-null, unique `run_id` and persists bridge context in JSON columns (`bridge_payload`, `bridge_result`) so the Cerebros bridge can replay requests idempotently. Any new persistence logic or migrations must respect these defaults and avoid inserting runs without a stable `run_id`.

## 5) Jido cognitive loop under Ash policies

Wrap the agent cycle with Ash actions. Each step invokes Jido workflows but is policy-guarded.

```elixir
defmodule Thunderline.Thundercrown.Resources.AgentWorkflow do
  use Ash.Resource,
    extensions: [AshPostgres.DataLayer, AshPolicyAuthorizer],
    domain: Thunderline.Thundercrown.Domain

  relationships do
    belongs_to :agent, Thunderline.Thunderbolt.Resources.Thunderbit
  end

  actions do
    update :observe do
      change fn changeset, _ ->
        agent_id = Ash.Changeset.get_argument(changeset, :agent_id)
        {:ok, data} = MyApp.AgentPlan.run_observe(agent_id: agent_id)
        Ash.Changeset.manage_relationship(changeset, :observations, data, type: :append)
      end
    end
    update :decide do
      change fn changeset, _ ->
        agent_id = Ash.Changeset.get_argument(changeset, :agent_id)
        {:ok, decision} = MyApp.AgentPlan.run_decide(agent_id: agent_id)
        Ash.Changeset.set_attribute(changeset, :last_decision, decision)
      end
    end
    update :act do
      change fn changeset, _ ->
        agent_id = Ash.Changeset.get_argument(changeset, :agent_id)
        _ = MyApp.AgentPlan.run_act(agent_id: agent_id)
        changeset
      end
    end
    update :train do
      change fn changeset, _ ->
        agent_id = Ash.Changeset.get_argument(changeset, :agent_id)
        _ = MyApp.AgentPlan.run_train(agent_id: agent_id)
        changeset
      end
    end
  end

  policies do
    policy action_type(:update) do
      authorize_if expr(agent_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end
```

- Trigger on a tick via Oban/Broadway timers while preserving the same authorizations.

## 6) PACs / ECSx mapping and 3D CA

- Map resource attributes to ECSx components (e.g., BehaviorType, Energy, Position).
- Use an ECSx.Manager to sync Ash state into runtime entities; implement systems like EnergyDecay.
- Publish state_update events; a visualizer maps them into a 3D CA (ThunderCell engine).

## 7) Observability

- Use the span model and metric catalog in observability.md.
- Add `federation_id`, `round_num`, `client_id`, and `tenant` labels for correlation.
- Surface Broadway and Oban spans (setup done in Application).

## 8) Security

- Enforce mTLS for Runner channels and JWS-signed job manifests.
- Tenant isolation via RLS; enforce deny-by-default in Ash policies.
- DP/secure agg toggles in FederationSpec (implemented on the client/strategy).

## 9) Acceptance checks

- ash_ai tools are visible at `/mcp` and enforce actor policies.
- Broadway JSONL pipeline works with OTel spans; PII masked.
- NAS lifecycle actions produce proper rows and events.
- Jido loop only runs for authorized actors and logs spans.
- PAC/ECSx visualization receives events and renders cell updates.

References
- Thundercrown MCP tools: lib/thunderline/thundercrown/domain.ex
- MCP router: lib/thunderline_web/router.ex (scope "/mcp")
- Flower Power deployment and ops: documentation/docs/flower-power/*
- Security, observability, and contracts: see respective docs in this folder.
