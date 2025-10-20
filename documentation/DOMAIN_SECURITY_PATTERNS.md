# Domain Security Patterns

**Purpose**: Standardized authorization policies for Thunderline Ash resources  
**Status**: ✅ ACTIVE - AUDIT-01 Implementation Guide  
**Last Updated**: 2025-10-20  
**Owners**: Renegade-S (Security) + Shadow-Sec (Audit)

---

## 🎯 Executive Summary

This document defines the **mandatory** authorization patterns for all Ash resources in Thunderline. Every resource **MUST** implement proper policies using `Ash.Policy.Authorizer` with tenant isolation and role-based access control (RBAC).

**Zero Tolerance**: `authorize_if always()` placeholders are **FORBIDDEN** in production code except for:
1. AshAuthentication interaction bypass (user registration/login flows)
2. System maintenance operations with explicit `actor(:role) == :system` guards

**Audit Status** (AUDIT-01):
- 📊 **Total Resources**: 116 Ash resources across 5 domains
- 🔴 **Active Violations**: 28 resources with `authorize_if always()` (24%)
- 🟢 **Target State**: 100% policy compliance by end of Week 1

---

## 📐 Core Security Model

### 1. Multi-Tenancy Strategy

Thunderline uses **attribute-based multi-tenancy** for data isolation:

```elixir
multitenancy do
  strategy :attribute
  attribute :tenant_id
  global? false
end
```

**Tenant Enforcement Rules**:
- ✅ **ALWAYS** filter by `tenant_id == ^actor(:tenant_id)` for user-owned data
- ✅ **NEVER** allow cross-tenant access without explicit `role == :system` check
- ✅ **ALWAYS** set `tenant_id` automatically from actor context on create

**Global Resources** (`:global? true`):
- System configuration resources (PolicyRule, SystemAction)
- Read-only reference data (no tenant isolation needed)
- System metrics aggregated across tenants

### 2. Actor Context Structure

Every Ash action receives an actor map with authentication/authorization context:

```elixir
%{
  id: "uuid-of-authenticated-user",
  email: "user@example.com",
  tenant_id: "uuid-of-tenant",
  role: :user | :admin | :system,
  scope: :tenant | :global | :maintenance,
  permissions: [:read, :write, :manage] # RBAC permissions
}
```

**Actor Sources**:
- 🔐 **Authenticated Users**: Via AshAuthentication magic link → actor loaded from User resource
- 🤖 **System Processes**: Event processors, Oban jobs → actor = `%{role: :system, scope: :maintenance}`
- 🔧 **Admin Operations**: Console, admin UI → actor with `:admin` role

### 3. Role-Based Access Control (RBAC)

Three primary roles with escalating privileges:

**:user** (Default)
- Read/write own tenant data
- Cannot access system resources
- Limited to tenant scope

**:admin** (Elevated)
- Read/write within tenant
- Manage tenant configuration
- View (but not modify) cross-tenant aggregates

**:system** (Full Trust)
- Bypass tenant isolation when `scope == :maintenance`
- Execute background jobs, event processing
- System-level resource management
- **MUST** be used sparingly with explicit scope checks

---

## 🛡️ Standard Policy Patterns

### Pattern 1: User-Owned Tenant Data

**Use For**: Resources owned by users within a tenant (Messages, Channels, VaultExperiences, etc.)

```elixir
policies do
  # Bypass for authentication flows only
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  # Create: User can create in own tenant
  policy action_type(:create) do
    authorize_if expr(^actor(:tenant_id) != nil)
  end

  # Read: Tenant isolation
  policy action_type(:read) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :admin and ^actor(:scope) == :global)
  end

  # Update: Own tenant + specific ownership check
  policy action_type(:update) do
    authorize_if expr(tenant_id == ^actor(:tenant_id) and user_id == ^actor(:id))
    authorize_if expr(^actor(:role) == :admin and tenant_id == ^actor(:tenant_id))
  end

  # Destroy: Own tenant + ownership or admin
  policy action_type(:destroy) do
    authorize_if expr(tenant_id == ^actor(:tenant_id) and user_id == ^actor(:id))
    authorize_if expr(^actor(:role) == :admin and tenant_id == ^actor(:tenant_id))
  end

  # System maintenance bypass
  policy action(:cleanup_old_records) do
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
  end
end
```

**Key Points**:
- Default deny (no catch-all `authorize_if always()`)
- Tenant isolation via `tenant_id == ^actor(:tenant_id)`
- Admin can manage within their tenant
- System role requires explicit scope check

### Pattern 2: System Configuration Resources

**Use For**: Global resources like PolicyRule, SystemAction, DecisionFramework

```elixir
policies do
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  # Read: All authenticated users
  policy action_type(:read) do
    authorize_if expr(^actor(:id) != nil)
  end

  # Write: Admin or system only
  policy action_type([:create, :update, :destroy]) do
    authorize_if expr(^actor(:role) in [:admin, :system])
  end

  # Specific system actions
  policy action(:apply_policy) do
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
  end
end
```

**Key Points**:
- No tenant isolation (global resources)
- Read allowed for authenticated users
- Write requires elevated privileges
- Dangerous actions require system role + scope

### Pattern 3: Graph/Lineage Resources

**Use For**: Knowledge graphs, lineage edges, relationship data

```elixir
policies do
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  # Create: Tenant-scoped or system
  policy action_type(:create) do
    authorize_if expr(^actor(:tenant_id) != nil)
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
  end

  # Read: Tenant isolation with traversal permissions
  policy action_type(:read) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :admin and ^actor(:scope) == :global)
  end

  # Update: Tenant + quality score check
  policy action_type(:update) do
    authorize_if expr(
      tenant_id == ^actor(:tenant_id) and
      verification_status != :locked
    )
  end

  # Graph operations: Tenant + relationship checks
  policy action(:add_relationship) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
  end

  policy action(:traverse_graph) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :system)
  end
end
```

**Key Points**:
- Tenant isolation for ownership
- Read access for graph traversal within tenant
- System can traverse cross-tenant for analytics
- Prevent modification of locked/verified nodes

### Pattern 4: Audit/Observability Resources

**Use For**: AuditLog, SystemMetric, PerformanceTrace, ErrorLog

```elixir
policies do
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  # Create: System only (logs created by system processes)
  policy action_type(:create) do
    authorize_if expr(^actor(:role) == :system)
  end

  # Read: Tenant isolation for audit logs
  policy action_type(:read) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :admin and ^actor(:scope) == :global)
  end

  # Update/Destroy: Forbidden (append-only audit trail)
  policy action_type([:update, :destroy]) do
    forbid_if always()
  end

  # System maintenance: Allow cleanup of old logs
  policy action(:cleanup_old_logs) do
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
  end
end
```

**Key Points**:
- Append-only (no updates/deletes)
- System creates logs
- Users/admins read within tenant
- Cleanup requires system role + maintenance scope

### Pattern 5: ML/Analytics Resources

**Use For**: ModelRun, ModelTrial, UpmTrainer, LaneConfiguration

```elixir
policies do
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  # Create: System or admin within tenant
  policy action_type(:create) do
    authorize_if expr(
      ^actor(:tenant_id) != nil and
      ^actor(:role) in [:admin, :system]
    )
  end

  # Read: Tenant isolation
  policy action_type(:read) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :global)
  end

  # Update: Admin or system for configuration
  policy action_type(:update) do
    authorize_if expr(
      tenant_id == ^actor(:tenant_id) and
      ^actor(:role) in [:admin, :system]
    )
  end

  # Training/execution: System only
  policy action(:execute_training) do
    authorize_if expr(^actor(:role) == :system)
  end
end
```

**Key Points**:
- Tenant isolation for ownership
- Admin can configure within tenant
- System executes training/analytics jobs
- Cross-tenant analytics require system role

---

## 🚨 Anti-Patterns (FORBIDDEN)

### ❌ Blanket Authorization

```elixir
# NEVER DO THIS
policies do
  policy always() do
    authorize_if always()
  end
end
```

**Why**: Bypasses all authorization checks, breaks tenant isolation, security nightmare.

### ❌ Commented-Out Policies

```elixir
# NEVER DO THIS
# policies do
#   policy action_type(:read) do
#     authorize_if expr(tenant_id == ^actor(:tenant_id))
#   end
# end
```

**Why**: Indicates incomplete implementation, resource is **UNPROTECTED**.

### ❌ Missing Tenant Checks

```elixir
# NEVER DO THIS
policies do
  policy action_type(:read) do
    authorize_if expr(^actor(:id) != nil)  # Missing tenant_id check!
  end
end
```

**Why**: Authenticated users can access all tenants' data.

### ❌ Overly Permissive System Role

```elixir
# NEVER DO THIS
policies do
  policy always() do
    authorize_if expr(^actor(:role) == :system)  # No scope check!
  end
end
```

**Why**: Any system process can modify any data. Add scope checks: `^actor(:scope) == :maintenance`

---

## 📋 Resource-by-Resource Audit Checklist

### ThunderBlock Domain (Persistence)

| Resource | Status | Tenant? | Pattern | Notes |
|----------|--------|---------|---------|-------|
| VaultUser | 🟢 COMPLIANT | No | Auth | Uses AshAuthentication bypass correctly |
| VaultUserToken | 🔴 VIOLATION | No | Auth | Has `authorize_if always()` |
| VaultKnowledgeNode | 🔴 COMMENTED | Yes | Graph | Entire policies block commented out |
| VaultMemoryRecord | 🔴 VIOLATION | Yes | User-Owned | Has `authorize_if always()` |
| VaultExperience | 🔴 VIOLATION | Yes | User-Owned | Has `authorize_if always()` |
| VaultAction | 🔴 COMMENTED | Yes | User-Owned | Policies commented out |
| VaultDecision | 🔴 COMMENTED | Yes | User-Owned | Policies commented out |
| VaultAgent | 🔴 COMMENTED | Yes | User-Owned | Policies commented out |
| VaultEmbeddingVector | 🔴 VIOLATION | Yes | Graph | Has `authorize_if always()` |
| VaultCacheEntry | 🔴 COMMENTED | Yes | System | Policies commented out |
| VaultQueryOptimization | 🔴 VIOLATION | Yes | System | Has `authorize_if always()` |
| SupervisionTree | 🔴 COMMENTED | Yes | System | Policies commented out |
| ZoneContainer | 🔴 COMMENTED | Yes | System | Policies commented out |
| PacHome | 🔴 COMMENTED | Yes | User-Owned | Policies commented out |

### ThunderGate Domain (AuthN/AuthZ)

| Resource | Status | Tenant? | Pattern | Notes |
|----------|--------|---------|---------|-------|
| User | 🟢 COMPLIANT | No | Auth | Proper AshAuth bypass + forbid default |
| Token | 🔴 VIOLATION | No | Auth | Has `authorize_if always()` |
| PolicyRule | 🔴 VIOLATION | No | System | Has `authorize_if always()` |
| SystemAction | 🔴 VIOLATION | No | System | Has `authorize_if always()` |
| DecisionFramework | 🔴 VIOLATION | No | System | Has `authorize_if always()` |
| AuditLog | 🔴 COMMENTED | Yes | Audit | Policies commented out |

### ThunderFlow Domain (Events & Lineage)

| Resource | Status | Tenant? | Pattern | Notes |
|----------|--------|---------|---------|-------|
| Lineage.Edge | 🟢 COMPLIANT | Yes | Graph | Proper tenant isolation + system bypass |

### ThunderBolt Domain (ML/Analytics)

| Resource | Status | Tenant? | Pattern | Notes |
|----------|--------|---------|---------|-------|
| ModelRun | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| ModelTrial | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| UpmTrainer | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| UpmAdapter | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| UpmSnapshot | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| UpmDriftWindow | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| LaneConfiguration | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| LaneConsensusRun | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| LaneTelemetrySnapshot | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| LaneRuleOracle | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| LanePerformanceMetric | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| TrainingSlice | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |
| MoE.Expert | 🔴 VIOLATION | Yes | ML | Has `authorize_if always()` |

### ThunderGrid Domain (Spatial)

| Resource | Status | Tenant? | Pattern | Notes |
|----------|--------|---------|---------|-------|
| GridZone | 🔴 VIOLATION | Yes | Spatial | Has `authorize_if always()` |
| GridResource | 🔴 VIOLATION | Yes | Spatial | Has `authorize_if always()` |
| SpatialCoordinate | 🔴 COMMENTED | Yes | Spatial | Policies commented out |
| ZoneBoundary | 🔴 COMMENTED | Yes | Spatial | Policies commented out |
| Zone | 🔴 COMMENTED | Yes | Spatial | Policies commented out |
| ZoneEvent | 🔴 COMMENTED | Yes | Spatial | Policies commented out |

### ThunderCom/ThunderLink Domains (Federation)

| Resource | Status | Tenant? | Pattern | Notes |
|----------|--------|---------|---------|-------|
| Community | 🔴 COMMENTED | Yes | User-Owned | Policies commented out (both domains) |
| Channel | 🔴 COMMENTED | Yes | User-Owned | Policies commented out (both domains) |
| Message | 🔴 COMMENTED | Yes | User-Owned | Policies commented out (both domains) |
| Role | 🔴 COMMENTED | Yes | User-Owned | Policies commented out (both domains) |
| FederationSocket | 🔴 COMMENTED | Yes | System | Policies commented out (both domains) |

**Summary Statistics**:
- 🔴 **28 Resources with Violations** (24% of 116 total)
- 🟢 **2 Compliant Resources** (User, Lineage.Edge)
- ⚪ **86 Resources Not Audited Yet** (need systematic review)

---

## 🔧 Implementation Guide

### Step 1: Assess Resource Risk

Categorize each resource by **data sensitivity** and **blast radius**:

**🔴 CRITICAL (Fix First)**:
- Authentication: User, Token
- Authorization: PolicyRule, SystemAction
- Audit: AuditLog, SystemMetric
- User Data: VaultExperience, VaultMemoryRecord, VaultDecision

**🟡 HIGH (Fix Week 1)**:
- Knowledge: VaultKnowledgeNode, VaultAction
- Federation: Community, Channel, Message
- ML Config: ModelRun, LaneConfiguration

**🟢 MEDIUM (Fix Week 2)**:
- ML Telemetry: ModelTrial, LaneTelemetrySnapshot
- Spatial: GridZone, Zone
- Caching: VaultCacheEntry, VaultQueryOptimization

### Step 2: Uncomment and Fix

For resources with commented-out policies:

1. **Uncomment** the policies block
2. **Replace** `authorize_if always()` with proper tenant checks
3. **Add** system bypass with scope guard
4. **Test** with integration tests

Example fix for `VaultKnowledgeNode`:

```elixir
# BEFORE (COMMENTED OUT)
# policies do
#   policy always() do
#     authorize_if always()
#   end
# end

# AFTER (PROPER TENANT ISOLATION)
policies do
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  policy action_type(:create) do
    authorize_if expr(^actor(:tenant_id) != nil)
  end

  policy action_type(:read) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :admin and ^actor(:scope) == :global)
  end

  policy action_type(:update) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
    authorize_if expr(^actor(:role) == :admin and tenant_id == ^actor(:tenant_id))
  end

  policy action_type(:destroy) do
    authorize_if expr(tenant_id == ^actor(:tenant_id) and ^actor(:role) == :admin)
  end

  # Graph operations
  policy action(:add_relationship) do
    authorize_if expr(tenant_id == ^actor(:tenant_id))
  end

  policy action(:consolidate_knowledge) do
    authorize_if expr(tenant_id == ^actor(:tenant_id) and ^actor(:role) == :admin)
  end

  # System maintenance
  policy action(:recalculate_metrics) do
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
  end

  policy action(:cleanup_deprecated) do
    authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
  end
end
```

### Step 3: Add Tests

For each fixed resource, add authorization tests:

```elixir
defmodule Thunderline.Thunderblock.VaultKnowledgeNodeTest do
  use Thunderline.DataCase

  describe "authorization" do
    setup do
      tenant1 = Ash.UUID.generate()
      tenant2 = Ash.UUID.generate()
      
      user1 = %{id: Ash.UUID.generate(), tenant_id: tenant1, role: :user}
      user2 = %{id: Ash.UUID.generate(), tenant_id: tenant2, role: :user}
      admin = %{id: Ash.UUID.generate(), tenant_id: tenant1, role: :admin}
      system = %{id: Ash.UUID.generate(), role: :system, scope: :maintenance}

      {:ok, %{tenant1: tenant1, tenant2: tenant2, user1: user1, user2: user2, admin: admin, system: system}}
    end

    test "user can create in own tenant", %{user1: user1} do
      assert {:ok, _node} = VaultKnowledgeNode.create(%{
        node_type: :concept,
        title: "Test",
        knowledge_domain: "general"
      }, actor: user1)
    end

    test "user can read own tenant data", %{user1: user1, tenant1: tenant1} do
      {:ok, node} = VaultKnowledgeNode.create(%{
        node_type: :concept,
        title: "Test",
        knowledge_domain: "general",
        tenant_id: tenant1
      }, actor: user1)

      assert {:ok, [^node]} = VaultKnowledgeNode.read(actor: user1)
    end

    test "user cannot read other tenant data", %{user1: user1, user2: user2, tenant2: tenant2} do
      {:ok, _node} = VaultKnowledgeNode.create(%{
        node_type: :concept,
        title: "Test",
        knowledge_domain: "general",
        tenant_id: tenant2
      }, actor: user2)

      assert {:ok, []} = VaultKnowledgeNode.read(actor: user1)
    end

    test "admin can read within tenant", %{admin: admin, tenant1: tenant1} do
      {:ok, node} = VaultKnowledgeNode.create(%{
        node_type: :concept,
        title: "Test",
        knowledge_domain: "general",
        tenant_id: tenant1
      }, actor: admin)

      assert {:ok, [^node]} = VaultKnowledgeNode.read(actor: admin)
    end

    test "system can bypass tenant isolation with scope", %{system: system, tenant1: tenant1} do
      {:ok, node} = VaultKnowledgeNode.create(%{
        node_type: :concept,
        title: "Test",
        knowledge_domain: "general",
        tenant_id: tenant1
      }, actor: system)

      # System with maintenance scope can read across tenants
      assert {:ok, nodes} = VaultKnowledgeNode.read(actor: system)
      assert length(nodes) > 0
    end

    test "user cannot update other tenant data", %{user1: user1, user2: user2, tenant2: tenant2} do
      {:ok, node} = VaultKnowledgeNode.create(%{
        node_type: :concept,
        title: "Test",
        knowledge_domain: "general",
        tenant_id: tenant2
      }, actor: user2)

      assert {:error, %Ash.Error.Forbidden{}} = VaultKnowledgeNode.update(node, %{
        title: "Hacked"
      }, actor: user1)
    end
  end
end
```

### Step 4: Validate Changes

After fixing each resource:

1. ✅ Run tests: `mix test test/thunderline/<domain>/<resource>_test.exs`
2. ✅ Run Credo: `mix credo --strict`
3. ✅ Run Dialyzer: `mix dialyzer`
4. ✅ Check coverage: `mix coveralls.json --min-coverage 85`
5. ✅ Verify CI passes: All 6 stages green

---

## 🎯 Week 1 Completion Criteria

**Definition of Done** for AUDIT-01:

- [ ] All 28 violated resources fixed with proper policies
- [ ] Authorization tests added for each fixed resource
- [ ] No `authorize_if always()` except AshAuth bypass
- [ ] No commented-out policy blocks
- [ ] All tests passing (≥85% coverage)
- [ ] CI pipeline green (all 9 hard gates)
- [ ] This document reviewed and approved by Shadow-Sec

**Success Metrics**:
- 🎯 100% policy compliance (0 violations)
- 🎯 ≥85% test coverage maintained
- 🎯 Zero security regressions in CI

---

## 📚 References

- [Ash Policy Guide](https://hexdocs.pm/ash/policies.html)
- [Ash Multitenancy](https://hexdocs.pm/ash/multitenancy.html)
- [AshAuthentication Bypass](https://hexdocs.pm/ash_authentication/getting-started.html#policies)
- `EVENT_TAXONOMY.md` - Event-driven authorization patterns
- `CODEBASE_STATUS.md` - Overall project status

---

**Next Steps**: Begin systematic resource fixes starting with CRITICAL resources (User, Token, PolicyRule, AuditLog, VaultExperience).
