defmodule Thunderline.Thunderbolt.TAK do
  @moduledoc """
  TAK (Thunderline Automata Kernel) - Unified Cellular Automata Engine

  ## Overview

  TAK consolidates:
  - Bolt.CA's production visualization pipeline (RuleParser, Runner, PubSub streaming)
  - ThunderCell's 3D massively concurrent engine (1000+ cell processes)
  - Nx.Defn GPU acceleration (>1000 gen/sec target)
  - ONNX serialization for UPM integration
  - TAK UI voxel renderer for visualization

  ## Architecture

  ```
  TAK Public API (Backward Compatible)
       ↓
  ┌────────────────────────────────────────┐
  │  TAK.RuleParser (from Bolt.CA)         │
  │  TAK.Runner (GPU-enhanced streaming)   │
  │  TAK.GPUStepper (Nx.Defn kernels)      │
  │  TAK.Grid (ThunderCell integration)    │
  │  TAK.Serializer (ONNX ↔ CA)            │
  └────────────────────────────────────────┘
       ↓
  PubSub → TAK UI Voxel Renderer
  ```

  ## Usage

  ### Parse CA Rules (Backward Compatible with Bolt.CA)
  ```elixir
  {:ok, ruleset} = TAK.parse_rule("B367/S568 rate=60Hz seed=glider")
  # => %RuleParser{born: [3,6,7], survive: [5,6,8], rate_hz: 60, seed: "glider"}
  ```

  ### Start CA Runner (GPU-Accelerated)
  ```elixir
  {:ok, pid} = TAK.start_runner("my_run_id", %{
    size: {100, 100, 100},
    ruleset: ruleset,
    tick_ms: 16  # ~60 FPS
  })
  ```

  ### GPU Evolution (>1000 gen/sec)
  ```elixir
  grid = TAK.Grid.new({100, 100, 100})
  {:ok, deltas, new_grid} = TAK.evolve_gpu(grid, ruleset)
  ```

  ### ONNX Serialization (UPM Integration)
  ```elixir
  onnx_binary = TAK.to_onnx(grid, ruleset)
  {:ok, {grid, ruleset}} = TAK.from_onnx(onnx_binary)
  ```

  ## Performance Targets

  - GPU Evolution: >1000 gen/sec (vs current 20 Hz)
  - PubSub Streaming: <10ms latency to UI
  - ONNX Serialization: <100ms, <1MB per snapshot
  - Voxel Rendering: 60 FPS for 10K visible cells

  ## Integration Points

  - **UPM**: TrainerWorker.update_model/2 → TAK.evolve_gpu → snapshot
  - **Bolt.CA**: Existing RuleParser + Runner API (backward compatible)
  - **ThunderCell**: Cluster → Nx tensor → GPU → Cluster
  - **TAK UI**: PubSub subscription → WebGL voxel renderer
  """

  alias Thunderline.Thunderbolt.CA.RuleParser

  @doc """
  Parse CA rule string into structured ruleset.

  Backward compatible with Bolt.CA.parse_rule/1.

  ## Examples

      iex> TAK.parse_rule("B3/S23")
      {:ok, %RuleParser{born: [3], survive: [2, 3]}}

      iex> TAK.parse_rule("B367/S568 rate=60Hz seed=glider zone=alpha")
      {:ok, %RuleParser{
        born: [3, 6, 7],
        survive: [5, 6, 8],
        rate_hz: 60,
        seed: "glider",
        zone: "alpha"
      }}
  """
  defdelegate parse_rule(rule_string), to: RuleParser, as: :parse

  @doc """
  Start a CA runner process with GPU-accelerated evolution.

  Backward compatible with Bolt.CA.Runner.start_link/1.

  ## Options

  - `:size` - Grid dimensions `{width, height}` or `{x, y, z}` (required)
  - `:ruleset` - Parsed CA rules (required)
  - `:tick_ms` - Milliseconds between generations (default: 50ms = 20Hz)
  - `:gpu_enabled?` - Use GPU acceleration (default: true)
  - `:broadcast?` - Emit deltas via PubSub (default: true)

  ## Examples

      {:ok, pid} = TAK.start_runner("run_001", %{
        size: {100, 100},
        ruleset: ruleset,
        tick_ms: 16  # 60 FPS
      })
  """
  def start_runner(run_id, opts) do
    # Phase 1: Delegate to existing Bolt.CA.Runner (backward compatible)
    # Phase 2: Will use TAK.Runner with GPU integration
    Thunderline.Thunderbolt.CA.Runner.start_link(Map.merge(opts, %{run_id: run_id}))
  end

  @doc """
  Perform GPU-accelerated CA evolution.

  Phase 1: Delegates to Bolt.CA.Stepper (stub)
  Phase 2: Will use TAK.GPUStepper with Nx.Defn kernels

  ## Examples

      grid = TAK.Grid.new({100, 100, 100})
      {:ok, deltas, new_grid} = TAK.evolve_gpu(grid, ruleset)
  """
  def evolve_gpu(grid, ruleset) do
    # Phase 1: Delegate to existing Stepper (backward compatible)
    # Phase 2: Will use TAK.GPUStepper.evolve/3
    Thunderline.Thunderbolt.CA.Stepper.next(grid, ruleset)
  end

  @doc """
  Serialize CA state to ONNX format.

  Phase 5 implementation. Returns binary ONNX data.

  ## Examples

      onnx_binary = TAK.to_onnx(grid, ruleset)
      File.write!("snapshot.onnx", onnx_binary)
  """
  def to_onnx(_grid, _ruleset) do
    # Phase 5: Implement TAK.Serializer.to_onnx/2
    {:error, :not_implemented_phase_5}
  end

  @doc """
  Deserialize CA state from ONNX format.

  Phase 5 implementation. Returns `{:ok, {grid, ruleset}}`.

  ## Examples

      onnx_binary = File.read!("snapshot.onnx")
      {:ok, {grid, ruleset}} = TAK.from_onnx(onnx_binary)
  """
  def from_onnx(onnx_binary) when is_binary(onnx_binary) do
    # Phase 5: Implement TAK.Serializer.from_onnx/1
    {:error, :not_implemented_phase_5}
  end

  @doc """
  Stop a running CA runner process.

  ## Examples

      :ok = TAK.stop_runner(pid)
  """
  def stop_runner(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Get current TAK version and enabled features.

  ## Examples

      TAK.info()
      # => %{
      #   version: "0.1.0-phase1",
      #   gpu_enabled?: false,
      #   onnx_enabled?: false,
      #   backward_compatible?: true
      # }
  """
  def info do
    %{
      version: "0.1.0-phase1",
      gpu_enabled?: false,
      onnx_enabled?: false,
      backward_compatible?: true,
      phases_complete: [:phase_1],
      phases_pending: [:phase_2, :phase_3, :phase_4, :phase_5, :phase_6]
    }
  end
end
