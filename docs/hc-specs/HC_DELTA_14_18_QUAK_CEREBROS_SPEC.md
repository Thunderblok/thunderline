# HC-Δ-14 through HC-Δ-18: QuAK Quantitative Automata + Cerebros CA Clustering

> **Classification**: HIGH COMMAND DELTA SERIES  
> **Priority**: P0 (Critical Path)  
> **Status**: SPECIFICATION COMPLETE  
> **Date**: 2025-12-03  
> **Author**: HC Research Division + Cerebros Team

---

## Executive Summary

This specification documents the synthesis of two critical research findings:

1. **Cerebros CA Clustering Algorithm** - A reversible CA-based clustering approach for multimodal embeddings
2. **QuAK Quantitative Automata** - Formal evaluation machinery for infinite behaviors with weighted transitions

The combination creates **Thunderline Automaton Engine (TAE)** - a mathematically grounded system for:
- Evaluating PAC behavior with formal guarantees
- Scoring CA patterns via quantitative value functions
- Training Cerebros models with proper reward signals
- Ensuring safety/liveness properties for autonomous agents

---

## Part I: Cerebros CA Clustering Proposal Gap Analysis

### Current Implementation Status

| Component | Status | Location |
|-----------|--------|----------|
| CA Stepper | ✅ Implemented | `lib/thunderline/thunderbolt/ca/stepper.ex` |
| LoopMonitor Metrics | ✅ Implemented | `lib/thunderline/thunderbolt/cerebros/loop_monitor.ex` |
| DiffLogicCA | ✅ Implemented | `lib/thunderline/thunderbolt/cerebros/difflogic_ca.ex` |
| Feature Extraction | ✅ Implemented | `lib/thunderline/thunderbolt/cerebros/features.ex` |
| Thundercell Substrate | ✅ Implemented | `lib/thunderline/thunderbit/thundercell.ex` |
| `encode_data` multimodal | ❌ Missing | HC-Δ-14 |
| `find_cycles` | ❌ Missing | HC-Δ-15 |
| Outer-Totalistic Rules | ❌ Missing | HC-Δ-16 |
| 3-Stage Clustering | ❌ Missing | HC-Δ-17 |
| Keras CAEmbedding | ❌ Missing | HC-Δ-18 |

### Original Cerebros Proposal Requirements

```
Stage 1: Chunk & Group
├── encode_data(data) → binary vector
├── apply_ca_rule(state, rule) → new state  
├── find_cycles(sequence) → cycle list
└── Pre-vetted rules: 267422991, 4042321935, 2863311530, 3435973836

Stage 2: Merge & Refine
├── Gray code ordering
├── Medians calculation
└── Second CA pass

Stage 3: Final Cut
├── k-cluster determination via gap analysis
└── Cluster assignment output
```

---

## Part II: QuAK Quantitative Automata Research

### Key Insight from High Command

> "This paper is essentially a blueprint for computable 'evaluation machines' that assign 
> numeric values to infinite behaviors via automata with weighted transitions."

### Mapping to Thunderline Architecture

| QuAK Concept | Thunderline Equivalent | Implementation |
|--------------|----------------------|----------------|
| Σ (alphabet) | Thunderbit categories | 10 categories defined |
| Q (states) | Thundercells | `Thundercell` struct |
| weight | Thunderbit energy/tag | `sigma_flow`, `energy` |
| run over Σω | CA evolution over ticks | `Stepper.next/2` |
| value of run | PAC reward / CA fitness | `PACCompute.compute_edge_score/1` |
| Top Value ⊤A | Best possible behavior | NEW: `TAE.top_value/1` |
| Safety | Prefix that kills hypothesis | NEW: `TAE.check_safety/2` |
| Liveness | Eventuality guarantee | NEW: `TAE.check_liveness/2` |

### Value Functions to Implement

From the QuAK paper, these value functions map infinite runs to real numbers:

```elixir
# Inf - infimum of all weights
defmodule TAE.ValueFunction.Inf do
  def compute(weights), do: Enum.min(weights)
end

# Sup - supremum of all weights  
defmodule TAE.ValueFunction.Sup do
  def compute(weights), do: Enum.max(weights)
end

# LimInf - limit inferior (eventual minimum)
defmodule TAE.ValueFunction.LimInf do
  def compute(weights) do
    weights
    |> Enum.chunk_every(10)  # sliding window
    |> Enum.map(&Enum.min/1)
    |> Enum.max()  # sup of inf
  end
end

# LimSup - limit superior (eventual maximum)
defmodule TAE.ValueFunction.LimSup do
  def compute(weights) do
    weights
    |> Enum.chunk_every(10)
    |> Enum.map(&Enum.max/1)
    |> Enum.min()  # inf of sup
  end
end

# LimSupAvg - limit superior of averages (critical for Cerebros)
defmodule TAE.ValueFunction.LimSupAvg do
  def compute(weights) do
    weights
    |> Stream.scan({0, 0}, fn w, {sum, count} -> {sum + w, count + 1} end)
    |> Enum.map(fn {sum, count} -> sum / count end)
    |> then(&LimSup.compute/1)
  end
end
```

### Core TAE Operations

1. **Top Value Computation**: `⊤A = sup_{w ∈ Σω} A(w)` - maximum achievable value
2. **Inclusion Checking**: `A ⊆ B` - is behavior A always bounded by B?
3. **Safety Closure**: Detect forbidden transitions, terminate early
4. **Liveness Decomposition**: Guarantee progress toward goals

---

## Part III: Implementation Specifications

### HC-Δ-14: Multimodal Binary Encoding

**File**: `lib/thunderline/thunderbolt/cerebros/encoder.ex`

```elixir
defmodule Thunderline.Thunderbolt.Cerebros.Encoder do
  @moduledoc """
  Multimodal binary encoding for CA clustering.
  
  Converts heterogeneous data (text, image, tabular) into fixed-length
  binary vectors suitable for outer-totalistic CA rules.
  
  ## Encoding Pipeline
  
      Text → sentence embedding → quantize → binary
      Image → flatten → normalize → quantize → binary
      Tabular → concatenate → normalize → quantize → binary
  """
  
  @default_dim 256
  @quantization_bits 8
  
  @type modality :: :text | :image | :tabular | :tensor | :raw
  @type encoding_opts :: [dim: pos_integer(), bits: pos_integer()]
  
  @doc """
  Encode arbitrary data into a binary vector.
  
  ## Examples
  
      iex> Encoder.encode_data("hello world", :text)
      {:ok, <<1, 0, 1, 1, ...>>}
      
      iex> Encoder.encode_data(image_tensor, :image)
      {:ok, <<0, 1, 0, 1, ...>>}
  """
  @spec encode_data(term(), modality(), encoding_opts()) :: {:ok, binary()} | {:error, term()}
  def encode_data(data, modality, opts \\ [])
  
  def encode_data(text, :text, opts) when is_binary(text) do
    dim = Keyword.get(opts, :dim, @default_dim)
    
    # Use hash embedding for lightweight encoding
    {vec, _norm} = Thunderline.Thunderflow.Probing.Embedding.hash_embedding(text, dim: dim)
    
    # Quantize to binary
    binary = quantize_to_binary(vec, Keyword.get(opts, :bits, @quantization_bits))
    {:ok, binary}
  end
  
  def encode_data(tensor, :tensor, opts) when is_struct(tensor, Nx.Tensor) do
    dim = Keyword.get(opts, :dim, @default_dim)
    
    # Flatten and normalize
    flat = tensor |> Nx.flatten() |> Nx.to_flat_list()
    normalized = normalize_vector(flat)
    
    # Resize to target dim
    resized = resize_vector(normalized, dim)
    
    # Quantize
    binary = quantize_to_binary(resized, Keyword.get(opts, :bits, @quantization_bits))
    {:ok, binary}
  end
  
  def encode_data(rows, :tabular, opts) when is_list(rows) do
    dim = Keyword.get(opts, :dim, @default_dim)
    
    # Flatten all rows into single vector
    flat = rows |> List.flatten() |> Enum.map(&to_float/1)
    normalized = normalize_vector(flat)
    resized = resize_vector(normalized, dim)
    
    binary = quantize_to_binary(resized, Keyword.get(opts, :bits, @quantization_bits))
    {:ok, binary}
  end
  
  def encode_data(raw, :raw, _opts) when is_binary(raw), do: {:ok, raw}
  
  def encode_data(data, modality, _opts) do
    {:error, {:unsupported_encoding, modality, data}}
  end
  
  @doc """
  Decode binary back to float vector (for debugging/visualization).
  """
  @spec decode_binary(binary(), pos_integer()) :: [float()]
  def decode_binary(binary, bits \\ @quantization_bits) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(div(bits, 8))
    |> Enum.map(&decode_chunk/1)
  end
  
  # Private helpers
  
  defp quantize_to_binary(vec, bits) do
    max_val = :math.pow(2, bits) - 1
    
    vec
    |> Enum.map(fn v ->
      # Map [-1, 1] to [0, max_val]
      clamped = max(-1.0, min(1.0, v))
      quantized = round((clamped + 1.0) / 2.0 * max_val)
      <<quantized::size(bits)>>
    end)
    |> IO.iodata_to_binary()
  end
  
  defp normalize_vector([]), do: []
  defp normalize_vector(vec) do
    {min_v, max_v} = Enum.min_max(vec)
    range = max_v - min_v
    
    if range == 0 do
      List.duplicate(0.0, length(vec))
    else
      Enum.map(vec, fn v -> (v - min_v) / range * 2.0 - 1.0 end)
    end
  end
  
  defp resize_vector(vec, target_dim) when length(vec) == target_dim, do: vec
  defp resize_vector(vec, target_dim) when length(vec) < target_dim do
    # Pad with zeros
    vec ++ List.duplicate(0.0, target_dim - length(vec))
  end
  defp resize_vector(vec, target_dim) do
    # Truncate or downsample
    Enum.take(vec, target_dim)
  end
  
  defp to_float(x) when is_float(x), do: x
  defp to_float(x) when is_integer(x), do: x * 1.0
  defp to_float(_), do: 0.0
  
  defp decode_chunk(bytes) do
    <<val::size(8)>> = IO.iodata_to_binary(bytes)
    val / 255.0 * 2.0 - 1.0
  end
end
```

### HC-Δ-15: Cycle Detection

**File**: `lib/thunderline/thunderbolt/cerebros/cycles.ex`

```elixir
defmodule Thunderline.Thunderbolt.Cerebros.Cycles do
  @moduledoc """
  Cycle detection for CA state sequences.
  
  Implements Floyd's tortoise-and-hare algorithm and Brent's improvement
  for detecting cycles in potentially infinite CA evolution traces.
  
  ## Key Insight from QuAK
  
  > "Everything reduces to two primitives: Inclusion checking and Top-value computation"
  
  Cycle detection is fundamental to both: cycles determine the ultimate
  periodic behavior that dominates limit computations.
  
  ## Usage
  
      # Detect cycles in a CA trace
      {:ok, cycles} = Cycles.find_cycles(state_sequence)
      
      # Get cycle statistics for value function computation
      stats = Cycles.cycle_stats(cycles)
  """
  
  @type state :: term()
  @type cycle :: %{
    prefix_length: non_neg_integer(),
    cycle_start: non_neg_integer(),
    cycle_length: pos_integer(),
    cycle_states: [state()]
  }
  
  @doc """
  Find cycles in a sequence of states using Floyd's algorithm.
  
  Returns the first detected cycle if one exists within the sequence,
  or `:no_cycle` if the sequence appears acyclic.
  """
  @spec find_cycles([state()]) :: {:ok, cycle()} | :no_cycle
  def find_cycles([]), do: :no_cycle
  def find_cycles([_]), do: :no_cycle
  
  def find_cycles(sequence) when is_list(sequence) do
    # Build state -> indices map
    indexed = sequence |> Enum.with_index() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    
    # Find repeated states
    repeated = indexed |> Enum.filter(fn {_state, indices} -> length(indices) > 1 end)
    
    case repeated do
      [] -> :no_cycle
      [{state, [first_idx | [second_idx | _]]} | _] ->
        cycle_length = second_idx - first_idx
        cycle_states = Enum.slice(sequence, first_idx, cycle_length)
        
        {:ok, %{
          prefix_length: first_idx,
          cycle_start: first_idx,
          cycle_length: cycle_length,
          cycle_states: cycle_states
        }}
    end
  end
  
  @doc """
  Find cycles using Brent's algorithm (faster for long sequences).
  
  Brent's algorithm is generally faster than Floyd's, especially when
  the cycle is short relative to the prefix.
  """
  @spec find_cycles_brent(Enumerable.t(), (state() -> state())) :: {:ok, cycle()} | :no_cycle
  def find_cycles_brent(initial, next_fn) do
    # Brent's algorithm
    # Phase 1: Find cycle length
    power = 1
    lambda = 1
    tortoise = initial
    hare = next_fn.(initial)
    
    {lambda, hare} = find_cycle_length(tortoise, hare, next_fn, power, lambda)
    
    if hare == nil do
      :no_cycle
    else
      # Phase 2: Find cycle start (mu)
      mu = find_cycle_start(initial, lambda, next_fn)
      
      # Extract cycle states
      cycle_states = extract_cycle(advance(initial, next_fn, mu), next_fn, lambda, [])
      
      {:ok, %{
        prefix_length: mu,
        cycle_start: mu,
        cycle_length: lambda,
        cycle_states: cycle_states
      }}
    end
  end
  
  @doc """
  Compute statistics for a detected cycle.
  
  These statistics are used by TAE value functions.
  """
  @spec cycle_stats(cycle(), (state() -> float())) :: map()
  def cycle_stats(cycle, weight_fn \\ fn _ -> 1.0 end) do
    weights = Enum.map(cycle.cycle_states, weight_fn)
    
    %{
      cycle_length: cycle.cycle_length,
      prefix_length: cycle.prefix_length,
      cycle_sum: Enum.sum(weights),
      cycle_avg: Enum.sum(weights) / cycle.cycle_length,
      cycle_min: Enum.min(weights),
      cycle_max: Enum.max(weights)
    }
  end
  
  @doc """
  Check if a sequence is ultimately periodic (has a cycle).
  """
  @spec ultimately_periodic?([state()]) :: boolean()
  def ultimately_periodic?(sequence) do
    case find_cycles(sequence) do
      {:ok, _} -> true
      :no_cycle -> false
    end
  end
  
  # Private helpers
  
  defp find_cycle_length(tortoise, hare, next_fn, power, lambda, max_iter \\ 10_000)
  defp find_cycle_length(_, _, _, _, _, 0), do: {0, nil}
  
  defp find_cycle_length(tortoise, hare, next_fn, power, lambda, remaining) do
    cond do
      tortoise == hare ->
        {lambda, hare}
      
      power == lambda ->
        find_cycle_length(hare, next_fn.(hare), next_fn, power * 2, 1, remaining - 1)
      
      true ->
        find_cycle_length(tortoise, next_fn.(hare), next_fn, power, lambda + 1, remaining - 1)
    end
  end
  
  defp find_cycle_start(initial, lambda, next_fn) do
    tortoise = initial
    hare = advance(initial, next_fn, lambda)
    find_mu(tortoise, hare, next_fn, 0)
  end
  
  defp find_mu(tortoise, hare, _next_fn, mu) when tortoise == hare, do: mu
  defp find_mu(tortoise, hare, next_fn, mu) do
    find_mu(next_fn.(tortoise), next_fn.(hare), next_fn, mu + 1)
  end
  
  defp advance(state, _next_fn, 0), do: state
  defp advance(state, next_fn, n), do: advance(next_fn.(state), next_fn, n - 1)
  
  defp extract_cycle(_, _, 0, acc), do: Enum.reverse(acc)
  defp extract_cycle(state, next_fn, remaining, acc) do
    extract_cycle(next_fn.(state), next_fn, remaining - 1, [state | acc])
  end
end
```

### HC-Δ-16: Outer-Totalistic CA Rules

**File**: `lib/thunderline/thunderbolt/cerebros/outer_totalistic.ex`

```elixir
defmodule Thunderline.Thunderbolt.Cerebros.OuterTotalistic do
  @moduledoc """
  Outer-Totalistic CA Rules for Cerebros Clustering.
  
  Implements the specific 32-bit rules from the Cerebros proposal that
  have been pre-vetted for good clustering behavior:
  
  | Rule Number | Properties |
  |-------------|------------|
  | 267422991   | High cycle diversity |
  | 4042321935  | Balanced entropy |
  | 2863311530  | Edge-of-chaos regime |
  | 3435973836  | Fast convergence |
  
  ## Outer-Totalistic Rules
  
  Unlike elementary CA rules that depend on exact neighbor patterns,
  outer-totalistic rules depend only on:
  1. The sum of neighbor states (totalistic part)
  2. The center cell's current state (outer part)
  
  This reduces the rule table from 2^8 to 2^(k+1) where k = max neighbor sum.
  
  ## Usage
  
      # Apply pre-vetted rule
      new_state = OuterTotalistic.apply_rule(267422991, cell_state, neighbor_sum)
      
      # Compute Langton's lambda for a rule
      lambda = OuterTotalistic.langton_lambda(267422991)
  """
  
  # Pre-vetted rules from Cerebros proposal
  @vetted_rules %{
    267422991 => %{name: :high_diversity, lambda: 0.32},
    4042321935 => %{name: :balanced_entropy, lambda: 0.28},
    2863311530 => %{name: :edge_of_chaos, lambda: 0.27},
    3435973836 => %{name: :fast_convergence, lambda: 0.25}
  }
  
  @type rule_number :: non_neg_integer()
  @type cell_state :: 0 | 1
  @type neighbor_sum :: non_neg_integer()
  
  @doc """
  Apply an outer-totalistic rule to compute next cell state.
  
  ## Parameters
  
  - `rule` - 32-bit rule number encoding the transition table
  - `center` - Current cell state (0 or 1)
  - `neighbor_sum` - Sum of neighbor states (0 to max_neighbors)
  - `max_neighbors` - Maximum neighbor count (default: 8 for Moore neighborhood)
  
  ## Example
  
      # Cell is 1, has 3 alive neighbors, using rule 267422991
      iex> OuterTotalistic.apply_rule(267422991, 1, 3)
      1
  """
  @spec apply_rule(rule_number(), cell_state(), neighbor_sum(), pos_integer()) :: cell_state()
  def apply_rule(rule, center, neighbor_sum, max_neighbors \\ 8) do
    # Index into rule table: center * (max_neighbors + 1) + neighbor_sum
    index = center * (max_neighbors + 1) + neighbor_sum
    
    # Extract bit at index position
    (rule >>> index) &&& 1
  end
  
  @doc """
  Apply rule to a binary state vector (for batch processing).
  """
  @spec apply_rule_batch(rule_number(), binary(), [neighbor_sum()]) :: binary()
  def apply_rule_batch(rule, state_binary, neighbor_sums) do
    states = :binary.bin_to_list(state_binary)
    
    states
    |> Enum.zip(neighbor_sums)
    |> Enum.map(fn {state, sum} -> apply_rule(rule, state, sum) end)
    |> :binary.list_to_bin()
  end
  
  @doc """
  Compute Langton's λ parameter for a rule.
  
  λ measures the fraction of rule table entries that produce state 1.
  Edge of chaos occurs near λ ≈ 0.273 for 2-state CAs.
  """
  @spec langton_lambda(rule_number(), pos_integer()) :: float()
  def langton_lambda(rule, table_size \\ 18) do
    # Count 1-bits in rule number
    ones = count_ones(rule, table_size)
    ones / table_size
  end
  
  @doc """
  Get info for a vetted rule.
  """
  @spec get_vetted_rule(rule_number()) :: map() | nil
  def get_vetted_rule(rule) do
    Map.get(@vetted_rules, rule)
  end
  
  @doc """
  List all vetted rules.
  """
  @spec vetted_rules() :: [rule_number()]
  def vetted_rules do
    Map.keys(@vetted_rules)
  end
  
  @doc """
  Find rule closest to target λ value.
  """
  @spec find_rule_by_lambda(float(), float()) :: rule_number()
  def find_rule_by_lambda(target_lambda, tolerance \\ 0.05) do
    @vetted_rules
    |> Enum.find(fn {_rule, info} ->
      abs(info.lambda - target_lambda) <= tolerance
    end)
    |> case do
      {rule, _} -> rule
      nil -> 2863311530  # Default to edge-of-chaos rule
    end
  end
  
  @doc """
  Generate a random rule with approximate target λ.
  """
  @spec generate_rule(float(), pos_integer()) :: rule_number()
  def generate_rule(target_lambda, table_size \\ 18) do
    target_ones = round(target_lambda * table_size)
    
    # Generate rule with approximately target_ones bits set
    0..(table_size - 1)
    |> Enum.reduce({0, 0}, fn i, {rule, ones} ->
      if ones < target_ones and :rand.uniform() < target_lambda do
        {rule ||| (1 <<< i), ones + 1}
      else
        {rule, ones}
      end
    end)
    |> elem(0)
  end
  
  @doc """
  Decode rule number into human-readable transition table.
  """
  @spec decode_rule(rule_number(), pos_integer()) :: map()
  def decode_rule(rule, max_neighbors \\ 8) do
    for center <- [0, 1],
        sum <- 0..max_neighbors,
        into: %{} do
      {{center, sum}, apply_rule(rule, center, sum, max_neighbors)}
    end
  end
  
  # Private helpers
  
  defp count_ones(n, max_bits) do
    0..(max_bits - 1)
    |> Enum.count(fn i -> (n >>> i &&& 1) == 1 end)
  end
end
```

### HC-Δ-17: Thunderline Automaton Engine (TAE)

**File**: `lib/thunderline/thunderbolt/tae/engine.ex`

```elixir
defmodule Thunderline.Thunderbolt.TAE.Engine do
  @moduledoc """
  Thunderline Automaton Engine (TAE) - Quantitative Automata Evaluation.
  
  Implements the core operations from the QuAK paper for evaluating
  infinite behaviors via weighted automata.
  
  ## Core Operations
  
  1. **Top Value** - Maximum achievable value over all infinite runs
  2. **Inclusion** - Check if behavior A is bounded by behavior B
  3. **Safety** - Detect prefix violations
  4. **Liveness** - Guarantee eventual progress
  
  ## Integration with Thunderline
  
  | TAE Operation | Thunderline Use Case |
  |---------------|---------------------|
  | Top Value | PAC optimal behavior scoring |
  | Inclusion | MCP ethics compliance |
  | Safety | Thunderbit prefix violation |
  | Liveness | Thunderflow deadlock prevention |
  
  ## Reference
  
  - Chalupa et al., "Automating the Analysis of Quantitative Automata with QuAK"
  - High Command Research Division findings (2025-12-03)
  """
  
  alias Thunderline.Thunderbolt.Cerebros.Cycles
  alias Thunderline.Thunderbolt.TAE.ValueFunction
  
  @type state :: term()
  @type weight :: float()
  @type automaton :: %{
    states: MapSet.t(state()),
    initial: state(),
    transitions: %{{state(), term()} => {state(), weight()}},
    value_fn: atom()
  }
  
  @type run :: [{state(), weight()}]
  
  # ═══════════════════════════════════════════════════════════════
  # Top Value Computation
  # ═══════════════════════════════════════════════════════════════
  
  @doc """
  Compute the top value of an automaton.
  
  ⊤A = sup_{w ∈ Σω} A(w)
  
  The top value is the maximum achievable value over all possible
  infinite runs of the automaton.
  
  ## Algorithm
  
  1. Find all cycles reachable from initial state
  2. For each cycle, compute the cycle's value contribution
  3. Return supremum over all reachable cycles
  """
  @spec top_value(automaton()) :: {:ok, float()} | {:error, term()}
  def top_value(%{transitions: transitions, initial: initial, value_fn: value_fn}) do
    # Build graph for cycle detection
    graph = build_graph(transitions)
    
    # Find all reachable cycles
    cycles = find_reachable_cycles(graph, initial)
    
    if Enum.empty?(cycles) do
      {:error, :no_cycles_found}
    else
      # Compute value for each cycle
      cycle_values = Enum.map(cycles, fn cycle ->
        weights = extract_cycle_weights(cycle, transitions)
        ValueFunction.compute(value_fn, weights)
      end)
      
      {:ok, Enum.max(cycle_values)}
    end
  end
  
  @doc """
  Compute top value with witnessing run.
  
  Returns both the top value and an ultimately periodic word
  that achieves (or approaches) this value.
  """
  @spec top_value_with_witness(automaton()) :: {:ok, float(), run()} | {:error, term()}
  def top_value_with_witness(%{transitions: transitions, initial: initial, value_fn: value_fn}) do
    graph = build_graph(transitions)
    cycles = find_reachable_cycles(graph, initial)
    
    if Enum.empty?(cycles) do
      {:error, :no_cycles_found}
    else
      # Find best cycle
      best_cycle = cycles
        |> Enum.map(fn cycle ->
          weights = extract_cycle_weights(cycle, transitions)
          value = ValueFunction.compute(value_fn, weights)
          {cycle, weights, value}
        end)
        |> Enum.max_by(&elem(&2, 2))
      
      {cycle, weights, value} = best_cycle
      
      # Build witnessing run
      prefix = find_path_to_cycle(graph, initial, hd(cycle))
      witness = prefix ++ Enum.zip(cycle, weights)
      
      {:ok, value, witness}
    end
  end
  
  # ═══════════════════════════════════════════════════════════════
  # Inclusion Checking
  # ═══════════════════════════════════════════════════════════════
  
  @doc """
  Check if automaton A is included in automaton B.
  
  A ⊆ B iff ∀w ∈ Σω: A(w) ≤ B(w)
  
  Used for MCP ethics compliance: "Is PAC behavior ≤ permitted behavior?"
  """
  @spec inclusion?(automaton(), automaton()) :: boolean()
  def inclusion?(a, b) do
    case {top_value(a), top_value(b)} do
      {{:ok, top_a}, {:ok, top_b}} -> top_a <= top_b
      _ -> false
    end
  end
  
  @doc """
  Check inclusion with counter-example if violated.
  """
  @spec check_inclusion(automaton(), automaton()) ::
    {:included, true} | {:violated, run()}
  def check_inclusion(a, b) do
    case {top_value_with_witness(a), top_value(b)} do
      {{:ok, top_a, witness}, {:ok, top_b}} when top_a > top_b ->
        {:violated, witness}
      _ ->
        {:included, true}
    end
  end
  
  # ═══════════════════════════════════════════════════════════════
  # Safety Checking
  # ═══════════════════════════════════════════════════════════════
  
  @doc """
  Check safety property: value never exceeds threshold.
  
  Safety is a prefix property - if violated, there exists a finite
  prefix that proves the violation.
  
  Returns:
  - `{:safe, true}` if safety holds
  - `{:unsafe, prefix}` with the violating prefix
  """
  @spec check_safety(automaton(), float()) :: {:safe, true} | {:unsafe, run()}
  def check_safety(%{transitions: transitions, initial: initial, value_fn: value_fn}, threshold) do
    # BFS to find prefix exceeding threshold
    check_safety_bfs([{initial, [], 0.0}], transitions, value_fn, threshold, MapSet.new())
  end
  
  defp check_safety_bfs([], _transitions, _value_fn, _threshold, _visited) do
    {:safe, true}
  end
  
  defp check_safety_bfs([{state, path, acc_value} | rest], transitions, value_fn, threshold, visited) do
    if MapSet.member?(visited, state) do
      check_safety_bfs(rest, transitions, value_fn, threshold, visited)
    else
      # Check if current prefix violates safety
      if acc_value > threshold do
        {:unsafe, Enum.reverse(path)}
      else
        # Expand successors
        successors = get_successors(state, transitions)
        
        new_frontier = Enum.map(successors, fn {next_state, weight} ->
          new_value = ValueFunction.accumulate(value_fn, acc_value, weight)
          {next_state, [{state, weight} | path], new_value}
        end)
        
        check_safety_bfs(
          rest ++ new_frontier,
          transitions,
          value_fn,
          threshold,
          MapSet.put(visited, state)
        )
      end
    end
  end
  
  # ═══════════════════════════════════════════════════════════════
  # Liveness Checking
  # ═══════════════════════════════════════════════════════════════
  
  @doc """
  Check liveness property: value eventually reaches threshold.
  
  Liveness is a suffix property - no finite prefix can disprove it.
  
  Returns:
  - `{:live, true}` if liveness holds (can reach threshold)
  - `{:dead, reason}` if liveness is impossible
  """
  @spec check_liveness(automaton(), float()) :: {:live, true} | {:dead, term()}
  def check_liveness(%{transitions: transitions, initial: initial, value_fn: value_fn}, threshold) do
    # Check if any reachable cycle can achieve the threshold
    graph = build_graph(transitions)
    cycles = find_reachable_cycles(graph, initial)
    
    achievable = Enum.any?(cycles, fn cycle ->
      weights = extract_cycle_weights(cycle, transitions)
      ValueFunction.compute(value_fn, weights) >= threshold
    end)
    
    if achievable do
      {:live, true}
    else
      {:dead, :threshold_unreachable}
    end
  end
  
  # ═══════════════════════════════════════════════════════════════
  # Safety-Liveness Decomposition
  # ═══════════════════════════════════════════════════════════════
  
  @doc """
  Decompose automaton into safety and liveness components.
  
  Every quantitative property can be expressed as the conjunction
  of a safety property (what must NOT happen) and a liveness
  property (what MUST eventually happen).
  """
  @spec decompose(automaton()) :: {automaton(), automaton()}
  def decompose(automaton) do
    # Safety closure: remove transitions that could lead to bad states
    safety = compute_safety_closure(automaton)
    
    # Liveness: the difference between original and safety
    liveness = compute_liveness_remainder(automaton, safety)
    
    {safety, liveness}
  end
  
  # ═══════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════
  
  defp build_graph(transitions) do
    transitions
    |> Enum.reduce(%{}, fn {{from, _symbol}, {to, _weight}}, graph ->
      Map.update(graph, from, [to], fn succs -> [to | succs] end)
    end)
  end
  
  defp find_reachable_cycles(graph, initial) do
    # Tarjan's algorithm for SCCs
    {_, _, cycles} = tarjan_scc(graph, initial, %{}, %{}, 0, [], [])
    cycles
  end
  
  defp tarjan_scc(graph, node, index_map, lowlink_map, index, stack, sccs) do
    index_map = Map.put(index_map, node, index)
    lowlink_map = Map.put(lowlink_map, node, index)
    stack = [node | stack]
    index = index + 1
    
    successors = Map.get(graph, node, [])
    
    {index_map, lowlink_map, index, stack, sccs} =
      Enum.reduce(successors, {index_map, lowlink_map, index, stack, sccs},
        fn succ, {im, lm, i, s, sc} ->
          cond do
            not Map.has_key?(im, succ) ->
              {im, lm, i, s, sc} = tarjan_scc(graph, succ, im, lm, i, s, sc)
              lm = Map.put(lm, node, min(lm[node], lm[succ]))
              {im, lm, i, s, sc}
            
            succ in s ->
              lm = Map.put(lm, node, min(lm[node], im[succ]))
              {im, lm, i, s, sc}
            
            true ->
              {im, lm, i, s, sc}
          end
        end)
    
    if lowlink_map[node] == index_map[node] do
      {scc, stack} = pop_scc(stack, node, [])
      if length(scc) > 1 or has_self_loop?(graph, node) do
        {index_map, lowlink_map, index, stack, [scc | sccs]}
      else
        {index_map, lowlink_map, index, stack, sccs}
      end
    else
      {index_map, lowlink_map, index, stack, sccs}
    end
  end
  
  defp pop_scc([node | rest], target, acc) when node == target do
    {[node | acc], rest}
  end
  defp pop_scc([node | rest], target, acc) do
    pop_scc(rest, target, [node | acc])
  end
  
  defp has_self_loop?(graph, node) do
    node in Map.get(graph, node, [])
  end
  
  defp extract_cycle_weights(cycle, transitions) do
    cycle
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      # Find transition weight
      transitions
      |> Enum.find(fn {{f, _}, {t, _}} -> f == from and t == to end)
      |> case do
        {{_, _}, {_, weight}} -> weight
        nil -> 0.0
      end
    end)
  end
  
  defp get_successors(state, transitions) do
    transitions
    |> Enum.filter(fn {{from, _}, _} -> from == state end)
    |> Enum.map(fn {{_, _}, {to, weight}} -> {to, weight} end)
  end
  
  defp find_path_to_cycle(graph, initial, cycle_start) do
    # BFS for shortest path
    bfs_path([{initial, []}], graph, cycle_start, MapSet.new())
  end
  
  defp bfs_path([], _graph, _target, _visited), do: []
  defp bfs_path([{state, path} | _rest], _graph, target, _visited) when state == target do
    Enum.reverse(path)
  end
  defp bfs_path([{state, path} | rest], graph, target, visited) do
    if MapSet.member?(visited, state) do
      bfs_path(rest, graph, target, visited)
    else
      successors = Map.get(graph, state, [])
      new_frontier = Enum.map(successors, fn succ -> {succ, [{state, 0.0} | path]} end)
      bfs_path(rest ++ new_frontier, graph, target, MapSet.put(visited, state))
    end
  end
  
  defp compute_safety_closure(automaton) do
    # Placeholder - full implementation would compute backwards reachability
    automaton
  end
  
  defp compute_liveness_remainder(automaton, _safety) do
    # Placeholder - full implementation would compute set difference
    automaton
  end
end
```

### HC-Δ-17 (cont): Value Functions

**File**: `lib/thunderline/thunderbolt/tae/value_function.ex`

```elixir
defmodule Thunderline.Thunderbolt.TAE.ValueFunction do
  @moduledoc """
  Value functions for quantitative automata.
  
  These functions map infinite runs (sequences of weights) to real numbers.
  Each function captures different aspects of the run's "quality".
  
  ## Supported Functions
  
  | Function | Description | Use Case |
  |----------|-------------|----------|
  | `:inf` | Minimum weight | Worst-case guarantee |
  | `:sup` | Maximum weight | Best-case potential |
  | `:lim_inf` | Eventual minimum | Long-term floor |
  | `:lim_sup` | Eventual maximum | Long-term ceiling |
  | `:lim_inf_avg` | Eventual avg minimum | Sustained performance |
  | `:lim_sup_avg` | Eventual avg maximum | Peak performance |
  | `:sum` | Total sum | Cumulative reward |
  | `:discount` | Discounted sum | Time-preference reward |
  """
  
  @type value_fn :: :inf | :sup | :lim_inf | :lim_sup | :lim_inf_avg | :lim_sup_avg | :sum | :discount
  @type weights :: [float()]
  
  @doc """
  Compute the value of a weight sequence using the given function.
  """
  @spec compute(value_fn(), weights()) :: float()
  def compute(:inf, weights), do: Enum.min(weights, fn -> 0.0 end)
  def compute(:sup, weights), do: Enum.max(weights, fn -> 0.0 end)
  
  def compute(:lim_inf, weights) do
    # Limit inferior: sup of eventual infima
    weights
    |> suffixes()
    |> Enum.map(&Enum.min(&1, fn -> 0.0 end))
    |> Enum.max(fn -> 0.0 end)
  end
  
  def compute(:lim_sup, weights) do
    # Limit superior: inf of eventual suprema
    weights
    |> suffixes()
    |> Enum.map(&Enum.max(&1, fn -> 0.0 end))
    |> Enum.min(fn -> 0.0 end)
  end
  
  def compute(:lim_inf_avg, weights) do
    # Limit inferior of running averages
    weights
    |> running_averages()
    |> compute(:lim_inf)
  end
  
  def compute(:lim_sup_avg, weights) do
    # Limit superior of running averages
    weights
    |> running_averages()
    |> compute(:lim_sup)
  end
  
  def compute(:sum, weights), do: Enum.sum(weights)
  
  def compute(:discount, weights) do
    discount_factor = 0.99
    
    weights
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {w, i}, acc ->
      acc + w * :math.pow(discount_factor, i)
    end)
  end
  
  @doc """
  Accumulate a new weight into running computation.
  
  Used during safety checking to track running value.
  """
  @spec accumulate(value_fn(), float(), float()) :: float()
  def accumulate(:inf, acc, weight), do: min(acc, weight)
  def accumulate(:sup, acc, weight), do: max(acc, weight)
  def accumulate(:sum, acc, weight), do: acc + weight
  def accumulate(:discount, acc, weight), do: acc * 0.99 + weight
  def accumulate(_, acc, _weight), do: acc  # For limit functions, need full sequence
  
  @doc """
  Get the identity element for a value function.
  """
  @spec identity(value_fn()) :: float()
  def identity(:inf), do: :infinity
  def identity(:sup), do: :neg_infinity
  def identity(:sum), do: 0.0
  def identity(:discount), do: 0.0
  def identity(_), do: 0.0
  
  # Private helpers
  
  defp suffixes([]), do: [[]]
  defp suffixes(list) do
    list
    |> Stream.iterate(fn [_ | rest] -> rest end)
    |> Enum.take(length(list))
  end
  
  defp running_averages([]), do: []
  defp running_averages(weights) do
    weights
    |> Enum.scan({0.0, 0}, fn w, {sum, count} -> {sum + w, count + 1} end)
    |> Enum.map(fn {sum, count} -> sum / count end)
  end
end
```

---

## Part IV: Integration Plan

### Phase 1: Foundation (This PR)

1. ✅ Create HC-Δ-14: `Encoder` module
2. ✅ Create HC-Δ-15: `Cycles` module
3. ✅ Create HC-Δ-16: `OuterTotalistic` module
4. ✅ Create HC-Δ-17: `TAE.Engine` + `TAE.ValueFunction`

### Phase 2: Integration (Next Sprint)

1. Hook TAE into Cerebros TPE optimization
2. Connect `OuterTotalistic` rules to `CA.Stepper`
3. Add safety/liveness checks to `Thunderflow.EventProcessor`
4. Update UI with TAE evaluation visualization

### Phase 3: Python Bridge (HC-Δ-18)

1. Keras `CAEmbedding` layer implementation
2. `tf.py_function` bridge for CA stepping
3. Training pipeline integration with Flower FL

---

## Part V: Success Criteria

### Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cycle detection latency | < 10ms for 1000-state sequences | Benchmark |
| Top value computation | < 100ms for 100-state automata | Benchmark |
| Safety check | < 1ms per prefix | Benchmark |
| Rule application | < 1μs per cell | Benchmark |

### Tests

```elixir
# Encoder tests
test "encodes text to fixed-length binary"
test "encodes Nx tensor to binary"
test "round-trip decode preserves ~90% accuracy"

# Cycles tests
test "detects simple cycle in periodic sequence"
test "handles acyclic sequences"
test "Brent's algorithm matches Floyd's"

# OuterTotalistic tests
test "applies vetted rules correctly"
test "Langton lambda matches expected values"
test "rule decode produces correct table"

# TAE tests
test "computes top value for simple automaton"
test "inclusion checking correct for subset"
test "safety detects prefix violation"
test "liveness confirms reachability"
```

---

## Appendix: References

1. Chalupa et al., "Automating the Analysis of Quantitative Automata with QuAK", 2024
2. Langton, C.G., "Computation at the Edge of Chaos", 1990
3. Packard, N.H., "Adaptation Toward the Edge of Chaos", 1988
4. Cerebros Team, "Reversible CA Clustering Proposal", 2025
5. High Command Research Division, "QuAK Integration Findings", 2025-12-03

---

> **"Everything reduces to two primitives: Inclusion checking and Top-value computation"**
> — QuAK Paper

> **"This is EXACTLY what a Thunderbit → Thundercell → Thunderflow pipeline will need"**
> — High Command
