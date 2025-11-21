# TAK (Thunderline Automata Kernel) Configuration
#
# GPU-accelerated cellular automata configuration.
# Imported by config/dev.exs and config/prod.exs.

import Config

# ============================================================================
# Nx Backend Configuration (GPU Acceleration)
# ============================================================================

# Set default backend to EXLA for GPU acceleration
# Falls back to BinaryBackend if EXLA not available
config :nx, :default_backend, EXLA.Backend

# EXLA GPU Client Configuration
config :exla, :clients,
  cuda: [platform: :cuda, preallocate: true],
  rocm: [platform: :rocm, preallocate: true],
  host: [platform: :host]

# Default to CUDA client if available, otherwise host (CPU)
# TEMPORARY: Set to :host for CPU-only systems without CUDA/ROCm
config :exla, :default_client, :host

# ============================================================================
# TAK Performance Configuration
# ============================================================================

config :thunderline, Thunderline.Thunderbolt.TAK,
  # GPU settings
  gpu_enabled?: true,
  default_backend: EXLA.Backend,

  # Performance targets
  target_gen_per_sec: 1000,
  min_acceptable_gen_per_sec: 500,

  # Grid defaults
  default_dimensions_2d: {100, 100},
  default_dimensions_3d: {100, 100, 100},
  max_grid_size: 1_000_000,  # 100³

  # Runner defaults
  default_tick_ms: 16,  # ~60 FPS
  broadcast_deltas?: true,
  delta_compression?: true,

  # Telemetry
  enable_telemetry?: true,
  telemetry_prefix: [:thunderline, :tak]

# ============================================================================
# CA Rule Defaults
# ============================================================================

config :thunderline, Thunderline.Thunderbolt.TAK.Rules,
  # Conway 2D (Game of Life)
  conway_2d: %{born: [3], survive: [2, 3]},

  # Conway 3D
  conway_3d: %{born: [5, 6, 7], survive: [4, 5, 6]},

  # Highlife 3D
  highlife_3d: %{born: [6, 8], survive: [5, 6]},

  # Seeds 3D
  seeds_3d: %{born: [4], survive: []},

  # Maze 3D
  maze_3d: %{born: [6], survive: [3, 4, 5, 6, 7, 8]},

  # Custom Thunderline CA
  thunderline: %{born: [6, 7, 8], survive: [5, 6, 7, 8]}

# ============================================================================
# ONNX Serialization (Phase 5)
# ============================================================================

config :thunderline, Thunderline.Thunderbolt.TAK.Serializer,
  compression: :zstd,
  compression_level: 3,
  max_snapshot_size_mb: 10,
  max_ops: 100,
  include_shader?: true,
  shader_format: :webgl

# ============================================================================
# Logging
# ============================================================================

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :run_id, :trainer_id]
