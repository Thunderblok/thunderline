# Thunderbit Behavior Contract v1.0

> **The Physics of Meaning** — This document defines the canonical semantics for
> Thunderbit operations. All implementations MUST conform to this contract.

---

## 1. Overview

The Thunderbit Protocol defines how **units of meaning** are born, composed, wired,
and transformed. It is the executable layer of the Upper Ontology.

```
Upper Ontology (what exists)
    ↓
Thunderbit Category Protocol (how meaning is born/composed)
    ↓
Thundervine DAG (how bits are orchestrated)
    ↓
Thundercrown Policy Engine (what's allowed)
    ↓
UIContract (what you see)
```

---

## 2. Canonical Thunderbit Struct

Every Thunderbit MUST have these fields:

```elixir
%Thunderbit{
  # Identity
  id: String.t(),                    # UUID, immutable after spawn
  category: Category.id(),           # :sensory | :cognitive | :mnemonic | :motor | ...
  role: Category.role(),             # :observer | :transformer | :storage | :actuator | ...
  
  # Content
  content: String.t(),               # The raw semantic payload
  ontology_path: [atom()],           # e.g. [:being, :proposition, :question]
  tags: [String.t()],                # Extracted entities/topics
  
  # Energy
  energy: float(),                   # 0.0-1.0 confidence/importance
  salience: float(),                 # 0.0-1.0 attention priority
  
  # Graph
  links: [String.t()],               # IDs of connected bits
  edges: [Edge.t()],                 # Full edge structs (optional)
  
  # Lifecycle
  status: status(),                  # :spawned | :processing | :settled | :error
  
  # Context
  owner: String.t() | nil,           # PAC or agent ID
  source: source(),                  # :text | :voice | :system | :pac
  
  # Ethics
  maxims: [String.t()],              # Applicable ethics maxims
  ethics_verdict: verdict() | nil,   # Result of ethics check
  
  # UI
  position: position(),              # {x, y, z} for rendering
  geometry: geometry(),              # Category-derived visual hints
  
  # Metadata
  inserted_at: DateTime.t(),
  metadata: map()
}
```

### Status Lifecycle

```
:spawned → :processing → :settled
                ↓
             :error
```

---

## 3. Protocol Verbs

### 3.1 `spawn_bit/3` — The Birth Ritual

```elixir
Protocol.spawn_bit(category, attrs, ctx) :: {:ok, bit, ctx} | {:error, reason}
```

**Inputs:**
- `category` — `:sensory | :cognitive | :motor | :mnemonic | :social | :ethical | :perceptual | :executive`
- `attrs` — `%{content: string, source: atom, tags: list, energy: float, ...}`
- `ctx` — Current context (PAC, graph, policies)

**Responsibilities:**

1. **Validate category** against Upper Ontology
   - `:cognitive` → `[:being, :proposition]`
   - `:sensory` → `[:being, :entity, :physical]`
   
2. **Enrich attrs:**
   - Assign UUID to `id`
   - Set `ontology_path` from category
   - Set `role` from category
   - Default `energy: 0.5`, `salience: 0.5`
   - Set `inserted_at: DateTime.utc_now()`
   - Set `status: :spawned`
   - Copy `required_maxims` from category definition
   
3. **Register** in ctx.bits_by_id

4. **Return** `{:ok, bit, ctx}` with updated context

**NEVER:**
- Mutate global state silently
- Return raw maps (always structs)
- Skip ethics check

---

### 3.2 `bind/3` — The Soul of Composition

```elixir
Protocol.bind(bit, fun, ctx) :: {bit', ctx'}
# OR for pipelines:
{bit, ctx} |> Protocol.bind(&transform/2)
```

**Contract:**
- `fun :: (bit, ctx) -> {bit', ctx'} | {:ok, bit', ctx'} | {:error, reason, ctx'}`

**MUST Preserve:**
- `bit.id` — immutable
- `bit.category` — immutable
- `bit.inserted_at` — immutable

**MAY Mutate:**
- `bit.content`
- `bit.tags`
- `bit.energy`
- `bit.salience`
- `bit.status`
- `bit.links`
- `bit.metadata`

**Context Updates:**
- Append to `ctx.log` (transformation events)
- Update `ctx.bits_by_id[bit.id]`
- Emit events to `ctx.event_log`

**Composability:**

```elixir
{bit, ctx}
|> Protocol.bind(&attach_intent/2)
|> Protocol.bind(&route_to_pac/2)
|> Protocol.bind(&score_risk/2)
```

Each bind is like "Thunderbit changes color/state" while staying the same entity.

---

### 3.3 `link/4` — Wiring Bits Together

```elixir
Protocol.link(from_bit, to_bit, relation, ctx) 
  :: {:ok, edge, ctx} | {:error, {:invalid_wiring, details}}
```

**Relation Types:**
- `:feeds` — data flow (sensory → cognitive)
- `:inhibits` — suppression
- `:modulates` — parameter influence
- `:contains` — hierarchical containment
- `:references` — soft pointer
- `:stores_in` — memory write
- `:retrieves` — memory read
- `:constrains` — ethical filtering
- `:commands` — action trigger

**Edge Struct:**

```elixir
%Thunderedge{
  id: String.t(),
  from_id: String.t(),
  to_id: String.t(),
  relation: relation(),
  strength: float(),        # 0.0-1.0
  metadata: map(),
  created_at: DateTime.t()
}
```

**Validation:**
1. Check `Category.wiring_valid?(from.category, to.category)`
2. Check `Thundercrown.check_link_policy(from, to, relation)`
3. Check `Ethics.check_link(from, to)`

**On Invalid:**
```elixir
{:error, {:invalid_wiring, %{from: :motor, to: :sensory, reason: :no_backward_edge}}}
```

---

## 4. Wiring Matrix v0

### 4.1 Allowed Connections (Default)

| From | To | Relation | Semantics |
|------|-----|----------|-----------|
| `:sensory` | `:cognitive` | `:feeds` | Raw input → reasoning |
| `:sensory` | `:mnemonic` | `:stores_in` | Input → memory |
| `:cognitive` | `:mnemonic` | `:consolidates` | Thought → memory |
| `:mnemonic` | `:cognitive` | `:retrieves` | Memory → thought |
| `:cognitive` | `:motor` | `:commands` | Decision → action |
| `:ethical` | `:cognitive` | `:constrains` | Ethics → reasoning |
| `:ethical` | `:motor` | `:filters` | Ethics → action |
| `:social` | `:cognitive` | `:contextualizes` | Social → reasoning |
| `:cognitive` | `:social` | `:expresses` | Reasoning → social |
| `:perceptual` | `:cognitive` | `:feeds` | Features → reasoning |
| `:executive` | `*` | `:orchestrates` | Controller → anything |

### 4.2 Disallowed Connections (Default)

| From | To | Reason |
|------|-----|--------|
| `:motor` | `:sensory` | No direct backward edge; needs intermediary |
| `:motor` | `:ethical` | Actions shouldn't originate ethics |
| `:sensory` | `:motor` | Raw reflexes are special-case, not default |
| `:ethical` | `:ethical` | No infinite regress |

### 4.3 Implementation

```elixir
# Static matrix in Category module
@wiring_matrix %{
  sensory: [:cognitive, :mnemonic, :perceptual, :social],
  cognitive: [:motor, :social, :ethical, :mnemonic, :executive],
  mnemonic: [:cognitive, :perceptual, :social],
  motor: [:mnemonic],
  social: [:motor, :cognitive, :mnemonic],
  ethical: [:motor, :social],
  perceptual: [:cognitive, :mnemonic, :social],
  executive: [:sensory, :cognitive, :mnemonic, :motor, :social, :ethical, :perceptual]
}

def wiring_valid?(from, to), do: to in Map.get(@wiring_matrix, from, [])
```

---

## 5. Context Threading

The `ctx` parameter is the **local universe** — never a junk drawer.

### 5.1 Required Fields

```elixir
%Context{
  # Bit registry
  bits_by_id: %{String.t() => Thunderbit.t()},
  edges: [Thunderedge.t()],
  
  # Current scope
  pac_id: String.t() | nil,
  graph_id: String.t() | nil,
  zone: String.t() | nil,
  
  # Governance
  policies: [Policy.t()],
  active_maxims: [String.t()],
  
  # Logging
  log: [LogEntry.t()],
  event_log: [Event.t()],
  
  # Session
  session_id: String.t(),
  started_at: DateTime.t()
}
```

### 5.2 Context Rules

1. **Never mutate global state** — always take ctx, return ctx
2. **Explicit field access** — no magic __MODULE__ tricks
3. **Testable** — ctx can be serialized/replayed
4. **Optimizable** — later we can shove ctx into ECS or CA grid

---

## 6. UIContract

### 6.1 Slim DTO Shape

Every bit sent to UI MUST have:

```elixir
%ThunderbitDTO{
  id: String.t(),
  category: String.t(),              # Atom as string
  role: String.t(),
  
  # Display
  label: String.t(),                 # Shortened content (max 30 chars)
  tooltip: String.t(),               # Full content
  
  # State
  energy: float(),
  salience: float(),
  status: String.t(),                # "spawned" | "processing" | "settled" | "error"
  
  # Graph
  links: [%{target_id: String.t(), relation: String.t(), strength: float()}],
  
  # Ontology
  ontology_path: [String.t()],
  
  # Geometry
  geometry: %{
    x: float(),
    y: float(),
    z: float(),                      # Layer/depth
    shape: String.t(),               # "circle" | "hex" | "capsule" | ...
    color: String.t(),               # Hex color
    size: float(),                   # Based on energy
    animation: String.t()            # "pulse" | "spin" | "static"
  }
}
```

### 6.2 Broadcast Contract

```elixir
UIContract.broadcast(bits) :: :ok

# Publishes to: "thunderbits:lobby"
# Event types:
#   - "thunderbit:created"
#   - "thunderbit:updated"
#   - "thunderbit:linked"
#   - "thunderbit:retired"
```

---

## 7. Error Handling

### 7.1 Spawn Errors

```elixir
{:error, :unknown_category}
{:error, {:ethics_violation, %{maxim: "Primum non nocere", reason: "..."}}}
{:error, {:policy_denied, %{policy: "zone_restricted", ...}}}
```

### 7.2 Link Errors

```elixir
{:error, {:invalid_wiring, %{from: :motor, to: :sensory}}}
{:error, {:cycle_detected, [id1, id2, id3]}}
{:error, {:policy_denied, %{policy: "cross_pac_link", ...}}}
```

### 7.3 Bind Errors

```elixir
{:error, :continuation_failed, ctx}
{:error, {:timeout, 5000}, ctx}
```

---

## 8. Integration Points

### 8.1 Thundervine DAG

```elixir
# Groups of Thunderbits become DAG nodes
Thundervine.Node
|> Map.put(:thunderbit_categories, [:sensory, :cognitive])
|> Map.put(:wiring_rules, %{internal: true, cross_node: :restricted})
```

### 8.2 Thundercrown Policy

```elixir
# Policy checks at spawn/link time
Thundercrown.check_spawn_policy(bit, ctx) :: :ok | {:deny, reason}
Thundercrown.check_link_policy(from, to, relation) :: :ok | {:deny, reason}
```

### 8.3 Ethics Layer

```elixir
# Maxim enforcement
Ethics.check_spawn(category, ctx) :: :ok | {:error, :maxim_violated}
Ethics.check_link(from, to) :: :ok | {:error, :invalid_composition}
Ethics.check_action(bit, action) :: :ok | {:error, :forbidden_action}
```

---

## 9. Demo Flow: Text → Sensory → Cognitive → UI

```elixir
def demo_intake(text, pac_id) do
  ctx = Context.new(pac_id: pac_id)
  
  # 1. Spawn sensory bit from text
  {:ok, sensory, ctx} = Protocol.spawn_bit(:sensory, %{
    content: text,
    source: :text
  }, ctx)
  
  # 2. Bind through classification
  {sensory, ctx} = Protocol.bind(sensory, &classify_intent/2, ctx)
  {sensory, ctx} = Protocol.bind(sensory, &extract_tags/2, ctx)
  
  # 3. Spawn cognitive bit for reasoning
  {:ok, cognitive, ctx} = Protocol.spawn_bit(:cognitive, %{
    content: text,
    source: :system,
    metadata: %{input_bit_id: sensory.id}
  }, ctx)
  
  # 4. Link them
  {:ok, edge, ctx} = Protocol.link(sensory, cognitive, :feeds, ctx)
  
  # 5. Broadcast to UI
  bits = [sensory, cognitive]
  :ok = UIContract.broadcast(bits, edge)
  
  {:ok, bits, ctx}
end
```

**UI Result:**
- 2 glyphs appear
- Sensory: blue circle, pulsing
- Cognitive: purple hex, spinning
- Arrow from sensory → cognitive labeled `:feeds`

---

## 10. Versioning

| Version | Date | Changes |
|---------|------|---------|
| v1.0 | 2025-12-01 | Initial behavior contract |

---

## 11. Compliance Checklist

For any Thunderbit implementation:

- [ ] `spawn_bit/3` returns `{:ok, bit, ctx}` with updated context
- [ ] `bind/3` preserves `id`, `category`, `inserted_at`
- [ ] `link/4` validates wiring matrix before creating edge
- [ ] All operations take `ctx`, return updated `ctx`
- [ ] `UIContract.broadcast/1` sends slim DTOs to `"thunderbits:lobby"`
- [ ] Errors follow standard tuple format
- [ ] No global state mutation

---

**This contract is the law. Drift at your peril.** ⚡
