# HC-Δ Implementation Specification

> **Status**: HC-Δ-5.3 COMPLETE ✅ | HC-Δ-5.4+ Ready for Implementation  
> **Date**: December 1, 2025  
> **Updated**: Reflecting actual implementation state  
> **Prerequisite**: HC-Δ-5 (Thunderbit Category Protocol) ✅ COMPLETE

This document captures the HC-Δ roadmap and implementation status.

---

## Table of Contents

1. [HC-Δ-5.3: Thunderfield MVP](#hc-δ-53-thunderfield-mvp) ✅ **COMPLETE**
2. [HC-Δ-5.4: Category + Ontology Integration](#hc-δ-54-category--ontology-integration)
3. [HC-Δ-6: Variable Reference Pattern](#hc-δ-6-variable-reference-pattern)
4. [HC-Δ-8: Thunderbit Training Exporter](#hc-δ-8-thunderbit-training-exporter)
5. [HC-Δ-9: Labeling & Embedding Infrastructure](#hc-δ-9-labeling--embedding-infrastructure)
6. [Implementation Order](#implementation-order)

---

## HC-Δ-5.3: Thunderfield MVP ✅ COMPLETE

**Priority**: P0  
**Goal**: "If I type a sentence in the console, I see at least 1–3 Thunderbits appear and link in the field."  
**Status**: ✅ **FULLY IMPLEMENTED**

### Implementation Summary

The complete Thunderfield MVP was implemented across these files:

| Component | File | Status |
|-----------|------|--------|
| **Protocol** | `lib/thunderline/thunderbit/protocol.ex` | ✅ Complete |
| **Context** | `lib/thunderline/thunderbit/context.ex` | ✅ Complete |
| **UIContract** | `lib/thunderline/thunderbit/ui_contract.ex` | ✅ Complete (~350 lines) |
| **Demo** | `lib/thunderline/thunderbit/demo.ex` | ✅ Complete |
| **IntakePipeline** | `lib/thunderline/thunderprism/intake_pipeline.ex` | ✅ Complete (~280 lines) |
| **ThunderfieldLive** | `lib/thunderline_web/live/thunderfield_live.ex` | ✅ Complete |
| **Thunderfield Components** | `lib/thunderline_web/live/components/thunderfield.ex` | ✅ Complete |

### Architecture (Actual)

```
User Input
    ↓
ThunderfieldLive (LiveView)
    ↓ phx-submit="submit_input"
Demo.intake/2 or IntakePipeline.process/2
    ↓ (spawns bits via Protocol)
UIContract.broadcast/3
    ↓ PubSub "thunderbits:lobby"
ThunderfieldLive.handle_info/2
    ↓ (merges bits, computes stats)
Thunderfield.thunderfield component
    ↓ (JS Hook renders canvas)
Visual Thunderbits with edges
```

### 5.3-A: UIContract ✅ IMPLEMENTED

**File**: `lib/thunderline/thunderbit/ui_contract.ex`

**Actual Implementation Highlights**:
- `to_dto/1` - Converts Thunderbit to slim UI DTO with geometry, category, energy
- `to_dtos/2` - Bulk conversion with edge linking
- `edge_to_dto/1` - Edge DTO for visualization lines
- `broadcast/3` - PubSub to `"thunderbits:lobby"` with event types:
  - `:created` → `{:thunderbit_spawn, %{bits: [...], edges: [...]}}`
  - `:updated` → `{:thunderbit_update, ...}`
  - `:retired` → `{:thunderbit_retire, ...}`
  - `:moved` → `{:thunderbit_move, ...}`
  - `:linked` → `{:thunderbit_link, ...}`

### 5.3-B: Demo Module ✅ IMPLEMENTED

**File**: `lib/thunderline/thunderbit/demo.ex`

**Key Functions**:
- `intake/2` - Main text → bits flow: spawns sensory + cognitive, links with `:feeds` relation
- `run/2` - Full demo with broadcast included
- `classify_intent/2` - Continuation for intent classification (question, command, memory, etc.)
- `sample_dtos/0` - For testing/inspection

### 5.3-C: IntakePipeline ✅ IMPLEMENTED

**File**: `lib/thunderline/thunderprism/intake_pipeline.ex`

**Enhanced Processing**:
- `process/2` - Main API: text → bits with broadcast
- `stream/3` - Progressive processing with callback for each chunk
- `parse_chunks/1` - Sentence-level splitting
- `classify/1` - Keyword-based categorization (question, command, memory, etc.)
- `spawn_sensory_bit/3` - Spawns sensory bit with content
- `spawn_cognitive_bit/3` - Spawns cognitive bit linked to sensory
- ML Tap integration for decision trail logging

### 5.3-D: ThunderfieldLive ✅ IMPLEMENTED

**File**: `lib/thunderline_web/live/thunderfield_live.ex`

**Features**:
- Subscribes to `"thunderbits:lobby"` PubSub on connect
- Form handling with `to_form/1` pattern
- Event handlers: `submit_input`, `run_demo`, `select_bit`, `close_detail`
- PubSub handlers: spawn, update, retire, move, link, state
- Stats tracking: total, sensory, cognitive, linked counts
- Uses `Thunderfield.thunderfield`, `thunderbit_detail`, `thunderbit_input` components

### 5.3-E: Thunderfield Components ✅ IMPLEMENTED

**File**: `lib/thunderline_web/live/components/thunderfield.ex`

**Components**:
- `thunderfield/1` - Main canvas with JS hook, grid, legend, bit container
- `thunderbit_static/1` - No-JS fallback render
- `bit_shape/1` - 8 shape variants (circle, hex, capsule, bubble, diamond, star, triangle, square)
- `thunderbit_detail/1` - Detail panel with metrics, tags, ontology path, maxims
- `thunderbit_input/1` - Input form with optional voice toggle
- `legend_item/1` - Legend color/label items

---

## HC-Δ-5.4: Category + Ontology Integration

**Priority**: P0 (parallel with 5.3)  
**Goal**: Complete the Ontology → Category → Protocol → UI triangle.

### 5.4-A: Category ↔ Upper Ontology Resolution

**File**: `lib/thunderline/thunderbit/category.ex` (extend existing)

```elixir
defmodule Thunderline.Thunderbit.Category do
  @moduledoc """
  Category system with Upper Ontology integration.
  """

  @ontology_paths %{
    sensory: ["Being", "Process", "SensoryProcess"],
    cognitive: ["Being", "Process", "CognitiveProcess"],
    memory: ["Being", "Object", "InformationObject", "Memory"],
    motor: ["Being", "Process", "MotorProcess"],
    social: ["Being", "Process", "SocialProcess"],
    ethical: ["Being", "Quality", "EthicalQuality"],
    dataset: ["Being", "Object", "InformationArtifact", "Dataset"],
    document: ["Being", "Object", "InformationArtifact", "Document"],
    result: ["Being", "Object", "InformationArtifact", "Result"]
  }

  @doc """
  Get the Upper Ontology path for a category.
  """
  @spec ontology_path(category :: atom()) :: [String.t()]
  def ontology_path(category) when is_atom(category) do
    Map.get(@ontology_paths, category, ["Being", "Object"])
  end

  @doc """
  Check if wiring between two categories is valid.
  """
  @spec wiring_valid?(from_category :: atom(), to_category :: atom(), relation :: atom()) :: boolean()
  def wiring_valid?(from, to, relation) do
    rules = wiring_rules()
    
    case Map.get(rules, {from, to}) do
      nil -> false
      allowed_relations -> relation in allowed_relations
    end
  end

  @doc """
  Get all valid wiring rules.
  """
  @spec wiring_rules() :: map()
  def wiring_rules do
    %{
      # Sensory can feed cognitive
      {:sensory, :cognitive} => [:feeds, :triggers, :informs],
      
      # Cognitive can modulate other cognitive, memory, motor
      {:cognitive, :cognitive} => [:feeds, :inhibits, :modulates, :competes],
      {:cognitive, :memory} => [:stores, :retrieves, :updates],
      {:cognitive, :motor} => [:triggers, :inhibits, :modulates],
      {:cognitive, :ethical} => [:validates, :constrains],
      
      # Memory can inform cognitive
      {:memory, :cognitive} => [:informs, :primes, :biases],
      
      # Ethical can gate anything
      {:ethical, :cognitive} => [:gates, :constrains, :validates],
      {:ethical, :motor} => [:gates, :constrains, :validates],
      {:ethical, :social} => [:gates, :constrains, :validates],
      
      # Social interactions
      {:social, :social} => [:communicates, :influences, :references],
      {:social, :cognitive} => [:informs, :requests],
      
      # Data types
      {:dataset, :cognitive} => [:feeds, :informs],
      {:document, :cognitive} => [:feeds, :informs],
      {:result, :cognitive} => [:feeds, :informs]
    }
  end
end
```

### 5.4-B: Ethics Hook Integration

**File**: `lib/thunderline/thunderbit/protocol.ex` (extend)

Add to spawn_bit and link functions:

```elixir
# In Protocol.spawn_bit/3, before creating the bit:
defp check_spawn_policy(category, attrs, ctx) do
  case Thunderline.Thundercrown.PolicyEngine.allow?(:thunderbit_spawn, %{
    category: category,
    attrs: attrs,
    ctx: ctx
  }) do
    {:ok, :allowed} -> :ok
    {:ok, :denied, reason} -> {:error, {:policy_denied, reason}}
    _ -> :ok  # Default allow if policy engine unavailable
  end
end

# In Protocol.link/4, before creating the edge:
defp check_link_policy(from_id, to_id, relation, ctx) do
  case Thunderline.Thundercrown.PolicyEngine.allow?(:thunderbit_link, %{
    from_id: from_id,
    to_id: to_id,
    relation: relation,
    ctx: ctx
  }) do
    {:ok, :allowed} -> :ok
    {:ok, :denied, reason} -> {:error, {:policy_denied, reason}}
    _ -> :ok  # Default allow
  end
end
```

---

## HC-Δ-6: Variable Reference Pattern

**Priority**: P0  
**Goal**: Reduce token usage by 80%+ through variable references instead of data copy.

### Core Concept

Tool outputs become named variables that agents pass by reference:

```
# Instead of:
analyze_cohort(users: [10,000 rows of JSON...])

# Agent says:
analyze_cohort(users: $weekly_visits)

# Orchestrator resolves $weekly_visits behind the scenes
```

### 6-A: Extend Context with Variables

**File**: `lib/thunderline/thunderbit/context.ex` (extend)

```elixir
defmodule Thunderline.Thunderbit.Context do
  @moduledoc """
  Extended Context with variable reference support.
  """

  defstruct [
    :session_id,
    :pac_id,
    bits_by_id: %{},
    edges: [],
    events: [],
    attributes: %{},
    vars: %{}  # NEW: Variable name -> bit_id mapping
  ]

  @doc """
  Assign a variable name to a Thunderbit.
  """
  @spec assign_var(ctx :: t(), name :: String.t(), bit :: map()) :: {:ok, t()}
  def assign_var(ctx, name, bit) when is_binary(name) do
    {:ok, %{ctx | vars: Map.put(ctx.vars, name, bit.id)}}
  end

  @doc """
  Resolve a variable reference to its Thunderbit.
  
  Supports:
    - "$var_name" - direct variable
    - "$var_name.field" - field access (returns the field value)
  """
  @spec resolve_var(ctx :: t(), ref :: String.t()) :: {:ok, map() | term()} | {:error, :not_found}
  def resolve_var(ctx, "$" <> rest) do
    case String.split(rest, ".", parts: 2) do
      [var_name] ->
        resolve_simple_var(ctx, var_name)
      
      [var_name, field] ->
        with {:ok, bit} <- resolve_simple_var(ctx, var_name) do
          {:ok, get_in(bit, [:attrs, String.to_existing_atom(field)])}
        end
    end
  end
  def resolve_var(_ctx, _ref), do: {:error, :not_a_variable}

  defp resolve_simple_var(ctx, var_name) do
    case Map.fetch(ctx.vars, var_name) do
      {:ok, bit_id} ->
        case Map.fetch(ctx.bits_by_id, bit_id) do
          {:ok, bit} -> {:ok, bit}
          :error -> {:error, :bit_not_found}
        end
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  List all available variables.
  """
  @spec list_vars(ctx :: t()) :: [{String.t(), String.t()}]
  def list_vars(ctx) do
    Enum.map(ctx.vars, fn {name, bit_id} ->
      bit = Map.get(ctx.bits_by_id, bit_id)
      {name, bit && bit.category}
    end)
  end

  @doc """
  Check if a string contains variable references.
  """
  @spec has_var_refs?(value :: term()) :: boolean()
  def has_var_refs?(value) when is_binary(value), do: String.starts_with?(value, "$")
  def has_var_refs?(value) when is_map(value) do
    Enum.any?(value, fn {_k, v} -> has_var_refs?(v) end)
  end
  def has_var_refs?(_), do: false
end
```

### 6-B: Argument Resolver

**File**: `lib/thunderline/thunderbit/arg_resolver.ex`

```elixir
defmodule Thunderline.Thunderbit.ArgResolver do
  @moduledoc """
  Resolves variable references in tool/action arguments.
  
  Runs OUTSIDE the LLM - substitutes $var references with actual data
  before passing to tools.
  """

  alias Thunderline.Thunderbit.Context

  @doc """
  Resolve all variable references in an arguments map.
  """
  @spec resolve(args :: map(), ctx :: Context.t()) :: {:ok, map()} | {:error, term()}
  def resolve(args, ctx) when is_map(args) do
    resolve_map(args, ctx)
  end

  defp resolve_map(map, ctx) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_value(value, ctx) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        {:error, reason} -> {:halt, {:error, {key, reason}}}
      end
    end)
  end

  defp resolve_value("$" <> _ = ref, ctx) do
    Context.resolve_var(ctx, ref)
  end

  defp resolve_value(value, ctx) when is_map(value) do
    resolve_map(value, ctx)
  end

  defp resolve_value(value, ctx) when is_list(value) do
    results = Enum.map(value, &resolve_value(&1, ctx))
    
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, v} -> v end)}
      error -> error
    end
  end

  defp resolve_value(value, _ctx), do: {:ok, value}

  @doc """
  Extract variable names used in arguments (for dependency tracking).
  """
  @spec extract_var_names(args :: term()) :: [String.t()]
  def extract_var_names(args) do
    extract_refs(args, [])
    |> Enum.uniq()
  end

  defp extract_refs("$" <> rest, acc) do
    var_name = rest |> String.split(".") |> hd()
    [var_name | acc]
  end
  defp extract_refs(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {_k, v}, a -> extract_refs(v, a) end)
  end
  defp extract_refs(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &extract_refs/2)
  end
  defp extract_refs(_, acc), do: acc
end
```

### 6-C: Tool Output → Variable Registration

**File**: `lib/thunderline/thunderbit/tool_bridge.ex`

```elixir
defmodule Thunderline.Thunderbit.ToolBridge do
  @moduledoc """
  Bridge between tool execution and Thunderbit variable system.
  
  Automatically converts large tool outputs to named Thunderbits
  that can be referenced by $var_name.
  """

  alias Thunderline.Thunderbit.{Protocol, Context, ArgResolver}
  alias Thunderline.Thunderprism.UIContract

  @large_result_threshold 1000  # bytes

  @doc """
  Execute a tool with variable resolution and output capture.
  """
  @spec execute(tool_module :: module(), args :: map(), ctx :: Context.t(), opts :: keyword()) ::
    {:ok, result :: term(), Context.t()} | {:error, term()}
  def execute(tool_module, args, ctx, opts \\ []) do
    var_name = Keyword.get(opts, :save_as)

    with {:ok, resolved_args} <- ArgResolver.resolve(args, ctx),
         {:ok, result} <- apply(tool_module, :run, [resolved_args, ctx]) do
      
      ctx = maybe_save_as_variable(result, var_name, ctx)
      {:ok, result, ctx}
    end
  end

  defp maybe_save_as_variable(result, nil, ctx), do: ctx
  defp maybe_save_as_variable(result, var_name, ctx) do
    # Determine category based on result type
    category = categorize_result(result)
    
    case Protocol.spawn_bit(category, %{
      data: result,
      size: estimate_size(result),
      created_by: :tool_output
    }, ctx) do
      {:ok, bit, ctx} ->
        {:ok, ctx} = Context.assign_var(ctx, var_name, bit)
        UIContract.broadcast(bit, ctx, :created)
        ctx
      
      _ ->
        ctx
    end
  end

  defp categorize_result(result) when is_list(result), do: :dataset
  defp categorize_result(result) when is_map(result) do
    cond do
      Map.has_key?(result, :content) or Map.has_key?(result, :text) -> :document
      Map.has_key?(result, :rows) or Map.has_key?(result, :data) -> :dataset
      true -> :result
    end
  end
  defp categorize_result(_), do: :result

  defp estimate_size(data) do
    data |> :erlang.term_to_binary() |> byte_size()
  end
end
```

---

## HC-Δ-8: Thunderbit Training Exporter

**Priority**: P1  
**Goal**: Export Thunderbit sessions as structured training data for Cerebros.

### 8-A: Exporter Module

**File**: `lib/thunderline/training/thunderbit_exporter.ex`

```elixir
defmodule Thunderline.Training.ThunderbitExporter do
  @moduledoc """
  Export Thunderbit sessions as structured training data.
  
  Supports:
    - CSV export (thunderbits.csv, thunderbit_edges.csv)
    - JSON/NDJSON export (one session per line)
  
  Output is compatible with Cerebros training pipelines.
  """

  require Logger

  @schema_version "1.0.0"

  @type export_opts :: [
    format: :csv | :json | :ndjson,
    output_dir: String.t(),
    filters: keyword(),
    include_embeddings: boolean()
  ]

  @doc """
  Export sessions to training data files.
  """
  @spec export_sessions(contexts :: [map()], opts :: export_opts()) ::
    {:ok, %{bits_file: String.t(), edges_file: String.t()}} | {:error, term()}
  def export_sessions(contexts, opts \\ []) do
    format = Keyword.get(opts, :format, :csv)
    output_dir = Keyword.get(opts, :output_dir, "priv/training_data")
    
    File.mkdir_p!(output_dir)

    case format do
      :csv -> export_csv(contexts, output_dir, opts)
      :json -> export_json(contexts, output_dir, opts)
      :ndjson -> export_ndjson(contexts, output_dir, opts)
    end
  end

  # CSV Export

  defp export_csv(contexts, output_dir, opts) do
    bits_file = Path.join(output_dir, "thunderbits.csv")
    edges_file = Path.join(output_dir, "thunderbit_edges.csv")

    # Write bits CSV
    bits_rows = contexts
    |> Enum.flat_map(&extract_bit_rows/1)
    |> add_labels(opts)

    write_csv(bits_file, bits_header(), bits_rows)

    # Write edges CSV
    edges_rows = contexts
    |> Enum.flat_map(&extract_edge_rows/1)

    write_csv(edges_file, edges_header(), edges_rows)

    Logger.info("Exported #{length(bits_rows)} bits and #{length(edges_rows)} edges")
    {:ok, %{bits_file: bits_file, edges_file: edges_file}}
  end

  defp bits_header do
    [
      "schema_version", "session_id", "pac_id", "bit_id", "t_order",
      "category", "ontology_path", "content_hash", "energy",
      "in_degree", "out_degree", "label_success", "label_reward"
    ]
  end

  defp edges_header do
    ["schema_version", "session_id", "edge_id", "from_bit_id", "to_bit_id", "relation_type", "weight", "t_order"]
  end

  defp extract_bit_rows(ctx) do
    bits = Map.values(ctx.bits_by_id)
    edges = ctx.edges || []

    bits
    |> Enum.with_index()
    |> Enum.map(fn {bit, idx} ->
      in_degree = Enum.count(edges, &(&1.to == bit.id))
      out_degree = Enum.count(edges, &(&1.from == bit.id))
      content = get_in(bit, [:attrs, :content]) || ""

      [
        @schema_version,
        ctx.session_id,
        ctx.pac_id,
        bit.id,
        idx,
        bit.category,
        Enum.join(bit.ontology_path || [], "/"),
        :crypto.hash(:md5, content) |> Base.encode16(case: :lower),
        bit.energy || 1.0,
        in_degree,
        out_degree,
        nil,  # label_success - filled by labeler
        nil   # label_reward - filled by labeler
      ]
    end)
  end

  defp extract_edge_rows(ctx) do
    (ctx.edges || [])
    |> Enum.with_index()
    |> Enum.map(fn {edge, idx} ->
      [
        @schema_version,
        ctx.session_id,
        edge.id,
        edge.from,
        edge.to,
        edge.relation,
        edge.weight || 1.0,
        idx
      ]
    end)
  end

  defp add_labels(rows, opts) do
    # Apply labeler if configured
    case Keyword.get(opts, :labeler) do
      nil -> rows
      labeler_module -> labeler_module.apply_labels(rows)
    end
  end

  defp write_csv(path, header, rows) do
    content = [header | rows]
    |> Enum.map(&Enum.join(&1, ","))
    |> Enum.join("\n")

    File.write!(path, content)
  end

  # JSON Export

  defp export_json(contexts, output_dir, _opts) do
    file = Path.join(output_dir, "thunderbit_sessions.json")
    
    data = Enum.map(contexts, &context_to_json/1)
    content = Jason.encode!(%{
      schema_version: @schema_version,
      exported_at: DateTime.utc_now(),
      sessions: data
    }, pretty: true)

    File.write!(file, content)
    {:ok, %{bits_file: file, edges_file: file}}
  end

  defp export_ndjson(contexts, output_dir, _opts) do
    file = Path.join(output_dir, "thunderbit_sessions.ndjson")
    
    lines = contexts
    |> Enum.map(&context_to_json/1)
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")

    File.write!(file, lines)
    {:ok, %{bits_file: file, edges_file: file}}
  end

  defp context_to_json(ctx) do
    bits = ctx.bits_by_id
    |> Map.values()
    |> Enum.sort_by(& &1.inserted_at)
    |> Enum.with_index()
    |> Enum.map(fn {bit, idx} ->
      %{
        bit_id: bit.id,
        t_order: idx,
        category: bit.category,
        content: get_in(bit, [:attrs, :content]),
        energy: bit.energy,
        ontology_path: bit.ontology_path
      }
    end)

    edges = (ctx.edges || [])
    |> Enum.map(fn edge ->
      %{from: edge.from, to: edge.to, relation: edge.relation}
    end)

    %{
      session_id: ctx.session_id,
      pac_id: ctx.pac_id,
      bits: bits,
      edges: edges,
      label: %{
        task_success: nil,  # To be filled by labeler
        reward: nil
      }
    }
  end
end
```

---

## HC-Δ-9: Labeling & Embedding Infrastructure

**Priority**: P1  
**Goal**: Provide labels and embeddings for Cerebros training.

### 9-A: Labeler Module

**File**: `lib/thunderline/training/labeler.ex`

```elixir
defmodule Thunderline.Training.Labeler do
  @moduledoc """
  Derive training labels from Thunderline execution logs.
  
  Label sources:
    1. Hard labels: success/failure, reward, policy violations
    2. Weak supervision: heuristic rules
    3. Teacher labels: LLM-based scoring (optional)
  """

  alias Thunderline.Thundercrown.PolicyEngine

  @doc """
  Derive all available labels for a context.
  """
  @spec derive_labels(ctx :: map()) :: map()
  def derive_labels(ctx) do
    %{}
    |> Map.merge(derive_system_labels(ctx))
    |> Map.merge(apply_heuristic_labels(ctx))
  end

  @doc """
  Derive hard, system-derived labels.
  """
  @spec derive_system_labels(ctx :: map()) :: map()
  def derive_system_labels(ctx) do
    %{
      # Task completion
      task_success: task_succeeded?(ctx),
      
      # Reward metrics
      response_time_ms: get_response_time(ctx),
      num_retries: get_retry_count(ctx),
      
      # Policy compliance
      policy_violation: has_policy_violation?(ctx),
      
      # Resource usage
      bit_count: map_size(ctx.bits_by_id),
      edge_count: length(ctx.edges || [])
    }
  end

  @doc """
  Apply heuristic-based weak supervision labels.
  """
  @spec apply_heuristic_labels(ctx :: map()) :: map()
  def apply_heuristic_labels(ctx) do
    %{
      # Session quality heuristics
      is_confused: confusion_detected?(ctx),
      is_efficient: efficient_resolution?(ctx),
      required_escalation: escalation_occurred?(ctx)
    }
  end

  # Private helpers

  defp task_succeeded?(ctx) do
    # Check if final motor/response bit indicates success
    final_bits = ctx.bits_by_id
    |> Map.values()
    |> Enum.filter(&(&1.category == :motor))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    case final_bits do
      [final | _] -> get_in(final, [:attrs, :success]) == true
      _ -> nil
    end
  end

  defp get_response_time(ctx) do
    bits = Map.values(ctx.bits_by_id)
    
    case {Enum.min_by(bits, & &1.inserted_at, fn -> nil end),
          Enum.max_by(bits, & &1.inserted_at, fn -> nil end)} do
      {nil, _} -> nil
      {_, nil} -> nil
      {first, last} -> DateTime.diff(last.inserted_at, first.inserted_at, :millisecond)
    end
  end

  defp get_retry_count(ctx) do
    ctx.bits_by_id
    |> Map.values()
    |> Enum.count(&(get_in(&1, [:attrs, :is_retry]) == true))
  end

  defp has_policy_violation?(ctx) do
    (ctx.events || [])
    |> Enum.any?(&(&1.type == :policy_violation))
  end

  defp confusion_detected?(ctx) do
    # Heuristic: > 3 similar sensory bits suggests confusion
    sensory_bits = ctx.bits_by_id
    |> Map.values()
    |> Enum.filter(&(&1.category == :sensory))

    length(sensory_bits) > 3
  end

  defp efficient_resolution?(ctx) do
    # Heuristic: < 5 total bits for a successful task
    bit_count = map_size(ctx.bits_by_id)
    bit_count < 5 and task_succeeded?(ctx) == true
  end

  defp escalation_occurred?(ctx) do
    ctx.bits_by_id
    |> Map.values()
    |> Enum.any?(&(get_in(&1, [:attrs, :escalated]) == true))
  end
end
```

### 9-B: Embedding Module

**File**: `lib/thunderline/training/embedding.ex`

```elixir
defmodule Thunderline.Training.Embedding do
  @moduledoc """
  Generate embeddings for Thunderbits and sessions.
  
  V0: Uses generic text embedding model
  V1: Cerebros-trained domain-specific embeddings
  """

  @embedding_dim 384  # MiniLM default

  @doc """
  Embed a single Thunderbit.
  """
  @spec embed_bit(bit :: map(), ctx :: map(), opts :: keyword()) ::
    {:ok, map()} | {:error, term()}
  def embed_bit(bit, ctx, opts \\ []) do
    text = bit_to_text(bit)
    
    case generate_embedding(text, opts) do
      {:ok, embedding} ->
        {:ok, Map.put(bit, :embedding, embedding)}
      
      error ->
        error
    end
  end

  @doc """
  Embed an entire session (mean-pooled bit embeddings).
  """
  @spec embed_session(ctx :: map(), opts :: keyword()) ::
    {:ok, [float()]} | {:error, term()}
  def embed_session(ctx, opts \\ []) do
    bits = Map.values(ctx.bits_by_id)
    
    embeddings = bits
    |> Enum.map(&bit_to_text/1)
    |> Enum.map(&generate_embedding(&1, opts))
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, emb} -> emb end)

    if length(embeddings) > 0 do
      {:ok, mean_pool(embeddings)}
    else
      {:error, :no_embeddings}
    end
  end

  @doc """
  Get embedding dimensions.
  """
  @spec dimensions() :: integer()
  def dimensions, do: @embedding_dim

  # Private helpers

  defp bit_to_text(bit) do
    parts = [
      "category=#{bit.category}",
      "tags=#{Enum.join(bit.tags || [], ",")}",
      "content=#{get_in(bit, [:attrs, :content]) || ""}"
    ]

    Enum.join(parts, "; ")
  end

  defp generate_embedding(text, opts) do
    # V0: Use external embedding service or local model
    # For now, return a placeholder - implement with actual embedding model
    case Keyword.get(opts, :embedding_model) do
      nil ->
        # Placeholder: return zero vector
        {:ok, List.duplicate(0.0, @embedding_dim)}
      
      model_module ->
        model_module.embed(text)
    end
  end

  defp mean_pool(embeddings) do
    n = length(embeddings)
    dim = length(hd(embeddings))

    0..(dim - 1)
    |> Enum.map(fn i ->
      sum = embeddings |> Enum.map(&Enum.at(&1, i)) |> Enum.sum()
      sum / n
    end)
  end
end
```

---

## Implementation Order

### Phase 1: Thunderfield MVP ✅ COMPLETE

1. ✅ **HC-Δ-5.3-A**: UIContract DTO transformation
2. ✅ **HC-Δ-5.3-B**: PubSub broadcast  
3. ✅ **HC-Δ-5.3-C**: Intake pipeline (Demo + IntakePipeline)
4. ✅ **HC-Δ-5.3-D**: LiveView visualization with components
5. ✅ **HC-Δ-5.3-E**: Thunderfield components (8 shapes, detail panel, input)

**Success Criteria**: ✅ "Type a sentence → see Thunderbits appear and link"

### Phase 2: Variable References (Ready)

1. **HC-Δ-6-A**: Context vars extension
2. **HC-Δ-6-B**: Argument resolver
3. **HC-Δ-6-C**: Tool bridge with output capture

**Success Criteria**: Tools can save outputs as $variables; subsequent tools reference them

### Phase 3: Ontology & Ethics (Ready)

1. **HC-Δ-5.4-A**: Category ↔ Ontology resolution
2. **HC-Δ-5.4-B**: PolicyEngine hooks in Protocol

**Success Criteria**: Bits have ontology paths; links check wiring rules

### Phase 4: Training Infrastructure (Ready)

1. **HC-Δ-8**: Thunderbit Exporter (CSV/JSON)
2. **HC-Δ-9-A**: Labeler module
3. **HC-Δ-9-B**: Embedding module

**Success Criteria**: Can export 100+ sessions with labels for Cerebros

---

## Appendix: Actual File Structure

```
lib/thunderline/
├── thunderbit/
│   ├── protocol.ex           # ✅ Core spawn/link/bind/mutate
│   ├── context.ex            # ✅ Session context with bits_by_id, edges
│   ├── category.ex           # ✅ Category definitions
│   ├── edge.ex               # ✅ Edge definitions
│   ├── ui_contract.ex        # ✅ UIContract with DTOs and broadcast
│   └── demo.ex               # ✅ Demo.intake/run/classify_intent
├── thunderprism/
│   ├── domain.ex             # ✅ PrismNode, PrismEdge resources
│   ├── intake_pipeline.ex    # ✅ Advanced streaming intake
│   └── ml_tap.ex             # ✅ ML decision trail logging
├── training/                  # To be implemented (HC-Δ-8/9)
│   ├── thunderbit_exporter.ex
│   ├── labeler.ex
│   └── embedding.ex
└── thunderline_web/
    └── live/
        ├── thunderfield_live.ex      # ✅ Full LiveView with PubSub
        └── components/
            └── thunderfield.ex       # ✅ Visual components (8 shapes)
```

---

## Notes

- **HC-Δ-5.3 is COMPLETE** - Implementation exceeds original spec with 8 shape variants, detail panels, voice toggle, and full PubSub integration
- Remaining code samples (HC-Δ-5.4, 6, 8, 9) are implementation-ready but may need minor adjustments
- Test files should accompany each new module
- Telemetry events should be added for monitoring
- Consider feature flags for gradual rollout

**Phase 1 Complete. Ready for Phase 2-4 implementation. 🚀**
