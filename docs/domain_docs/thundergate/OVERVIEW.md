# ThunderGate Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thundergate/domain.ex`  
**Vertex Position**: Control Plane Ring — Security Gateway

## Purpose

ThunderGate is the **security and policy enforcement domain** of Thunderline:
- Authentication and authorization
- Rate limiting and API boundary controls
- Policy enforcement and decision frameworks
- Security monitoring and observability
- External API integration and adaptation
- Cross-realm identity management and federation

**Design Principle**: "Gate permits" — single entry point for all security decisions.

## Domain Extensions

```elixir
use Ash.Domain, extensions: [AshAdmin.Domain]
```

- **AshAdmin** — Admin dashboard enabled

## Directory Structure

```
lib/thunderline/thundergate/
├── domain.ex                  # Main Ash domain (18 resources)
├── supervisor.ex              # Domain supervisor
├── actor_context.ex           # Actor context utilities
├── magika.ex                  # Magic auth utilities
├── self_test.ex               # Self-testing utilities
├── service_registry.ex        # Service registry root
├── thunder_bridge.ex          # Bridge module
├── ups.ex                     # UPS utilities
├── authentication/            # Auth helpers
│   └── magic_link_sender.ex   # Magic link email sender
├── plug/                      # Phoenix plugs
│   └── actor_context_plug.ex  # Actor context plug
├── policies/                  # Ash policy checks
│   ├── admin_access.ex        # Admin access check
│   └── presence.ex            # Presence check
├── rate_limiting/             # Rate limiting subsystem
│   ├── bucket.ex              # Token bucket
│   ├── policy.ex              # Rate limit policy
│   └── rate_limiter.ex        # Rate limiter GenServer
├── resources/                 # Core Ash resources (19 files)
│   ├── user.ex, token.ex, api_key.ex     # Auth resources
│   ├── external_service.ex, data_adapter.ex  # Integration
│   ├── federated_realm.ex, realm_identity.ex, federated_message.ex  # Federation
│   ├── decision_framework.ex, policy_rule.ex  # Policy (ex-ThunderStone)
│   ├── alert_rule.ex, audit_log.ex, error_log.ex  # Monitoring (ex-ThunderEye)
│   ├── health_check.ex, performance_trace.ex
│   ├── system_action.ex, system_metric.ex
│   └── thunderbit_monitor.ex, thunderbolt_monitor.ex
├── service_registry/          # Service discovery
│   ├── service.ex             # Service Ash resource (not in domain!)
│   └── health_monitor.ex      # Health monitoring
└── thunderwatch/              # Monitoring subsystem
    ├── manager.ex             # Watch manager
    └── supervisor.ex          # Watch supervisor
```

## Registered Ash Resources

### Main Domain (18 resources)

#### Authentication Resources
| Resource | Module | File |
|----------|--------|------|
| User | `Thunderline.Thundergate.Resources.User` | resources/user.ex |
| Token | `Thunderline.Thundergate.Resources.Token` | resources/token.ex |
| ApiKey | `Thunderline.Thundergate.Resources.ApiKey` | resources/api_key.ex |

**User Resource Extensions**:
```elixir
extensions: [AshAuthentication]

authentication do
  strategies do
    magic_link :magic_link do
      identity_field :email
      sender Thunderline.Thundergate.Authentication.MagicLinkSender
    end
    
    api_key do
      api_key_relationship :valid_api_keys
      api_key_hash_attribute :api_key_hash
    end
  end
  
  tokens do
    enabled? true
    token_resource Thunderline.Thundergate.Resources.Token
    signing_secret Thunderline.Secrets
    store_all_tokens? true
  end
end
```

#### External Integration Resources
| Resource | Module | File |
|----------|--------|------|
| ExternalService | `Thunderline.Thundergate.Resources.ExternalService` | resources/external_service.ex |
| DataAdapter | `Thunderline.Thundergate.Resources.DataAdapter` | resources/data_adapter.ex |

#### Federation Resources
| Resource | Module | File |
|----------|--------|------|
| FederatedRealm | `Thunderline.Thundergate.Resources.FederatedRealm` | resources/federated_realm.ex |
| RealmIdentity | `Thunderline.Thundergate.Resources.RealmIdentity` | resources/realm_identity.ex |
| FederatedMessage | `Thunderline.Thundergate.Resources.FederatedMessage` | resources/federated_message.ex |

#### Policy Enforcement (ex-ThunderStone)
| Resource | Module | File |
|----------|--------|------|
| DecisionFramework | `Thunderline.Thundergate.Resources.DecisionFramework` | resources/decision_framework.ex |
| PolicyRule | `Thunderline.Thundergate.Resources.PolicyRule` | resources/policy_rule.ex |

#### Security Monitoring (ex-ThunderEye)
| Resource | Module | File |
|----------|--------|------|
| AlertRule | `Thunderline.Thundergate.Resources.AlertRule` | resources/alert_rule.ex |
| AuditLog | `Thunderline.Thundergate.Resources.AuditLog` | resources/audit_log.ex |
| ErrorLog | `Thunderline.Thundergate.Resources.ErrorLog` | resources/error_log.ex |
| HealthCheck | `Thunderline.Thundergate.Resources.HealthCheck` | resources/health_check.ex |
| PerformanceTrace | `Thunderline.Thundergate.Resources.PerformanceTrace` | resources/performance_trace.ex |
| SystemAction | `Thunderline.Thundergate.Resources.SystemAction` | resources/system_action.ex |
| SystemMetric | `Thunderline.Thundergate.Resources.SystemMetric` | resources/system_metric.ex |
| ThunderbitMonitor | `Thunderline.Thundergate.Resources.ThunderbitMonitor` | resources/thunderbit_monitor.ex |
| ThunderboltMonitor | `Thunderline.Thundergate.Resources.ThunderboltMonitor` | resources/thunderbolt_monitor.ex |

### Unregistered Ash Resource

| Resource | Module | File | Note |
|----------|--------|------|------|
| Service | `Thunderline.Thundergate.ServiceRegistry.Service` | service_registry/service.ex | **NOT in domain!** |

## Authentication Strategy

- **Magic Link** — Primary passwordless auth via email
- **API Key** — For programmatic access
- **JWT Tokens** — Session management via AshAuthentication

## Policy Checks

| Check | Module | Purpose |
|-------|--------|---------|
| AdminAccess | `Thunderline.Thundergate.Policies.AdminAccess` | Admin role verification |
| Presence | `Thunderline.Thundergate.Policies.Presence` | Online/presence verification |

## Rate Limiting

| Module | Purpose |
|--------|---------|
| Bucket | Token bucket implementation |
| Policy | Rate limit policy definition |
| RateLimiter | GenServer for rate limit enforcement |

## Thunderwatch Monitoring

| Module | Purpose |
|--------|---------|
| Manager | Centralized watch management |
| Supervisor | Watch process supervision |

## Service Registry

| Module | Purpose |
|--------|---------|
| Service | Service definition resource (Ash) |
| HealthMonitor | Service health monitoring |

## Plugs

| Plug | Purpose |
|------|---------|
| ActorContextPlug | Sets actor context on conn for auth |

## Consolidated History

ThunderGate consolidated responsibilities from:
- **ThunderStone** → Policy management (DecisionFramework, PolicyRule)
- **ThunderEye** → Security monitoring (AlertRule, AuditLog, ErrorLog, etc.)

## Known Issues & TODOs

### 1. Service Resource Not Registered
`Thunderline.Thundergate.ServiceRegistry.Service` is an Ash resource but NOT registered in the domain.
Either register it or verify it's intentionally standalone.

### 2. Commented Out Resources
```elixir
# Commented out until implementation is available
# resource Thundergate.Resources.WebhookEndpoint
# resource Thundergate.Resources.SyncJob
# resource Thundergate.Resources.FederationBridge
```

### 3. Password Auth Disabled
User resource has magic_link and api_key auth, but password-based auth is disabled.
Legacy `hashed_password` field retained for existing rows.

### 4. Policy Default Forbid
User resource has `forbid_if always()` default policy — all access blocked except auth.

## Telemetry Events

- `[:thunderline, :thundergate, :auth, :success|:failure]`
- `[:thunderline, :thundergate, :rate_limit, :allowed|:rejected]`
- `[:thunderline, :thundergate, :policy, :evaluated]`
- `[:thunderline, :thundergate, :health_check, :result]`

## Development Priorities

1. **Service Registration** — Add Service resource to domain or document why standalone
2. **Implement WebhookEndpoint** — Enable webhook integrations
3. **Federation Maturation** — Complete federation resource implementations
4. **Password Auth** — Consider enabling if needed for local dev

## Related Domains

- **ThunderLink** — Communication uses Gate for auth decisions
- **ThunderBlock** — Persistence of auth data
- **ThunderCrown** — Higher-level governance (Gate enforces Crown's policies)
- **ThunderFlow** — Event publication for audit logs
