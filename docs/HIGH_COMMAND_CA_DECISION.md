# HIGH COMMAND DIRECTIVE — CA ARCHITECTURE DECISION

**Date**: November 21, 2025  
**Authority**: High Command  
**Classification**: OPERATIONAL DIRECTIVE  
**Distribution**: All Teams (Research, Dev, Cerebros, TAK UI)

---

## EXECUTIVE SUMMARY

After comprehensive review of:
- `Thunderbolt.CA` (RuleParser, Runner, Stepper)
- `Thunderbolt.ThunderCell` (CAEngine, CACell, Cluster)
- UPM integration requirements
- Cerebros ONNX integration
- GPU acceleration strategies

**🔥 FINAL DECISION:**

**We consolidate both CA systems into ONE hybrid engine:**  
**"TAK (Thunderline Automata Kernel)"**

---

## TAK ARCHITECTURE

```
TAK = 
  ├─ RuleParser (from Bolt.CA)
  ├─ Streaming Pipeline (from Bolt.CA.Runner)
  ├─ GPU-Accelerated Stepper (new, Nx.Defn)
  ├─ ThunderCell 3D Grid + Concurrency
  ├─ ONNX Persistence (for UPM)
  └─ TAK UI (voxel renderer for visualization)
```

---

## 🚀 WHY THIS IS THE DECISION

### ✔️ 1. Bolt.CA gives us the perfect production-facing pipeline

**Already has:**
- **RuleParser**: Conway B#/S# notation + metadata/seeds
- **Runner**: 20Hz delta streaming
- **PubSub broadcasting**: `Phoenix.PubSub.broadcast("ca:#{run_id}")`
- **Event taxonomy integration**: Emits `evt.action.ca.rule_parsed`

**This is the public API.**

---

### ✔️ 2. ThunderCell gives us the perfect underlying CA compute substrate

**Already supports:**
- **3D grids**: {X, Y, Z} topology
- **CACell**: Each cell = separate Elixir process (fault-tolerant)
- **Cluster manager**: Coordinates 1000+ concurrent cells
- **CAEngine**: Algorithm registry with optimization
- **Fully concurrent neighbor calculations**: Phase 1 (prepare) + Phase 2 (commit)

**This is the execution engine.**

---

### ✔️ 3. Nx.Defn GPU acceleration plugs naturally into Stepper

`Stepper.next/2` is currently a stub — **perfect insertion point for:**

```elixir
defn evolve_grid(grid, born, survive) do
  neighbors = Nx.conv(grid, neighborhood_kernel_3d())
  birth_mask = Nx.any(Nx.equal(neighbors, born))
  survival_mask = Nx.any(Nx.equal(neighbors, survive))
  Nx.select(Nx.logical_or(birth_mask, survival_mask), 1, 0)
end
```

**Data flow:**
```
ThunderCell.Cluster → produces big Nx tensor
    ↓
StepperGPU → GPU-accelerated updates
    ↓
Bolt.CA.Runner → streams deltas via PubSub
```

**Perfect alignment with UPM training/update loop.**

---

### ✔️ 4. ONNX Serialization Works Cleanly Over This Split

`SnapshotManager` can serialize:

1. **CA ruleset** (from `Bolt.RuleParser`)
2. **CA tensor state** (from `ThunderCell.Cluster`)
3. **Compressed compute-shader kernel** (for TAK UI)
4. **Full ONNX version** (for Cerebros)

**Exactly what UPM needs.**

---

### ✔️ 5. TAK UI Layer fits this structure perfectly

**TAK UI needs:**
- **Streaming deltas** → `Bolt.CA.Runner` already does this
- **State grid** → `ThunderCell` already provides
- **Voxel-level glyphs** → TAK shader engine
- **Event integration** → Thunderflow

**Perfect synergy.**

---

## 🔧 THE BUILD PLAN

### PHASE 1 — Merge CA logic into TAK

**New module structure:**

```
lib/thunderline/thunderbolt/tak/
├── tak.ex                  # Public API facade
├── grid.ex                 # 3D grid management (wraps ThunderCell.Cluster)
├── runner.ex               # Streaming pipeline (from Bolt.CA.Runner)
├── gpu_stepper.ex          # Nx.Defn GPU kernels (replaces Stepper)
└── serializer.ex           # ONNX ↔ CA rules conversion
```

**Preserve existing modules for backward compatibility:**
- `Bolt.CA` → delegates to TAK
- `ThunderCell.*` → used internally by TAK

---

### PHASE 2 — Nx/EXLA GPU Stepper

**Replace `Stepper.next` with:**

```elixir
defmodule Thunderline.Thunderbolt.TAK.GPUStepper do
  import Nx.Defn

  @doc "GPU-accelerated CA evolution using Nx.Defn"
  defn evolve(grid, born_neighbors, survive_neighbors) do
    # 3D convolution for neighbor counting
    neighbors = Nx.conv(grid, neighborhood_kernel_3d(), 
      padding: :same, 
      strides: [1, 1, 1]
    )
    
    # Birth condition: dead cells with birth_neighbors
    birth_mask = Nx.logical_and(
      Nx.equal(grid, 0),
      neighbor_matches(neighbors, born_neighbors)
    )
    
    # Survival condition: alive cells with survival_neighbors
    survival_mask = Nx.logical_and(
      Nx.equal(grid, 1),
      neighbor_matches(neighbors, survive_neighbors)
    )
    
    # New state
    Nx.select(Nx.logical_or(birth_mask, survival_mask), 1, 0)
  end

  defnp neighborhood_kernel_3d do
    # 3x3x3 Moore neighborhood kernel
    Nx.tensor([
      [[1, 1, 1], [1, 1, 1], [1, 1, 1]],
      [[1, 1, 1], [1, 0, 1], [1, 1, 1]],  # Center = 0
      [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
    ])
  end

  defnp neighbor_matches(neighbors, target_counts) do
    # Check if neighbor count matches any in target list
    Enum.reduce(target_counts, Nx.broadcast(0, neighbors), fn count, acc ->
      Nx.logical_or(acc, Nx.equal(neighbors, count))
    end)
  end
end
```

**This is the unified compute kernel.**

---

### PHASE 3 — Connect ThunderCell.Cluster → TAK Grid

**ThunderCell remains the in-memory active state holder.**

```elixir
defmodule Thunderline.Thunderbolt.TAK.Grid do
  alias Thunderline.Thunderbolt.ThunderCell.Cluster

  def evolve_generation(cluster_id) do
    # Get current state as Nx tensor
    tensor = Cluster.to_tensor(cluster_id)
    rules = Cluster.get_ca_rules(cluster_id)
    
    # GPU-accelerated evolution
    updated_tensor = Nx.Defn.jit(&GPUStepper.evolve/3).(
      tensor,
      rules.birth_neighbors,
      rules.survival_neighbors
    )
    
    # Apply changes back to cluster
    Cluster.update_from_tensor(cluster_id, updated_tensor)
  end
end
```

**Data flow:**
1. `Cluster` → produces Nx tensor
2. `GPUStepper` → GPU update
3. `Cluster` → applies changes to cell processes

---

### PHASE 4 — Plug TAK into UPM TrainerWorker

**Replace the TODO in `TrainerWorker.update_model/2`:**

```elixir
defmodule Thunderline.Thunderbolt.UPM.TrainerWorker do
  def update_model(state, window_data) do
    # Load current CA grid state
    grid_tensor = TAK.load_current_grid(state.trainer.id)
    
    # Apply window data to grid (feature → CA state translation)
    updated_grid = TAK.apply_window(grid_tensor, window_data)
    
    # GPU-accelerated CA evolution
    evolved_grid = TAK.evolve_gpu(updated_grid, state.trainer.ca_rules)
    
    # Serialize to snapshot format
    snapshot_data = TAK.serialize_to_snapshot(evolved_grid)
    
    %{state | 
      model_state: snapshot_data,
      iterations: state.iterations + 1
    }
  end
end
```

**This replaces the existing TODO.**

---

### PHASE 5 — Integrate ONNX Snapshots

**SnapshotManager enhancement:**

```elixir
defmodule Thunderline.Thunderbolt.UPM.SnapshotManager do
  def create_snapshot(trainer_id, metadata) do
    # Get CA rules and current grid state
    ca_rules = TAK.get_rules(trainer_id)
    grid_state = TAK.get_grid_tensor(trainer_id)
    
    # Convert to ONNX format
    onnx_model = TAK.Serializer.to_onnx(%{
      metadata: metadata,
      ca_rules: ca_rules,
      grid_state: grid_state,
      shader_kernel: TAK.compile_shader_kernel(ca_rules)
    })
    
    # Compress and persist
    compressed = :zstd.compress(:erlang.term_to_binary(onnx_model))
    File.write!(snapshot_path(trainer_id), compressed)
  end
  
  def load_snapshot(snapshot_id) do
    # Read and decompress
    {:ok, compressed} = File.read(snapshot_path(snapshot_id))
    onnx_model = :erlang.binary_to_term(:zstd.decompress(compressed))
    
    # Convert ONNX → CA rules + grid
    %{
      ca_rules: TAK.Serializer.onnx_to_rules(onnx_model),
      grid_state: TAK.Serializer.onnx_to_tensor(onnx_model),
      shader_kernel: onnx_model.shader_kernel
    }
  end
end
```

**Snapshot format:**
- CA ruleset (born/survive patterns)
- Grid tensor state (Nx binary)
- Compiled shader kernel (SPIR-V bytecode)
- Full ONNX graph (for Cerebros)

**This makes CA models portable and evolvable.**

---

### PHASE 6 — TAK UI Layer

**GPU shader-based voxel renderer:**

```elixir
defmodule Thunderline.Thunderbolt.TAK.UI do
  @moduledoc "TAK visualization layer for voxel rendering"
  
  def start_visualization(run_id, opts \\ []) do
    # Subscribe to CA delta stream
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "ca:#{run_id}")
    
    # Initialize WebGL shader program
    shader_kernel = Keyword.get(opts, :shader_kernel)
    
    # Start renderer
    {:ok, renderer_pid} = TAK.UI.Renderer.start_link(%{
      run_id: run_id,
      shader_kernel: shader_kernel,
      glyph_mapping: opts[:glyph_mapping]
    })
    
    {:ok, renderer_pid}
  end
  
  # Renderer receives CA deltas and pushes to frontend
  def handle_info({:ca_delta, %{cells: deltas}}, socket) do
    # Transform CA deltas → voxel updates
    voxel_updates = Enum.map(deltas, &to_voxel_glyph/1)
    
    # Push to WebGL frontend
    {:noreply, push_event(socket, "tak-voxel-update", %{voxels: voxel_updates})}
  end
end
```

**Features:**
- Voxel-level glyph rendering
- Real-time CA state visualization
- Event integration with Thunderflow
- Shader-based GPU rendering

**This plugs directly into the existing `Bolt.CA.Runner` PubSub stream.**

---

## 🧠 MESSAGE TO CEREBROS TEAM

### **Cerebros Integration Requirements**

We need **one ONNX model** from you that can be used in **three ways**:

#### 1. As a CA Rule Generator

**Input:** Window tensor (from FeatureWindow)  
**Output:**
- Updated CA rule weights (born/survive patterns)
- Automata deltas for TAK grid

#### 2. As a Feature-to-State Translator

**Input:** Raw features (sensor data, metrics, etc.)  
**Output:** Nx tensor representing updated CA state

#### 3. As a Shader Kernel Source

**The ONNX graph must be convertible into:**
- Small fully-connected network
- Runnable inside WebGL/OpenGL compute shader
- For TAK UI visualization

---

### **Key Constraints**

**We do NOT need a giant model.**

**We DO need:**
- Lightweight, CA-compatible ONNX graph
- JIT-compilable to GPU kernels
- Serializable to snapshot format
- Small enough to run in browser shaders

**Target Model Size:** <10MB uncompressed, <100 ops

**Target Inference Speed:** <5ms per CA generation on GPU

---

## 📊 MIGRATION PATH

### Backward Compatibility

**Existing code continues to work:**

```elixir
# Old API (still works)
Thunderline.Thunderbolt.CA.parse_rule("B367/S568")
Thunderline.Thunderbolt.CA.Runner.start_link(...)
Thunderline.Thunderbolt.ThunderCell.Cluster.start_link(...)

# New API (preferred)
Thunderline.Thunderbolt.TAK.parse_rule("B367/S568")
Thunderline.Thunderbolt.TAK.start_runner(...)
Thunderline.Thunderbolt.TAK.start_cluster(...)
```

**Deprecation Timeline:**
- **Phase 1-2**: TAK modules created, old modules delegate to TAK
- **Phase 3-4**: New code uses TAK directly
- **Phase 5-6**: Old modules marked deprecated
- **Post-launch**: Remove deprecated modules (1 release cycle notice)

---

## ✅ SUCCESS CRITERIA

### Phase 1-2 Complete When:
- [ ] TAK modules created and tested
- [ ] GPU Stepper passes benchmark (>1000 gen/sec on 100³ grid)
- [ ] Backward compatibility verified

### Phase 3-4 Complete When:
- [ ] UPM TrainerWorker integrated with TAK
- [ ] CA updates running in production shadow mode
- [ ] Drift detection working with CA grids

### Phase 5-6 Complete When:
- [ ] ONNX snapshots serializing/deserializing correctly
- [ ] TAK UI rendering voxels in browser
- [ ] Full E2E test: FeatureWindow → CA update → ONNX snapshot → TAK UI

---

## 🎯 TEAM ASSIGNMENTS

**Research Team:**
- Prototype Nx.Defn GPU kernels
- Benchmark CA evolution performance
- Define CA ↔ ONNX schema

**Dev Team:**
- Implement TAK module structure
- Integrate with UPM TrainerWorker
- Backward compatibility layer

**Cerebros Team:**
- Design lightweight ONNX model
- Implement Feature → CA state translator
- Provide shader-compilable graph

**TAK UI Team:**
- WebGL voxel renderer
- Glyph mapping system
- Real-time delta streaming frontend

---

## 📝 NOTES FOR IMPLEMENTERS

1. **GPU Memory Management:**
   - Pin CA grid tensors to GPU memory
   - Only transfer deltas to CPU for broadcasting
   - Use Nx.Defn.jit with EXLA backend

2. **ONNX Format:**
   - Version snapshots by CA topology hash
   - Include shader kernel in metadata
   - Support incremental updates (deltas only)

3. **Visualization:**
   - Use WebGL2 compute shaders
   - Batch voxel updates (max 60fps)
   - Implement LOD for large grids

4. **Testing:**
   - Day 2 UPM tests already validate integration points
   - Add TAK-specific tests for GPU kernels
   - Benchmark against pure Elixir baseline

---

## APPROVAL & SIGN-OFF

**Approved By:** High Command  
**Date:** November 21, 2025  
**Effective:** Immediately  

**All teams:** Acknowledge receipt and begin Phase 1 implementation.

**Next Review:** After Phase 2 completion (GPU Stepper benchmark results)

---

**END DIRECTIVE**
