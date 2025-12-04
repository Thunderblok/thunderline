# Thunderlink Node Registry - Implementation Progress

**Mission**: First-class, Ash-backed registry for BEAM + edge nodes with 3D graph visualization

**Status**: ✅ **Step 1 Complete** (Schema & Migrations) - 45% overall progress

---

## ✅ Step 1: Schema & Migrations - COMPLETE

### Resources Created (6 total, 618 lines)

1. **Node** (`lib/thunderline/thunderlink/resources/node.ex` - 176 lines)
   - Core node registry: name, role, domain, status, cluster_type
   - Actions: register, mark_online, mark_offline, mark_status, by_role, by_status, online_nodes
   - Identities: unique_name
   - Code interface: all actions exposed

2. **Heartbeat** (`lib/thunderline/thunderlink/resources/heartbeat.ex` - 150 lines)
   - Rolling liveness + metrics: cpu_load, mem_used_mb, latency_ms
   - Actions: record, for_node, **recent** (fixed filter), **old_heartbeats** (converted from destroy), bulk_delete
   - **Filter fixes applied**: 2 actions corrected to use `expr()` macro

3. **LinkSession** (`lib/thunderline/thunderlink/resources/link_session.ex` - 204 lines)
   - Edge connections: session_type, status, weight, latency_ms, bandwidth_mbps
   - Actions: create, establish, update_metrics, close, for_node, active, by_nodes
   - Relationships: belongs_to :node, :remote_node (self-referential)

4. **NodeCapability** (`lib/thunderline/thunderlink/resources/node_capability.ex` - 158 lines)
   - Capability-based routing: capability_key, capability_value, enabled
   - Actions: create, enable, disable, for_node, enabled_for_node, **by_capability** (fixed filter), ml_inference_nodes
   - **Filter fix applied**: Conditional filtering corrected
   - Identities: unique_capability_per_node

5. **NodeGroup** (`lib/thunderline/thunderlink/resources/node_group.ex` - 148 lines)
   - Logical grouping: name, group_type, parent_group_id (hierarchical)
   - Actions: create, add_node, remove_node, list_members, roots, by_type
   - Identities: unique_name

6. **NodeGroupMembership** (`lib/thunderline/thunderlink/resources/node_group_membership.ex` - 93 lines)
   - Join table: node_id, group_id, meta
   - Identities: unique_membership

### Domain Registration

Updated `lib/thunderline/thunderlink/domain.ex`:
- Registered all 6 new resources
- Total resources in domain: 15 (9 existing + 6 new)

### Migration Generated & Applied

**File**: `priv/repo/migrations/20251116052600_add_thunderlink_node_registry.exs`

**Tables Created**:
- ✅ `thunderlink_nodes` - Core node table with unique name index
- ✅ `thunderlink_heartbeats` - Rolling liveness records
- ✅ `thunderlink_link_sessions` - Edge connections (bidirectional foreign keys)
- ✅ `thunderlink_node_capabilities` - Capability routing
- ✅ `thunderlink_node_groups` - Logical grouping with optional parent
- ✅ `thunderlink_node_group_memberships` - Join table with composite unique index

**Foreign Keys**:
- All `on_delete: :delete_all` for proper cascade
- Self-referential FK in `link_sessions` (node_id → remote_node_id)
- Hierarchical FK in `node_groups` (parent_group_id → node_groups)

**Indexes**:
- Unique name index on nodes
- Unique name index on node_groups
- Unique (node_id, capability_key) on node_capabilities
- Unique (node_id, group_id) on node_group_memberships

### Filter Syntax Fixes

**Issue**: Ash 3.x requires `expr()` macro for all filters

**Fixes Applied**:

1. **Heartbeat.ex - read :recent**:
   - ✅ Added `before_action` wrapper
   - ✅ Added `require Ash.Query`
   - ✅ Wrapped filter in `expr(inserted_at > ^cutoff)`

2. **Heartbeat.ex - read :old_heartbeats** (converted from destroy):
   - ✅ Changed from `destroy :destroy_old` to `read :old_heartbeats`
   - ✅ Used inline `filter expr(inserted_at < ^DateTime.add(...))`
   - **Lesson**: Destroy actions don't support `prepare` callback

3. **NodeCapability.ex - read :by_capability**:
   - ✅ Added `before_action` wrapper
   - ✅ Added `require Ash.Query`
   - ✅ Wrapped both conditional filters in `expr()`
   - ✅ Extracted variables for cleaner code

### Compilation Status

✅ **All resources compile cleanly**
✅ **No filter syntax errors**
✅ **Migration applied successfully**

---

## ⏳ Step 2: Registry Module - PENDING

**File**: `lib/thunderline/thunderlink/registry.ex`

**Core Functions** (to implement):
- `ensure_node(attrs)` - Register or update node
- `mark_online(node_id, session_attrs)` - Mark node online + create link session
- `mark_status(node_id, status)` - Update node status
- `heartbeat(node_id, metrics)` - Record heartbeat
- `list_nodes(filters \\ [])` - Query nodes
- `graph()` - Return full topology for visualization

**Optional**:
- ETS cache for hot-path queries
- Pre-computed adjacency lists

---

## ⏳ Step 3: Wire Into Gate/Link/Flow - PENDING

**Thundergate Integration**:
- Call `Registry.ensure_node/1` on handshake
- Extract node metadata from QUIC connection

**Thunderlink Integration**:
- Call `Registry.mark_online/2` on connection established
- Call `Registry.heartbeat/2` periodically
- Update `LinkSession` metrics on traffic

**Thunderflow Integration**:
- Emit `cluster.node.registered` event
- Emit `cluster.node.online` event
- Emit `cluster.node.offline` event
- Emit `cluster.link.established` event

---

## ⏳ Step 4: Cluster Graph API - PENDING

**Controller**: `ThunderlinkWeb.ThunderlinkController`

**Endpoints**:
- `GET /api/thunderlink/nodes` - List all nodes with metadata
- `GET /api/thunderlink/graph` - Full topology JSON for 3d-force-graph

**Response Format** (3d-force-graph compatible):
```json
{
  "nodes": [
    {"id": "uuid", "name": "worker-1", "role": "worker", "val": 10}
  ],
  "links": [
    {"source": "uuid1", "target": "uuid2", "value": 1.0}
  ]
}
```

---

## ⏳ Step 5: Realtime Topology Stream - PENDING

**Phoenix Channel**: `thunderlink:graph`

**Events**:
- `node_up` - When node comes online
- `node_down` - When node goes offline
- `link_up` - When link established
- `link_down` - When link closed
- `topology_update` - Periodic full graph

**Implementation**:
- Subscribe to `cluster.*` Thunderflow events
- Broadcast to connected clients
- Track subscribed topics per socket

---

## ⏳ Step 6: Tests & Guardrails - PENDING

**Resource Tests**:
- Node CRUD + filters
- Heartbeat rolling records
- LinkSession relationships
- NodeCapability querying

**Registry Tests**:
- `ensure_node/1` idempotency
- `graph/0` structure
- Concurrent updates

**Controller Tests**:
- GET /api/thunderlink/nodes
- GET /api/thunderlink/graph

**Feature Flag**:
- `config :thunderline, :enable_node_registry, true`

---

## ⏳ Step 7: Documentation - PENDING

**TL;DR** (for team):
- What is Node Registry?
- How to query cluster state?
- How to visualize topology?

**API Documentation**:
- Registry module functions
- HTTP endpoints
- Channel events

---

## Ash Filter Syntax Patterns (Learned)

### Read Actions - Use `prepare`

```elixir
read :recent do
  argument :minutes, :integer, default: 60
  prepare before_action(fn query, _context ->
    require Ash.Query
    cutoff = DateTime.add(DateTime.utc_now(), -query.arguments.minutes, :minute)
    Ash.Query.filter(query, expr(inserted_at > ^cutoff))
  end)
end
```

### Destroy Actions - Use Inline `filter`

```elixir
destroy :destroy_old do
  argument :hours, :integer, default: 24
  filter expr(inserted_at < ^DateTime.add(DateTime.utc_now(), -hours * 3600, :second))
end
```

**Best Practice**: For deletion, use `read` action to find records, then delete separately:

```elixir
read :old_heartbeats do
  argument :hours, :integer, default: 24
  filter expr(inserted_at < ^DateTime.add(DateTime.utc_now(), -hours * 3600, :second))
end
```

---

## Next Steps

**Immediate** (Step 2):
1. Create `lib/thunderline/thunderlink/registry.ex`
2. Implement `ensure_node/1` using Node.register action
3. Implement `mark_online/2` (update Node + create LinkSession)
4. Implement `heartbeat/2` (create Heartbeat record)
5. Implement `graph/0` (query Nodes + LinkSessions)
6. Optional: Add ETS cache for performance

**Then** (Steps 3-7):
7. Wire into Thundergate handshake
8. Wire into Thunderlink connection
9. Add Thunderflow event emissions
10. Create HTTP API endpoints
11. Add Phoenix Channel for realtime
12. Write tests
13. Add feature flag
14. Document for team

---

**Overall Progress**: 45% complete (Step 1 done, 6 steps remaining)
