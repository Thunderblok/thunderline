# HC-Δ-5: Thunderbit Category Protocol v0.1

> **Status**: Draft  
> **Card**: HC-Δ-5  
> **Depends**: Upper Ontology (HC-Ω), Thundervine DAG (HC-Δ-1), Thundercrown Policy (HC-Δ-2)  
> **Unlocks**: HC-Δ-3 (DiffLogic CA), HC-Δ-4 (MAP-Elites), Thunderfield UI

---

## 1. Purpose

The Thunderbit Category Protocol turns the Upper Ontology into an **executable computational grammar**. It defines:

1. **Formal Thunderbit categories** with roles, I/O specs, and capabilities
2. **Composition rules** for valid wiring between Thunderbits
3. **Protocol verbs** for the Thunderbit lifecycle (spawn, bind, link, step, retire)
4. **UI geometry contract** for rendering
5. **PAC/DAG integration rules**
6. **Ethics enforcement hooks**

Without this protocol, the ontology is just taxonomy. With it, every Thunderbit becomes a runnable unit with known interfaces.

---

## 2. Category Taxonomy

### 2.1 Core Categories (bound to Upper Ontology)

Each Thunderbit resolves to exactly one ontological node. The protocol adds computational semantics:

| Category | Ontology Path | Role | Description |
|----------|--------------|------|-------------|
| **Sensory** | Entity.Physical | Observer | Ingests external signals (text, voice, sensors) |
| **Cognitive** | Proposition.* | Transformer | Reasons, classifies, infers |
| **Mnemonic** | Entity.Conceptual | Storage | Recalls and stores context |
| **Motor** | Process.Action | Actuator | Emits events, triggers actions |
| **Social** | Relation.* | Router | Manages connections between agents |
| **Ethical** | Proposition.Goal | Critic | Evaluates constraints and policies |
| **Perceptual** | Attribute.State | Analyzer | Extracts features and patterns |
| **Executive** | Process.Action | Controller | Sequences and orchestrates |

### 2.2 Thunderbit Roles

Every Thunderbit plays exactly one role in the computational graph:

```
┌─────────────────────────────────────────────────────────────────┐
│  OBSERVER      TRANSFORMER      ROUTER       ACTUATOR   CRITIC │
│     ↓              ↓              ↓             ↓          ↓   │
│  [Sense]  →    [Think]    →   [Route]   →   [Act]   ←  [Judge] │
└─────────────────────────────────────────────────────────────────┘
```

| Role | Input | Output | Capability |
|------|-------|--------|------------|
| **Observer** | External signals | Parsed events | `read:sensors`, `subscribe:topics` |
| **Transformer** | Events, context | Transformed events | `compute:inference`, `access:memory` |
| **Router** | Events | Routed events | `select:targets`, `filter:events` |
| **Actuator** | Events | Side effects | `write:events`, `trigger:actions` |
| **Critic** | Events, context | Verdicts | `evaluate:policy`, `veto:action` |
| **Controller** | Events | Control flow | `sequence:steps`, `spawn:children` |
| **Storage** | Events | Stored state | `persist:memory`, `retrieve:context` |

---

## 3. Thunderbit Schema

### 3.1 Category Definition Struct

```elixir
defmodule Thunderline.Thunderbit.Category do
  @type t :: %__MODULE__{
    id: atom(),                          # :sensory, :cognitive, etc.
    name: String.t(),                    # "Sensory"
    ontology_path: [atom()],             # [:being, :entity, :physical]
    role: role(),                        # :observer | :transformer | ...
    
    # I/O Specification
    inputs: [io_spec()],                 # What this category accepts
    outputs: [io_spec()],                # What this category produces
    
    # Capabilities
    capabilities: [capability()],        # What it can request/mutate
    forbidden: [capability()],           # What it must never do
    
    # Composition Rules
    can_link_to: [atom()],               # Valid downstream categories
    can_receive_from: [atom()],          # Valid upstream categories
    composition_mode: composition(),     # :serial | :parallel | :feedback
    
    # Ethics
    required_maxims: [String.t()],       # Must satisfy these
    forbidden_maxims: [String.t()],      # Must not violate these
    
    # UI Hints
    geometry: geometry(),                # Visual representation
    
    # Metadata
    description: String.t(),
    examples: [String.t()]
  }
  
  @type role :: :observer | :transformer | :router | :actuator | :critic | :controller | :storage
  
  @type io_spec :: %{
    name: atom(),
    type: atom(),           # :event | :tensor | :message | :context
    shape: term(),          # For tensors: {dim1, dim2, ...}
    topic: String.t()       # For events/messages
  }
  
  @type capability :: atom()
  # :read_sensors, :write_events, :access_memory, :spawn_bits,
  # :mutate_pac, :trigger_action, :evaluate_policy, :veto_action
  
  @type composition :: :serial | :parallel | :feedback | :broadcast
  
  @type geometry :: %{
    type: :node | :glyph | :voxel | :halo | :edge,
    shape: :circle | :hex | :capsule | :star | :diamond | :triangle | :square,
    base_color: atom(),
    size_basis: :energy | :salience | :fixed,
    animation: :pulse | :drift | :static | :spin
  }
end
```

### 3.2 Thunderbit Instance Struct (Extended)

The existing `Thunderbit` struct gains category-aware fields:

```elixir
defmodule Thunderline.Thunderbit do
  # ... existing fields ...
  
  # NEW: Category Protocol fields
  field :category, :atom                    # :sensory, :cognitive, etc.
  field :role, :atom                        # :observer, :transformer, etc.
  field :io_state, :map                     # Current input/output buffers
  field :capabilities_used, [:atom]         # Audit trail
  field :composition_context, :map          # Parent chain, siblings
  field :ethics_verdict, :map               # Last policy evaluation
end
```

---

## 4. Protocol Verbs

The Thunderbit lifecycle is managed through a small set of protocol verbs:

### 4.1 Verb Definitions

| Verb | Signature | Description |
|------|-----------|-------------|
| `spawn_bit` | `spawn_bit(category, attrs, context) → {:ok, bit} \| {:error, reason}` | Create a new Thunderbit |
| `bind` | `bind(bit, continuation) → {:ok, bit', context'}` | Monadic bind: pass bit to next step |
| `link` | `link(bit_a, bit_b, relation) → {:ok, edge} \| {:error, :invalid_wiring}` | Connect two Thunderbits |
| `step` | `step(bit, event) → {:ok, bit', outputs} \| {:halt, reason}` | Process one input event |
| `retire` | `retire(bit, reason) → :ok` | Gracefully remove from field |
| `query` | `query(bit, key) → {:ok, value} \| :not_found` | Read internal state |
| `mutate` | `mutate(bit, changes) → {:ok, bit'} \| {:error, :forbidden}` | Update internal state |

### 4.2 Monadic Bind Pattern

The `bind/2` operation is the core composition primitive:

```elixir
# bind(bit, continuation) → {bit', context'}
# Where continuation :: (bit, context) → {bit', context'}

# Example: parse text → classify → spawn UI bit
{:ok, bit} = Thunderbit.spawn_bit(:sensory, %{content: "Is it safe?"}, ctx)
{bit, ctx} = Thunderbit.bind(bit, &classify/2)
{bit, ctx} = Thunderbit.bind(bit, &extract_tags/2)
{bit, ctx} = Thunderbit.bind(bit, &spawn_in_field/2)
```

### 4.3 Wiring Rules

Not all categories can connect to all others. The protocol enforces valid composition:

```
VALID WIRING:
  Observer  → Transformer  (sense → think)
  Observer  → Storage      (sense → remember)
  Transformer → Router     (think → route)
  Transformer → Actuator   (think → act)
  Transformer → Critic     (think → judge)
  Router → Actuator        (route → act)
  Critic → Actuator        (judge → allow/deny act)
  Controller → *           (orchestrate anything)
  
INVALID WIRING:
  Actuator → Observer      (can't un-act)
  Critic → Critic          (no infinite regress)
  Storage → Actuator       (memory doesn't act directly)
```

Encoded as adjacency:

```elixir
@wiring_rules %{
  observer:    [:transformer, :storage, :router],
  transformer: [:router, :actuator, :critic, :storage, :controller],
  router:      [:actuator, :transformer, :storage],
  actuator:    [:storage],  # Can log actions
  critic:      [:actuator, :router],  # Can veto or redirect
  controller:  [:observer, :transformer, :router, :actuator, :critic, :storage],
  storage:     [:transformer, :router]  # Recall feeds reasoning
}
```

---

## 5. UI Geometry Contract

### 5.1 Minimal Schema for Front-End

Every Thunderbit exposed to UI must provide:

```typescript
interface ThunderbitUISpec {
  id: string;
  canonical_name: string;
  
  // Geometry
  geometry: {
    type: "node" | "glyph" | "voxel" | "halo" | "edge";
    shape: "circle" | "hex" | "capsule" | "star" | "diamond" | "triangle" | "square";
    position: { x: number; y: number; z: number };
  };
  
  // Visual State
  visual: {
    base_color: string;      // Hex color
    energy: number;          // 0-1, affects size/glow
    salience: number;        // 0-1, affects opacity/prominence
    state: "idle" | "thinking" | "overloaded" | "constrained" | "fading";
    animation: "pulse" | "drift" | "spin" | "static";
  };
  
  // Relations (for rendering edges)
  links: Array<{
    target_id: string;
    relation_type: string;
    strength: number;
  }>;
  
  // Content
  label: string;             // Short display text
  tooltip: string;           // Detailed hover text
  category: string;          // Category name for filtering
  role: string;              // Role name
}
```

### 5.2 UI Query Interface

The front-end can query the backend with:

```elixir
# Given a PAC + text/voice parse → spawn + layout metadata
Thunderbit.Protocol.spawn_for_ui(%{
  pac_id: "ezra_001",
  input_type: :text,
  content: "Navigate to the crash site",
  zone: "hangar_bay"
}) 
# → {:ok, [%ThunderbitUISpec{...}, ...]}
```

---

## 6. PAC Integration

### 6.1 PAC → Thunderbit Mapping

PAC internal organs become Thunderbits:

| PAC Component | Thunderbit Category | Role |
|---------------|---------------------|------|
| Perception | Sensory | Observer |
| Attention | Perceptual | Analyzer |
| Working Memory | Mnemonic | Storage |
| Long-term Memory | Mnemonic | Storage |
| Reasoning | Cognitive | Transformer |
| Planning | Executive | Controller |
| Action Selection | Cognitive | Transformer |
| Motor Output | Motor | Actuator |
| Social Model | Social | Router |
| Values/Ethics | Ethical | Critic |

### 6.2 PAC Instantiation

When a PAC is spawned, it automatically gets a constellation of Thunderbits:

```elixir
def spawn_pac_bits(pac_id, config) do
  [
    {:sensory, %{owner: pac_id, role: :observer}},
    {:cognitive, %{owner: pac_id, role: :transformer}},
    {:mnemonic, %{owner: pac_id, role: :storage}},
    {:motor, %{owner: pac_id, role: :actuator}},
    {:ethical, %{owner: pac_id, role: :critic}}
  ]
  |> Enum.map(fn {cat, attrs} -> Thunderbit.spawn_bit(cat, attrs, %{pac: pac_id}) end)
  |> Enum.reduce_while({:ok, []}, &collect_results/2)
end
```

---

## 7. DAG Integration

### 7.1 Thundervine Node Types

DAG nodes gain Thunderbit category annotations:

```elixir
defmodule Thunderline.Thundervine.Node do
  # ... existing fields ...
  
  # NEW: Thunderbit protocol fields
  field :thunderbit_categories, [:atom]      # Categories this node handles
  field :wiring_rules, :map                  # Local composition rules
  field :ethics_context, :map                # Maxims in scope
end
```

### 7.2 DAG ↔ Thunderbit Mapping

| DAG Concept | Thunderbit Equivalent |
|-------------|----------------------|
| Input Node | Observer Thunderbit |
| Transform Node | Transformer Thunderbit |
| Branch Node | Router Thunderbit |
| Output Node | Actuator Thunderbit |
| Checkpoint Node | Storage Thunderbit |
| Validation Node | Critic Thunderbit |

---

## 8. Ethics Enforcement

### 8.1 Maxim Attachment

Every category has ethics metadata:

```elixir
@category_ethics %{
  sensory: %{
    required: ["Res in armonia"],           # Must preserve harmony
    forbidden: []
  },
  motor: %{
    required: ["Primum non nocere"],        # Must not harm
    forbidden: ["Acta sine consilio"]       # No action without deliberation
  },
  ethical: %{
    required: ["Veritas liberabit", "In nexus virtus"],
    forbidden: []
  }
}
```

### 8.2 Policy Check Flow

Before `spawn_bit` or `link` completes, Thundercrown evaluates:

```elixir
def spawn_bit(category, attrs, context) do
  with {:ok, bit} <- build_bit(category, attrs),
       :ok <- Thundercrown.check_spawn_policy(bit, context),
       :ok <- check_maxim_compliance(bit) do
    {:ok, activate(bit)}
  end
end

def link(bit_a, bit_b, relation) do
  with :ok <- check_wiring_valid?(bit_a, bit_b),
       :ok <- Thundercrown.check_link_policy(bit_a, bit_b, relation),
       :ok <- check_combined_maxims(bit_a, bit_b) do
    {:ok, create_edge(bit_a, bit_b, relation)}
  end
end
```

---

## 9. Module Structure

### 9.1 File Layout

```
lib/thunderline/thunderbit/
├── category.ex           # Category definitions and registry
├── protocol.ex           # Verb implementations (spawn, bind, link, step, retire)
├── registry.ex           # Runtime category registry
├── wiring.ex             # Composition rules and validation
├── io.ex                 # I/O spec types and validation
├── ethics.ex             # Maxim enforcement
├── ui_contract.ex        # UI geometry helpers
└── resources/
    └── thunderbit_definition.ex  # Ash resource for persistence
```

### 9.2 Module Responsibilities

| Module | Responsibility |
|--------|---------------|
| `Thunderbit.Category` | Define and query category metadata |
| `Thunderbit.Protocol` | Implement the 7 verbs |
| `Thunderbit.Registry` | Runtime lookup of categories and instances |
| `Thunderbit.Wiring` | Validate connections, check composition rules |
| `Thunderbit.IO` | Type specs for inputs/outputs |
| `Thunderbit.Ethics` | Maxim checks, policy integration |
| `Thunderbit.UIContract` | Generate UI specs |
| `Thunderbit.Definition` | Ash resource for admin/persistence |

---

## 10. Vertical Slice: Text → Thunderbits → UI

### 10.1 Flow

```
User types: "Is the crash site clear?"
     ↓
[1. Parse] → Sensory Thunderbit (Observer)
     ↓
[2. Classify] → Cognitive Thunderbit (Transformer) 
     ↓ kind: :question
[3. Extract] → Tags: ["crash_site", "safety"]
     ↓
[4. Spawn UI] → ThunderbitUISpec pushed to LiveView
     ↓
[5. Render] → Orange bubble appears in Thunderfield
```

### 10.2 Implementation Sketch

```elixir
defmodule Thunderline.Thunderbit.Intake do
  alias Thunderline.Thunderbit.{Protocol, Category, UIContract}
  
  def process_text(content, context) do
    with {:ok, sensory} <- Protocol.spawn_bit(:sensory, %{content: content}, context),
         {sensory, ctx} <- Protocol.bind(sensory, &classify/2),
         {sensory, ctx} <- Protocol.bind(sensory, &extract_tags/2),
         {:ok, cognitive} <- maybe_spawn_cognitive(sensory, ctx),
         {:ok, ui_specs} <- UIContract.render_all([sensory, cognitive]) do
      broadcast_to_field(ui_specs)
      {:ok, ui_specs}
    end
  end
  
  defp classify(bit, ctx) do
    # ... classification logic ...
  end
  
  defp extract_tags(bit, ctx) do
    # ... tag extraction ...
  end
  
  defp maybe_spawn_cognitive(sensory, ctx) do
    if needs_reasoning?(sensory) do
      Protocol.spawn_bit(:cognitive, %{input: sensory.id}, ctx)
    else
      {:ok, nil}
    end
  end
  
  defp broadcast_to_field(specs) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_spawn, specs}
    )
  end
end
```

---

## 11. Success Criteria

### 11.1 Must Have

- [ ] All 8 categories defined with complete metadata
- [ ] 7 protocol verbs implemented
- [ ] Wiring rules enforced (invalid links rejected)
- [ ] Ethics checks integrated (at least maxim validation)
- [ ] UI contract produces valid specs
- [ ] Text → Thunderbit → UI flow works

### 11.2 Nice to Have

- [ ] Ash resource for category persistence
- [ ] Admin UI for category management
- [ ] Voice input pathway
- [ ] PAC auto-spawning of Thunderbit constellations
- [ ] DAG node annotation with categories

---

## 12. API Quick Reference

```elixir
# Category queries
Category.get(:sensory)                    # → {:ok, %Category{}}
Category.list_by_role(:observer)          # → [%Category{}, ...]
Category.wiring_valid?(:sensory, :motor)  # → false
Category.maxims_for(:motor)               # → ["Primum non nocere"]

# Protocol verbs
Protocol.spawn_bit(:cognitive, attrs, ctx)  # → {:ok, %Thunderbit{}}
Protocol.bind(bit, &transform/2)            # → {bit', ctx'}
Protocol.link(bit_a, bit_b, :causes)        # → {:ok, edge} | {:error, _}
Protocol.step(bit, event)                   # → {:ok, bit', outputs}
Protocol.retire(bit, :done)                 # → :ok
Protocol.query(bit, :energy)                # → {:ok, 0.85}
Protocol.mutate(bit, %{salience: 0.9})      # → {:ok, bit'}

# Registry
Registry.register(bit)                    # → :ok
Registry.lookup(bit_id)                   # → {:ok, %Thunderbit{}}
Registry.by_category(:sensory)            # → [%Thunderbit{}, ...]
Registry.by_owner(pac_id)                 # → [%Thunderbit{}, ...]

# UI Contract
UIContract.to_spec(bit)                   # → %ThunderbitUISpec{}
UIContract.render_all([bits])             # → [%ThunderbitUISpec{}, ...]

# Ethics
Ethics.check_spawn(category, ctx)         # → :ok | {:error, :maxim_violated}
Ethics.check_link(bit_a, bit_b)           # → :ok | {:error, :invalid_composition}
```

---

**Next**: Implement Elixir modules following this spec.
