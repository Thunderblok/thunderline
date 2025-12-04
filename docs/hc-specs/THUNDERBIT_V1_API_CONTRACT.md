# Thunderbit v1 API Contract

> **The Programmable Monad** — This document defines the canonical API for Thunderbits
> as base automata in the Thunderline system. All implementations MUST conform to this contract.

**Version**: 1.0.0  
**Status**: DRAFT  
**Last Updated**: 2025-01-20  
**HC Reference**: HC-60 (Thunderbit Resource & Stepper)

---

## 0. Design Philosophy

Thunderbits are **Leibnizian monads** — self-contained units with:
- Internal state (no direct access to other bits)
- Local rules (determine state transitions)
- Meta-rules (determine rule evolution)
- Complete isolation (all external effects mediated via Thundervine)

**Key Principle**: Thunderbits do NOT message each other directly. All causation flows 
through the **Thundervine Field** (DAG + FieldChannels).

---

## 1. Core Thunderbit Struct

```elixir
defmodule Thunderline.Thunderbolt.Thunderbit do
  @moduledoc """
  Base automaton unit in the Thunderline lattice.
  
  Implements the programmable monad pattern:
  - state: Current cell state (tensor or bitfield)
  - rules: Local CA transition rules (OuterTotalistic or custom)
  - meta_rules: Rules that modify rules at runtime
  - trace: History for debugging/audit (optional)
  """
  
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer
  
  @enforce_keys [:id, :coord]
  
  postgres do
    table "thunderbits"
    repo Thunderline.Repo
  end
  
  attributes do
    uuid_primary_key :id
    
    # === SPATIAL IDENTITY ===
    attribute :coord, :map do
      description "3D lattice position {x, y, z}"
      allow_nil? false
      public? true
    end
    
    attribute :zone_id, :string do
      description "Thunderbolt cluster this bit belongs to"
      allow_nil? true
      public? true
    end
    
    # === AUTOMATON STATE ===
    attribute :state, :map do
      description "Current cell state - bitfield or tensor representation"
      default %{value: 0, bits: []}
      public? true
    end
    
    attribute :rules, :map do
      description "Local CA transition rules (rule number, neighborhood, custom)"
      default %{rule_number: 110, neighborhood: :moore, radius: 1}
      public? true
    end
    
    attribute :meta_rules, {:array, :map} do
      description "Meta-rules for runtime rule modification"
      default []
      public? true
    end
    
    # === FIELD INTERACTION ===
    attribute :field_state, :map do
      description "Read-only snapshot from FieldChannels (gravity, mood, heat, etc.)"
      default %{}
      public? true
    end
    
    attribute :write_buffer, {:array, :map} do
      description "Pending writes to FieldChannels (processed by Thundervine)"
      default []
      public? true
    end
    
    # === PHYSICS PARAMETERS (from playbook) ===
    attribute :phi_phase, :float do
      description "φ_phase - oscillation phase"
      default 0.0
      public? true
      constraints min: 0.0, max: 1.0
    end
    
    attribute :sigma_flow, :float do
      description "σ_flow - information flow rate"
      default 0.0
      public? true
      constraints min: -1.0, max: 1.0
    end
    
    attribute :lambda_sensitivity, :float do
      description "λ̂_sensitivity - responsiveness to field changes"
      default 0.5
      public? true
      constraints min: 0.0, max: 1.0
    end
    
    attribute :trust_score, :float do
      description "Trust accumulator from successful interactions"
      default 0.5
      public? true
      constraints min: 0.0, max: 1.0
    end
    
    # === PRESENCE & ROUTING ===
    attribute :presence, :atom do
      description "Cell occupancy status"
      default :vacant
      constraints one_of: [:vacant, :occupied, :forwarding, :dormant]
      public? true
    end
    
    attribute :channel_id, :string do
      description "Active CAChannel ID (nil if idle)"
      allow_nil? true
      public? true
    end
    
    attribute :route_tags, {:array, :string} do
      description "Bloom filter of destination IDs for routing"
      default []
      public? true
    end
    
    # === LIFECYCLE ===
    attribute :status, :atom do
      description "Bit lifecycle state"
      default :spawned
      constraints one_of: [:spawned, :active, :suspended, :terminated]
      public? true
    end
    
    attribute :tick_count, :integer do
      description "Number of CA ticks this bit has processed"
      default 0
      public? true
    end
    
    # === TRACE (optional) ===
    attribute :trace_enabled, :boolean do
      description "Whether to record state history"
      default false
      public? true
    end
    
    attribute :trace, {:array, :map} do
      description "Recent state history (bounded circular buffer)"
      default []
      public? false
    end
    
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
  
  identities do
    identity :coord_unique, [:coord, :zone_id]
  end
  
  relationships do
    belongs_to :thunderbolt, Thunderline.Thunderbolt.Resources.Cluster do
      description "Parent Thunderbolt cluster"
      allow_nil? true
    end
  end
end
```

---

## 2. Protocol Functions

### 2.1 `tick/2` — The Heartbeat

```elixir
@spec tick(Thunderbit.t(), TickContext.t()) :: {:ok, Thunderbit.t()} | {:error, reason}

defmodule Thunderline.Thunderbolt.Protocol do
  @moduledoc "Core Thunderbit protocol operations"
  
  @doc """
  Execute one CA tick for a Thunderbit.
  
  The tick cycle:
  1. Read field state from Thundervine FieldChannels
  2. Apply local rules to compute next state
  3. Apply meta-rules to potentially modify rules
  4. Buffer writes for Thundervine
  5. Update trace if enabled
  """
  def tick(%Thunderbit{} = bit, %TickContext{} = ctx) do
    with {:ok, field_state} <- read_field_channels(bit.coord, ctx),
         {:ok, neighbors} <- get_neighbor_states(bit.coord, ctx),
         {:ok, next_state} <- apply_rules(bit, neighbors, field_state),
         {:ok, updated_rules} <- apply_meta_rules(bit, next_state, ctx),
         {:ok, writes} <- compute_field_writes(bit, next_state),
         {:ok, trace} <- maybe_update_trace(bit, next_state) do
      {:ok, %{bit |
        state: next_state,
        rules: updated_rules,
        field_state: field_state,
        write_buffer: writes,
        trace: trace,
        tick_count: bit.tick_count + 1
      }}
    end
  end
end
```

### 2.2 `spawn_bit/3` — The Birth Ritual

```elixir
@spec spawn_bit(coord :: map(), attrs :: map(), ctx :: SpawnContext.t()) 
  :: {:ok, Thunderbit.t()} | {:error, reason}

@doc """
Spawn a new Thunderbit at the given coordinate.

Responsibilities:
1. Validate coordinate is unoccupied
2. Apply zone policies (Thundercrown)
3. Initialize state from rules
4. Register in Thundervine graph
5. Emit `bit.spawned` event
"""
def spawn_bit(coord, attrs, ctx) do
  with :ok <- validate_coord_vacant(coord, ctx),
       :ok <- check_spawn_policy(coord, ctx),
       {:ok, initial_state} <- initialize_state(attrs),
       {:ok, bit} <- create_bit(coord, initial_state, attrs),
       :ok <- register_in_vine(bit, ctx),
       :ok <- emit_event(:bit_spawned, bit, ctx) do
    {:ok, bit}
  end
end
```

### 2.3 `apply_rules/3` — State Transition

```elixir
@spec apply_rules(Thunderbit.t(), neighbors :: [state()], field_state :: map())
  :: {:ok, state()} | {:error, reason}

@doc """
Compute next state using local CA rules.

The rules map specifies:
- rule_number: Classic CA rule (e.g., 110 for elementary CA)
- neighborhood: :von_neumann | :moore | :hex
- radius: Neighborhood radius
- custom: Optional custom rule function
"""
def apply_rules(%Thunderbit{rules: rules} = bit, neighbors, field_state) do
  case rules do
    %{custom: fun} when is_function(fun) ->
      fun.(bit.state, neighbors, field_state)
    
    %{rule_number: rule, neighborhood: :outer_totalistic} ->
      # Use existing OuterTotalistic module
      Thunderline.Thunderbolt.Cerebros.OuterTotalistic.apply_rule(
        rule,
        bit.state,
        neighbors,
        []
      )
    
    %{rule_number: rule} ->
      apply_elementary_rule(rule, bit.state, neighbors)
  end
end
```

### 2.4 `apply_meta_rules/3` — Rule Evolution

```elixir
@spec apply_meta_rules(Thunderbit.t(), next_state :: state(), ctx :: TickContext.t())
  :: {:ok, rules :: map()} | {:error, reason}

@doc """
Apply meta-rules to potentially modify the bit's rules.

Meta-rules enable:
- Adaptive behavior (learn from field state)
- Rule switching based on conditions
- Gradual rule parameter drift

IMPORTANT: Meta-rules are evaluated by Thunderforge, not inline.
This maintains separation between rule execution and rule modification.
"""
def apply_meta_rules(%Thunderbit{meta_rules: []} = bit, _next_state, _ctx) do
  {:ok, bit.rules}  # No meta-rules, rules unchanged
end

def apply_meta_rules(%Thunderbit{meta_rules: meta_rules} = bit, next_state, ctx) do
  # Delegate to Thunderforge for rule modification
  Thunderline.Thunderforge.MetaRuleEngine.evaluate(
    bit.rules,
    meta_rules,
    %{state: next_state, field: bit.field_state},
    ctx
  )
end
```

---

## 3. FieldChannel Interface

Thunderbits interact with the outside world ONLY through FieldChannels mediated by Thundervine.

### 3.1 Reading Field State

```elixir
@spec read_field_channels(coord :: map(), ctx :: TickContext.t()) :: {:ok, map()}

@doc """
Read current field values at this coordinate.

Returns map of channel → value:
%{
  gravity: -0.3,    # Local gravitational influence
  mood: 0.7,        # Emotional/social field
  heat: 0.5,        # Activity/energy level  
  signal: 0.0,      # Communication signal strength
  entropy: 0.2,     # Local disorder measure
  intent: :neutral, # Directional intent from neighbors
  reward: 0.1       # Reinforcement signal
}
"""
def read_field_channels(coord, ctx) do
  channels = [:gravity, :mood, :heat, :signal, :entropy, :intent, :reward]
  
  field_state = Enum.reduce(channels, %{}, fn channel, acc ->
    value = Thunderline.Thundervine.FieldChannel.read(channel, coord, ctx)
    Map.put(acc, channel, value)
  end)
  
  {:ok, field_state}
end
```

### 3.2 Writing to Field

```elixir
@spec compute_field_writes(Thunderbit.t(), next_state :: state()) :: {:ok, [write()]}

@doc """
Compute writes to buffer for Thundervine to process.

Writes are NOT applied directly - they go into write_buffer
and Thundervine processes them during the global tick phase.

This ensures:
- Synchronous global updates
- Field consistency across the lattice
- Proper causal ordering
"""
def compute_field_writes(%Thunderbit{} = bit, next_state) do
  writes = []
  
  # Example: if state crossed threshold, emit heat
  writes = if crossed_threshold?(bit.state, next_state, :activation) do
    [{:heat, bit.coord, 0.1} | writes]  # Emit heat pulse
  else
    writes
  end
  
  # Example: if generating signal, emit to signal channel
  writes = if next_state.signaling do
    [{:signal, bit.coord, next_state.signal_strength} | writes]
  else
    writes
  end
  
  {:ok, writes}
end
```

---

## 4. Neighbor Access

Thunderbits access neighbor states through Thundervine, NOT directly.

```elixir
@spec get_neighbor_states(coord :: map(), ctx :: TickContext.t()) 
  :: {:ok, [state()]} | {:error, reason}

@doc """
Get states of neighboring cells.

The neighborhood is determined by bit.rules.neighborhood:
- :von_neumann - 6 neighbors (±x, ±y, ±z)
- :moore - 26 neighbors (3³ - 1)
- :hex - 12 neighbors (hexagonal lattice)

States are fetched from Thundervine's spatial index,
NOT by direct reference to neighbor bits.
"""
def get_neighbor_states(%{x: x, y: y, z: z} = coord, ctx) do
  offsets = get_neighborhood_offsets(ctx.neighborhood || :von_neumann)
  
  neighbor_coords = Enum.map(offsets, fn {dx, dy, dz} ->
    %{x: x + dx, y: y + dy, z: z + dz}
  end)
  
  # Query Thundervine for neighbor states
  states = Thunderline.Thundervine.SpatialIndex.get_states(neighbor_coords, ctx)
  {:ok, states}
end

defp get_neighborhood_offsets(:von_neumann) do
  [{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}]
end

defp get_neighborhood_offsets(:moore) do
  for dx <- -1..1, dy <- -1..1, dz <- -1..1, {dx, dy, dz} != {0, 0, 0}, do: {dx, dy, dz}
end

defp get_neighborhood_offsets(:hex) do
  # 12 directions in hexagonal close-packing
  # (Implementation follows Fibonacci clustering: 12 primary directions)
  [
    {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0},
    {1, 1, 0}, {-1, -1, 0}, {1, -1, 0}, {-1, 1, 0},
    {0, 0, 1}, {0, 0, -1}, {1, 0, 1}, {-1, 0, -1}
  ]
end
```

---

## 5. Trace & Debugging

```elixir
@max_trace_length 100

@spec maybe_update_trace(Thunderbit.t(), next_state :: state()) :: {:ok, trace :: [map()]}

@doc """
Update trace buffer if tracing is enabled.

Trace entries include:
- tick: Tick number
- state_hash: Hash of state for efficient comparison
- rules_version: Current rules version
- timestamp: Wall clock time
"""
def maybe_update_trace(%Thunderbit{trace_enabled: false} = bit, _next_state) do
  {:ok, bit.trace}
end

def maybe_update_trace(%Thunderbit{trace_enabled: true, trace: trace} = bit, next_state) do
  entry = %{
    tick: bit.tick_count + 1,
    state_hash: hash_state(next_state),
    rules_version: hash_rules(bit.rules),
    timestamp: DateTime.utc_now()
  }
  
  updated_trace = [entry | trace] |> Enum.take(@max_trace_length)
  {:ok, updated_trace}
end
```

---

## 6. Ash Actions

```elixir
actions do
  defaults [:read, :destroy]
  
  create :spawn do
    description "Spawn a new Thunderbit at a coordinate"
    accept [:coord, :zone_id, :rules, :meta_rules, :trace_enabled]
    
    change set_attribute(:status, :spawned)
    change set_attribute(:tick_count, 0)
    change set_attribute(:presence, :vacant)
  end
  
  update :tick do
    description "Execute one CA tick"
    accept []
    
    argument :tick_context, :map do
      allow_nil? false
    end
    
    # Tick logic handled by change module
    change Thunderline.Thunderbolt.Changes.ExecuteTick
  end
  
  update :activate do
    description "Activate a spawned bit"
    accept []
    change set_attribute(:status, :active)
    change set_attribute(:presence, :occupied)
  end
  
  update :suspend do
    description "Suspend a bit (pause ticking)"
    accept []
    change set_attribute(:status, :suspended)
  end
  
  update :terminate do
    description "Terminate a bit"
    accept []
    change set_attribute(:status, :terminated)
    change set_attribute(:presence, :vacant)
  end
  
  update :update_rules do
    description "Update local CA rules (via Thunderforge)"
    accept [:rules, :meta_rules]
  end
  
  update :assign_channel do
    description "Assign bit to a CAChannel"
    accept [:channel_id]
    change set_attribute(:presence, :forwarding)
  end
  
  read :by_coord do
    description "Find bit by coordinate"
    argument :coord, :map, allow_nil?: false
    argument :zone_id, :string, allow_nil?: true
    
    filter expr(coord == ^arg(:coord) and zone_id == ^arg(:zone_id))
  end
  
  read :by_zone do
    description "List all bits in a zone"
    argument :zone_id, :string, allow_nil?: false
    filter expr(zone_id == ^arg(:zone_id))
  end
  
  read :active_in_channel do
    description "List bits forwarding for a channel"
    argument :channel_id, :string, allow_nil?: false
    filter expr(channel_id == ^arg(:channel_id) and presence == :forwarding)
  end
end
```

---

## 7. Context Structs

### 7.1 TickContext

```elixir
defmodule Thunderline.Thunderbolt.TickContext do
  @moduledoc "Context passed to tick operations"
  
  defstruct [
    :tick_number,      # Global tick counter
    :zone_id,          # Current zone
    :neighborhood,     # Neighborhood type override
    :field_snapshot,   # Pre-fetched field state (optimization)
    :actor,            # Requesting entity (for auth)
    :trace_all,        # Force tracing for all bits
    timeout_ms: 5000
  ]
end
```

### 7.2 SpawnContext

```elixir
defmodule Thunderline.Thunderbolt.SpawnContext do
  @moduledoc "Context passed to spawn operations"
  
  defstruct [
    :zone_id,
    :parent_id,        # Parent Thunderbolt cluster
    :policies,         # Active Thundercrown policies
    :actor,
    :initial_field     # Initial field values to read
  ]
end
```

---

## 8. Events

Thunderbits emit events to Thunderflow:

| Event | Payload | When |
|-------|---------|------|
| `bit.spawned` | `{bit_id, coord, zone_id}` | New bit created |
| `bit.activated` | `{bit_id}` | Bit transitions to active |
| `bit.ticked` | `{bit_id, tick_count, state_hash}` | Tick completed |
| `bit.rules_changed` | `{bit_id, old_rules, new_rules}` | Meta-rule modified rules |
| `bit.suspended` | `{bit_id, reason}` | Bit suspended |
| `bit.terminated` | `{bit_id, reason}` | Bit terminated |
| `bit.field_write` | `{bit_id, channel, coord, value}` | Write buffered |

---

## 9. Integration Points

### 9.1 Thundervine (Field/DAG)

```elixir
# Thunderbits register in Thundervine graph at spawn
Thunderline.Thundervine.register_bit(bit)

# Field reads go through Thundervine channels
Thunderline.Thundervine.FieldChannel.read(channel, coord, ctx)

# Field writes are processed by Thundervine in bulk
Thunderline.Thundervine.FieldChannel.process_writes(write_buffer)

# Neighbor states fetched from Thundervine spatial index
Thunderline.Thundervine.SpatialIndex.get_states(coords, ctx)
```

### 9.2 Thunderforge (Meta-rules)

```elixir
# Meta-rule evaluation delegated to Thunderforge
Thunderline.Thunderforge.MetaRuleEngine.evaluate(rules, meta_rules, context, ctx)

# Rule validation
Thunderline.Thunderforge.RuleValidator.validate(rules)
```

### 9.3 Thundercrown (Policies)

```elixir
# Spawn policy check
Thunderline.Thundercrown.PolicyEngine.check_spawn(coord, ctx)

# Zone capacity limits
Thunderline.Thundercrown.PolicyEngine.check_zone_capacity(zone_id, ctx)
```

### 9.4 OuterTotalistic (CA Rules)

```elixir
# Existing CA rule engine (stays pure)
Thunderline.Thunderbolt.Cerebros.OuterTotalistic.apply_rule(rule, state, neighbors, opts)

# Cycle detection for rule analysis
Thunderline.Thunderbolt.Cerebros.Cycles.find_cycles(sequence)
```

---

## 10. Clustering Constants

Per High Command synthesis (Fibonacci literal numbers):

```elixir
@doc "12 primary directions in hexagonal lattice"
@hex_directions 12

@doc "Thunderbits per Thunderbolt cluster"
@bits_per_bolt 144  # 12 × 12

@doc "Thunderbolts per zone"
@bolts_per_zone 1728  # 12 × 144

@doc "Total bits per zone"
@bits_per_zone 248_832  # 144 × 1728
```

---

## 11. Error Handling

```elixir
# Spawn errors
{:error, :coord_occupied}
{:error, :zone_full}
{:error, {:policy_denied, reason}}

# Tick errors
{:error, :bit_suspended}
{:error, :bit_terminated}
{:error, {:field_read_timeout, channel}}
{:error, {:rule_evaluation_failed, reason}}

# Meta-rule errors
{:error, {:invalid_meta_rule, index}}
{:error, :meta_rule_cycle_detected}
```

---

## 12. Compliance Checklist

For any Thunderbit implementation:

- [ ] Bits do NOT directly reference other bits
- [ ] All neighbor access goes through Thundervine
- [ ] All field interaction uses FieldChannels
- [ ] Meta-rules evaluated by Thunderforge, not inline
- [ ] Events emitted to Thunderflow on state changes
- [ ] Policies checked via Thundercrown at spawn
- [ ] Trace bounded to prevent memory growth
- [ ] Coordinate + zone_id forms unique identity
- [ ] Write buffer cleared after Thundervine processes

---

## 13. Migration Path

From existing `THUNDERBIT_BEHAVIOR_CONTRACT.md`:

| Old Concept | New Concept | Notes |
|-------------|-------------|-------|
| `category` | Removed | Bits are homogeneous automata |
| `role` | Determined by `rules` | Role emerges from behavior |
| `content` | `state` | Raw semantic → tensor state |
| `energy` | `phi_phase`, `sigma_flow` | Split into physics params |
| `links` | Via Thundervine graph | No direct links |
| `edges` | Via Thundervine DAG | Edges are causal, not direct |
| `ctx` | `TickContext` / `SpawnContext` | Explicit context types |

The semantic/cognitive layer (`spawn_bit/3`, `bind/3`, `link/4`) becomes a 
higher-level API built ON TOP of the base automaton Thunderbit.

---

## 14. Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | 2025-01-20 | Initial automaton-focused contract |

---

**This contract is the foundation. Build up, not around.** ⚡
