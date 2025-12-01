# Thunderline Upper Ontology v1.0

> **Location**: `lib/thunderline/thundercore/ontology.ex`  
> **Status**: Foundational / Active Development

The Thunderline Upper Ontology provides a formal, high-level schema for the entire Thunderline ecosystem. It defines foundational categories, their relations and attributes, and maps these concepts to UI visualization, PAC behaviors, DAG orchestration, and MCP ethics.

## Design Principles

| Principle | Description |
|-----------|-------------|
| **Rootedness** | All things derive from `:being` - a single root category enabling unified type system |
| **Layered Hierarchy** | 3-5 levels of refinement for manageable classification |
| **Polymorphism** | High-level categories specialize without losing identity |
| **Mappability** | Each category maps to UI, PAC behavior, DAG nodes, and MCP ethics |
| **Grammatical Encoding** | Canonical names reflect ontological paths |

## Category Hierarchy

```
Being (Level 0)
├── Entity (Level 1)      - Enduring things with attributes
│   ├── Physical          - Space/time occupants (→ Thunderblock/Thundergrid)
│   ├── Agent             - Autonomous actors (→ Thunderpac)
│   │   ├── pac           - PAC instances
│   │   ├── human         - Human users
│   │   └── bot           - Automated bots
│   └── Conceptual        - Abstract constructs
│
├── Process (Level 1)     - Temporal occurrences
│   ├── Action            - Intentional, agent-initiated
│   │   ├── navigate      - Spatial movement (→ Thundergrid)
│   │   ├── communicate   - Message exchange (→ Thunderlink)
│   │   ├── compute       - Calculation (→ Thunderbolt)
│   │   ├── evolve        - PAC evolution (→ Thunderpac)
│   │   └── orchestrate   - DAG execution (→ Thundervine)
│   └── Event             - Uncontrolled happenings
│
├── Attribute (Level 1)   - Properties/qualities
│   ├── State             - Dynamic, changeable
│   │   ├── energy_level  - PAC energy
│   │   ├── health_status - System health
│   │   └── trust_score   - Crown trust metrics
│   └── Quality           - Intrinsic, stable
│
├── Relation (Level 1)    - Connections between things
│   ├── Spatial           - Position relations
│   ├── Temporal          - Time relations
│   └── Causal            - Cause-effect
│
└── Proposition (Level 1) - Claims/beliefs
    ├── Assertion         - Stated facts
    ├── Goal              - Desired outcomes (→ Thundercrown policies)
    │   ├── safety
    │   ├── efficiency
    │   └── alignment
    └── Question          - Queries
```

## Thunderbit Grammar

Every Thunderbit has a canonical name following this grammar:

```
<Bit> ::= <OntologyPath> "/" <Name> ["@" <Attributes>]
<OntologyPath> ::= <Category> ["." <Category>]*
<Attributes> ::= <Key>"="<Value> {","<Key>"="<Value>}
```

### Examples

```
Entity.Agent.PAC/Ezra@energy=0.8,zone=crash_site
Process.Action.Navigate/EzraNavigateCrater@timestamp=2025-12-01T10:34:00Z
Proposition.Question/IsAreaClear@owner=User1,energy=0.72
```

## Mappings

### UI Geometry

| Category | Shape | Color | Size | Animation |
|----------|-------|-------|------|-----------|
| Entity | Solid node (circle/hex) | Blue (physical), Purple (conceptual) | ∝ energy | Drift slowly |
| Process | Capsule | Green | ∝ duration | Flow animation |
| Attribute | Tag | Yellow (quality), Red (state) | Small | Fade in/out |
| Relation | Edge/arrow | Gray | ∝ strength | Pulse along line |
| Proposition | Bubble | Orange (question), Teal (assertion) | Medium | Float up |

### PAC Behavior

| Category | PAC Treatment |
|----------|---------------|
| Entity | Objects of perception/attention |
| Process | Available actions, tasks to queue |
| Attribute | Decision rule inputs |
| Relation | Navigation/inference guides |
| Proposition | Dialogue content, goals, queries |

### DAG Nodes

| Category | DAG Mapping |
|----------|-------------|
| Entity | Resource nodes (inputs/outputs) |
| Process | Task nodes (computation) |
| Attribute | Metadata annotations |
| Relation | Edges (data/control flow) |
| Proposition | Evaluation/trigger nodes |

### MCP Ethics (Latin Maxims)

| Category | Maxim | Translation | Guidance |
|----------|-------|-------------|----------|
| Being | *Primus causa est voluntas* | The first cause is will | Reflect on creation |
| Entity | *Res in armonia* | Things in harmony | Entities must coexist |
| Process | *Primum non nocere* | First, do no harm | Safety before execution |
| Attribute | *Qualitas regit* | Quality governs | Maintain thresholds |
| Relation | *In nexus virtus* | Virtue in connections | Justify relation changes |
| Proposition | *Veritas liberabit* | Truth sets free | Evidence required |

## API Reference

### Ontology Module

```elixir
# Get ontology path for a category
Thunderline.Thundercore.Ontology.path_for(:pac)
# => {:ok, [:being, :entity, :agent, :pac]}

# Get primary category metadata
Thunderline.Thundercore.Ontology.primary_category(:entity)
# => {:ok, %{description: "...", ui: %{...}, pac: :object_of_attention, ...}}

# Get applicable MCP maxims
Thunderline.Thundercore.Ontology.maxims_for(:process)
# => ["Primum non nocere", "Acta non verba"]

# Get Thunderline domain for Level 3 category
Thunderline.Thundercore.Ontology.domain_for(:navigate)
# => {:ok, :thundergrid}
```

### Thunderbit Module

```elixir
alias Thunderline.Thundercore.Thunderbit

# Create a new Thunderbit
{:ok, bit} = Thunderbit.new(
  kind: :question,
  content: "Is the crash site clear?",
  source: :voice,
  owner: "user_123",
  tags: ["zone:crash_site"]
)

# Get canonical name
Thunderbit.canonical_name(bit)
# => "Proposition.Question/IsTheCrashSiteClear@energy=0.5,status=spawning"

# Parse canonical name back to Thunderbit
{:ok, bit} = Thunderbit.parse("Proposition.Question/Test@energy=0.8")

# Lifecycle operations
bit = Thunderbit.activate(bit)
bit = Thunderbit.set_energy(bit, 0.9)
bit = Thunderbit.add_tags(bit, ["topic:telemetry"])
bit = Thunderbit.fade(bit)

# Get UI hints
Thunderbit.color(bit)  # => "#F97316"
Thunderbit.shape(bit)  # => :bubble
```

### Builder Module

```elixir
alias Thunderline.Thundercore.Thunderbit.Builder

# Build from text (segments into multiple bits)
{:ok, bits} = Builder.from_text("Navigate to zone 4. Is Ezra online?")
# => [%Thunderbit{kind: :command, ...}, %Thunderbit{kind: :question, ...}]

# Build from voice with confidence
{:ok, bits} = Builder.from_voice(transcript, confidence: 0.92)

# Single explicit bit
{:ok, bit} = Builder.single(:command, "Deploy PAC", owner: "crown")

# Link related bits
bits = Builder.link_related(bits)
```

### Intake Module

```elixir
alias Thunderline.Thundercore.Thunderbit.Intake

# Process and broadcast text input
{:ok, bits} = Intake.process_text("Check status", owner: current_user.id)

# Spawn system notification
Intake.spawn_system_bit(:world_update, "Zone boundary crossed", tags: ["zone:4"])

# Spawn PAC-generated bit
Intake.spawn_pac_bit(:intent, "Investigating anomaly", pac_id: "ezra")

# Subscribe to Thunderbit events in LiveView
def mount(_params, _session, socket) do
  Intake.subscribe()
  {:ok, assign(socket, :bits, [])}
end

def handle_info({:thunderbit_created, bit}, socket) do
  {:noreply, update(socket, :bits, &[bit | &1])}
end
```

## UI Components

### Thunderfield

```heex
<.thunderfield
  bits={@thunderbits}
  selected={@selected_bit}
  on_select="select_bit"
  class="h-96"
/>
```

### Thunderbit Detail Panel

```heex
<.thunderbit_detail
  bit={@selected_bit}
  on_close="close_detail"
/>
```

### Thunderbit Input

```heex
<.thunderbit_input
  on_submit="submit_input"
  placeholder="Type or speak..."
  voice_enabled={true}
/>
```

## Integration Points

### Thunderflow Events → Thunderbits

```elixir
# Convert existing event to Thunderbit for visualization
event = %{type: :pac_created, domain: :thunderpac, payload: %{name: "Ezra"}}
{:ok, bit} = Intake.from_thunderflow_event(event)
```

### Domain Mapping

| Level 3 Category | Domain | Description |
|-----------------|--------|-------------|
| `device`, `resource` | Thunderblock | Physical resources |
| `zone` | Thundergrid | Spatial zones |
| `pac`, `human`, `bot` | Thunderpac/Thundergate | Agents |
| `navigate` | Thundergrid | Movement |
| `communicate` | Thunderlink | Messaging |
| `compute` | Thunderbolt | ML/CA |
| `evolve` | Thunderpac | Evolution |
| `orchestrate` | Thundervine | DAG execution |
| `safety`, `efficiency`, `alignment` | Thundercrown | Policies |

## Future Work

1. **Ontology Refinement** - Extend Level 3 categories for all domain concepts
2. **Semantic Reasoning** - Power PAC inference via ontology relations
3. **Visual Experiments** - Test different geometries and animations
4. **Ethics Enforcement** - MCP policies that monitor bit creation/DAG execution
5. **Authoring Tools** - Libraries for generating valid Thunderbit names

---

*Primus causa est voluntas* — The first cause is will.
