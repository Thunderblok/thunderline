# Thunderbit v2 Migration Guide

> **From Automaton to Quantum Substrate**
>
> This document bridges the v1 Thunderbit API Contract to the v2 Quantum Substrate Specification.
> All new implementations SHOULD follow v2 patterns; v1 remains valid for transition period.

**Created**: December 5, 2025  
**Last Updated**: December 5, 2025  
**Related**: [THUNDERBIT_V1_API_CONTRACT.md](THUNDERBIT_V1_API_CONTRACT.md), [HC_QUANTUM_SUBSTRATE_SPEC.md](HC_QUANTUM_SUBSTRATE_SPEC.md)

---

## Version Comparison Summary

| Aspect | v1 (Current) | v2 (Target) |
|--------|--------------|-------------|
| **State Model** | Binary/float state map | Ternary state `:neg \| :zero \| :pos` |
| **Physics** | φ_phase, σ_flow, λ_sensitivity | + bias, coupling, temperature (Ising) |
| **Memory** | Trace buffer only | MIRAS deep MLP memory |
| **Clock** | Simple tick counter | 4-phase Switch/Hold/Release/Relax |
| **Rules** | OuterTotalistic/custom | + Reversible Toffoli/Feynman gates |
| **Fault Tolerance** | Basic retry | TQCA-style dropout resilience |

---

## Field Additions (v2)

Add these fields to `Thunderbit` struct:

```elixir
# === TERNARY STATE (HC-86, HC-87) ===
attribute :state, :atom do
  description "Ternary state value"
  default :zero
  constraints one_of: [:neg, :zero, :pos]
  public? true
end

attribute :state_vector, {:array, :float} do
  description "Multi-channel state vector (NCA compatible)"
  default []
  public? true
end

# === ISING PHYSICS (HC-87) ===
attribute :bias, :float do
  description "External field / policy pressure"
  default 0.0
  public? true
end

attribute :coupling, :float do
  description "Local energy coupling coefficient"
  default 1.0
  public? true
end

attribute :temperature, :float do
  description "Noise/randomness parameter"
  default 0.1
  constraints min: 0.0
  public? true
end

# === MIRAS MEMORY (HC-90, HC-91) ===
attribute :surprise_metric, :float do
  description "Current |predicted - observed| gradient magnitude"
  default 0.0
  public? true
end

attribute :retention_gate, :float do
  description "Memory decay control [0, 1]"
  default 1.0
  constraints min: 0.0, max: 1.0
  public? true
end

attribute :momentum_surprise, :float do
  description "β-EMA smoothed surprise"
  default 0.0
  public? true
end

# === RULE VERSION (HC-89) ===
attribute :rule_version, :integer do
  description "Which CA rule version applies"
  default 1
  public? true
end
```

---

## New Modules (HC-86 through HC-95)

### HC-86: TernaryState

```elixir
defmodule Thunderline.Thunderbolt.TernaryState do
  @type ternary :: :neg | :zero | :pos
  
  def to_balanced(:neg), do: -1
  def to_balanced(:zero), do: 0
  def to_balanced(:pos), do: 1
  
  def from_balanced(-1), do: :neg
  def from_balanced(0), do: :zero
  def from_balanced(1), do: :pos
  
  def ternary_not(:neg), do: :pos
  def ternary_not(:zero), do: :zero
  def ternary_not(:pos), do: :neg
  
  def ternary_and(a, b), do: min_ternary(a, b)
  def ternary_or(a, b), do: max_ternary(a, b)
end
```

### HC-88: 4-Phase Clock

Replace simple tick counter with phase-aware clock:

```elixir
defmodule Thunderline.Thundercore.Clock do
  @phases [:switch, :hold, :release, :relax]
  
  def current_phase(), do: GenServer.call(__MODULE__, :current_phase)
  
  def on_phase(phase, callback) when phase in @phases do
    GenServer.cast(__MODULE__, {:subscribe, phase, callback})
  end
end
```

### HC-89: Reversible Rules

Add reversibility check to rule application:

```elixir
defmodule Thunderline.Thunderbolt.ReversibleRules do
  def reversible?(rule_fn) do
    # Test bijection over all input combinations
    inputs = for a <- [:neg, :zero, :pos],
                 b <- [:neg, :zero, :pos],
                 c <- [:neg, :zero, :pos], do: {a, b, c}
    outputs = Enum.map(inputs, &rule_fn.(&1))
    length(Enum.uniq(outputs)) == length(inputs)
  end
  
  def feynman_ternary(control, target) do
    Integer.mod(to_balanced(control) + to_balanced(target), 3)
    |> from_balanced()
  end
end
```

---

## Migration Strategy

### Phase 1: Add Fields (Non-breaking)

1. Add new attributes with defaults
2. Generate migration: `mix ash.codegen add_thunderbit_v2_fields`
3. Existing code continues to work

### Phase 2: Add Modules (Parallel)

1. Create `TernaryState`, `ReversibleRules` modules
2. Add `Thundercore.Clock` GenServer
3. Create `Thunderpac.MemoryModule` GenServer

### Phase 3: Integrate (Gradual)

1. Update `tick/2` to use 4-phase clock
2. Add surprise metric computation
3. Enable ternary state for new bits

### Phase 4: Validate (Testing)

1. Run fault tolerance simulations
2. Verify reversibility of rules
3. Test MIRAS memory write gating

---

## Backward Compatibility

- v1 `state: %{value: 0}` maps to v2 `state: :zero`
- v1 `rules.rule_number` continues to work
- v1 `tick/2` signature unchanged
- v1 events still emitted

New v2 features are **opt-in** via:
- `rule_version: 2` enables ternary rules
- `trace_enabled: :miras` enables surprise tracking
- Clock phase callbacks are optional

---

## See Also

- [HC_QUANTUM_SUBSTRATE_SPEC.md](HC_QUANTUM_SUBSTRATE_SPEC.md) - Full v2 specification
- [THUNDERBIT_V1_API_CONTRACT.md](THUNDERBIT_V1_API_CONTRACT.md) - Current v1 contract
- [THUNDERBIT_BEHAVIOR_CONTRACT.md](THUNDERBIT_BEHAVIOR_CONTRACT.md) - Semantic layer contract

---

**Migrate incrementally. Break nothing. Build everything.** ⚡
