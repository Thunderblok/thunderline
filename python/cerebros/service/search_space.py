"""
Cerebros TPE Search Space Configuration.

This module defines the hyperparameter search spaces for Cerebros TPE optimization.
Each search space category can be enabled/disabled and combined for multi-objective optimization.

Search Space Categories:
- ARCHITECTURE: Network topology (levels, units, neurons)
- CONNECTION: Lateral/predecessor connection parameters
- TRAINING: Learning rate, epochs, batch size
- EMBEDDING: Embedding dimensions and dropout
- MEMORY (HC-78): MIRAS/Titans memory architecture parameters
- SNN (HC-57): Spiking neural network parameters
- CA (HC-64): Cellular automata parameters

Usage:
    from search_space import SearchSpaceConfig, suggest_hyperparameters

    config = SearchSpaceConfig(
        enable_memory=True,
        enable_snn=False,
        enable_ca=False
    )
    params = suggest_hyperparameters(trial, config)

References:
- HC-78: MIRAS/Titans Memory Hyperparameters
- HC-57: SNN Priors
- HC-64: CAT/NCA Hyperparameters
"""
import logging
from dataclasses import dataclass, field
from typing import Dict, Any, Optional, List
from enum import Enum

logger = logging.getLogger(__name__)


class WriteGateMode(str, Enum):
    """Write gate modes for memory module (MIRAS architecture)."""
    THRESHOLD = "threshold"  # Binary gate based on surprise threshold
    SOFTMAX = "softmax"      # Soft attention-weighted writes
    TOPK = "topk"            # Top-k most surprising entries
    GUMBEL = "gumbel"        # Gumbel-softmax for differentiable selection


class RetentionMode(str, Enum):
    """Memory retention/forgetting modes (Titans architecture)."""
    DECAY = "decay"          # Exponential weight decay (default Titans)
    GRU = "gru"              # GRU-style gating for selective retention
    NONE = "none"            # No forgetting (unbounded growth)
    ADAPTIVE = "adaptive"    # Surprise-proportional decay


class AttentionalBias(str, Enum):
    """MIRAS attentional bias configurations."""
    NONE = "none"            # Standard linear attention
    SOFTMAX = "softmax"      # Softmax over memory slots
    SLOT = "slot"            # Slot-based attention mechanism


@dataclass
class SearchSpaceConfig:
    """Configuration for which search space categories to enable."""
    
    # Core architecture search
    enable_architecture: bool = True
    enable_connection: bool = True
    enable_training: bool = True
    enable_embedding: bool = True
    
    # Extended search spaces (HC-75+)
    enable_memory: bool = False     # HC-78: MIRAS/Titans memory params
    enable_snn: bool = False        # HC-57: Spiking neural network params
    enable_ca: bool = False         # HC-64: Cellular automata params
    
    # Constraints for objective function
    plv_constraint: Optional[tuple] = None  # (min, max) for criticality constraint
    memory_budget_mb: Optional[float] = None  # Memory budget constraint
    
    def __post_init__(self):
        """Validate configuration."""
        if self.plv_constraint is not None:
            if len(self.plv_constraint) != 2:
                raise ValueError("plv_constraint must be (min, max) tuple")
            if self.plv_constraint[0] >= self.plv_constraint[1]:
                raise ValueError("plv_constraint min must be < max")


# =============================================================================
# SEARCH SPACE DEFINITIONS
# =============================================================================

def suggest_architecture_params(trial) -> Dict[str, Any]:
    """
    Architecture hyperparameters for Cerebros network topology.
    
    These control the structure of the neural network:
    - Number of levels (depth)
    - Units per level
    - Neurons per unit
    """
    # Level constraints - ensure max >= min
    minimum_levels = trial.suggest_int('minimum_levels', 1, 3)
    maximum_levels = trial.suggest_int('maximum_levels', minimum_levels, 4)
    
    # Units per level - ensure max >= min
    minimum_units_per_level = trial.suggest_int('minimum_units_per_level', 1, 4)
    maximum_units_per_level = trial.suggest_int('maximum_units_per_level', minimum_units_per_level, 6)
    
    # Neurons per unit - ensure max >= min
    minimum_neurons_per_unit = trial.suggest_int('minimum_neurons_per_unit', 1, 4)
    maximum_neurons_per_unit = trial.suggest_int('maximum_neurons_per_unit', minimum_neurons_per_unit, 6)
    
    return {
        'minimum_levels': minimum_levels,
        'maximum_levels': maximum_levels,
        'minimum_units_per_level': minimum_units_per_level,
        'maximum_units_per_level': maximum_units_per_level,
        'minimum_neurons_per_unit': minimum_neurons_per_unit,
        'maximum_neurons_per_unit': maximum_neurons_per_unit,
    }


def suggest_connection_params(trial) -> Dict[str, Any]:
    """
    Connection hyperparameters for lateral and predecessor connections.
    
    These control how neurons are connected within and across levels.
    """
    return {
        'predecessor_level_connection_affinity_factor_first': trial.suggest_float(
            'predecessor_level_connection_affinity_factor_first', 10.0, 30.0
        ),
        'predecessor_level_connection_affinity_factor_main': trial.suggest_float(
            'predecessor_level_connection_affinity_factor_main', 16.0, 25.0
        ),
        'max_consecutive_lateral_connections': trial.suggest_int(
            'max_consecutive_lateral_connections', 5, 10
        ),
        'p_lateral_connection': trial.suggest_float(
            'p_lateral_connection', 0.12, 0.35
        ),
        'num_lateral_connection_tries_per_unit': trial.suggest_int(
            'num_lateral_connection_tries_per_unit', 20, 40
        ),
    }


def suggest_training_params(trial) -> Dict[str, Any]:
    """
    Training hyperparameters for optimization.
    """
    return {
        'learning_rate': trial.suggest_float('learning_rate', 0.0001, 0.01, log=True),
        'epochs': trial.suggest_int('epochs', 5, 100),
        'batch_size': trial.suggest_int('batch_size', 4, 32),
        'gradient_accumulation_steps': trial.suggest_int('gradient_accumulation_steps', 1, 16),
        'activation': trial.suggest_categorical('activation', ['relu', 'gelu', 'swish', 'softsign']),
    }


def suggest_embedding_params(trial) -> Dict[str, Any]:
    """
    Embedding hyperparameters for input representation.
    """
    embedding_n = trial.suggest_int('embedding_n', 6, 16)
    
    return {
        'embedding_n': embedding_n,
        'embedding_dim': embedding_n * 2,  # iRoPE requires even dimension
        'positional_embedding_dropout': trial.suggest_float(
            'positional_embedding_dropout', 0.5, 0.95
        ),
    }


# =============================================================================
# HC-78: MIRAS/TITANS MEMORY HYPERPARAMETERS
# =============================================================================

def suggest_memory_params(trial) -> Dict[str, Any]:
    """
    Memory hyperparameters for MIRAS/Titans architecture (HC-78).
    
    These parameters configure the deep MLP memory module that stores
    and retrieves learned patterns based on surprise signals.
    
    Architecture Parameters:
    - memory_depth: Number of MLP layers (Titans "deep memory")
    - memory_width: Hidden dimension per layer
    - memory_heads: Number of attention heads for retrieval (MIRAS multi-head)
    
    Surprise/Write Parameters:
    - surprise_threshold: Minimum gradient norm to trigger write (Titans s_t)
    - write_gate_mode: How to gate writes (threshold/softmax/topk)
    - write_lr: Learning rate for memory weight updates
    
    Retention Parameters:
    - momentum_beta: Momentum smoothing for surprise (Titans β)
    - weight_decay: Forgetting factor for old memories (Titans α)
    - retention_mode: How memories decay over time
    
    MIRAS-Specific:
    - attentional_bias: How attention is computed over memory
    - retention_gate_enabled: Whether to use learned retention gates
    - update_algorithm: Memory update strategy
    
    References:
        - Titans Paper: "surprise = ‖∇ℓ‖, momentum smoothing, weight decay"
        - MIRAS Paper: "Memory Architecture × Attentional Bias × Retention Gate × Update Algorithm"
    """
    params = {}
    
    # -------------------------------------------------------------------------
    # Memory Architecture (MIRAS "Memory Architecture" axis)
    # -------------------------------------------------------------------------
    
    # Depth: 1 = single linear, 2-8 = deep MLP
    params['memory_depth'] = trial.suggest_int('memory_depth', 1, 8)
    
    # Width: Hidden dimension per layer
    # Larger = more capacity but more compute
    params['memory_width'] = trial.suggest_int('memory_width', 64, 1024, step=64)
    
    # Multi-head attention for memory retrieval (MIRAS)
    params['memory_heads'] = trial.suggest_int('memory_heads', 1, 8)
    
    # -------------------------------------------------------------------------
    # Surprise/Write Parameters (Titans "surprise-gated write")
    # -------------------------------------------------------------------------
    
    # Surprise threshold: gradient norm cutoff for triggering writes
    # Lower = more writes (more memory updates), higher = selective writes
    params['surprise_threshold'] = trial.suggest_float(
        'surprise_threshold', 0.01, 1.0, log=True
    )
    
    # Write gate mode (MIRAS "Update Algorithm" axis)
    params['write_gate_mode'] = trial.suggest_categorical(
        'write_gate_mode', 
        [m.value for m in WriteGateMode]
    )
    
    # Learning rate for memory weight updates
    # Separate from main network lr for stability
    params['write_lr'] = trial.suggest_float('write_lr', 0.001, 0.1, log=True)
    
    # -------------------------------------------------------------------------
    # Retention/Forgetting Parameters (Titans "weight decay as forgetting")
    # -------------------------------------------------------------------------
    
    # Momentum beta: smoothing factor for surprise estimates
    # Higher = more stable but slower adaptation
    params['momentum_beta'] = trial.suggest_float('momentum_beta', 0.8, 0.99)
    
    # Weight decay: forgetting factor applied to memory weights
    # Higher = memories persist longer, lower = faster forgetting
    params['weight_decay'] = trial.suggest_float('weight_decay', 0.9, 0.999)
    
    # Retention mode (MIRAS "Retention Gate" axis)
    params['retention_mode'] = trial.suggest_categorical(
        'retention_mode',
        [m.value for m in RetentionMode]
    )
    
    # -------------------------------------------------------------------------
    # MIRAS-Specific Parameters
    # -------------------------------------------------------------------------
    
    # Attentional bias for memory retrieval (MIRAS "Attentional Bias" axis)
    params['attentional_bias'] = trial.suggest_categorical(
        'attentional_bias',
        [b.value for b in AttentionalBias]
    )
    
    # Whether to use learned retention gates (vs fixed decay)
    params['retention_gate_enabled'] = trial.suggest_categorical(
        'retention_gate_enabled', [True, False]
    )
    
    # Memory slot count (for slot-based attention)
    if params.get('attentional_bias') == AttentionalBias.SLOT.value:
        params['memory_slots'] = trial.suggest_int('memory_slots', 16, 256, step=16)
    
    # -------------------------------------------------------------------------
    # Compute Budget Constraints
    # -------------------------------------------------------------------------
    
    # Max memory capacity in MB (soft constraint)
    params['memory_budget_mb'] = trial.suggest_float('memory_budget_mb', 10.0, 500.0)
    
    logger.debug(f"Suggested memory params: {params}")
    
    return params


# =============================================================================
# HC-57: SNN PRIORS (Spiking Neural Network)
# =============================================================================

def suggest_snn_params(trial) -> Dict[str, Any]:
    """
    Spiking neural network hyperparameters (HC-57).
    
    For EventProp-style SNN training with spike timing and delay optimization.
    """
    return {
        'spike_threshold': trial.suggest_float('spike_threshold', 0.5, 2.0),
        'leak_rate': trial.suggest_float('leak_rate', 0.8, 0.99),
        'trainable_delays_enabled': trial.suggest_categorical('trainable_delays_enabled', [True, False]),
        'max_delay_ticks': trial.suggest_int('max_delay_ticks', 1, 16),
        'perturbation_strength': trial.suggest_float('perturbation_strength', 0.001, 0.1, log=True),
        'layer_decorrelation_method': trial.suggest_categorical(
            'layer_decorrelation_method', 
            ['noise', 'dropout', 'phase_shift']
        ),
    }


# =============================================================================
# HC-64: CELLULAR AUTOMATA PARAMETERS
# =============================================================================

def suggest_ca_params(trial) -> Dict[str, Any]:
    """
    Cellular automata hyperparameters (HC-64).
    
    For CAT (Cellular Automata Transforms) architecture search.
    """
    return {
        'ca_rule_id': trial.suggest_int('ca_rule_id', 0, 255),  # Elementary CA rules
        'ca_dims': trial.suggest_int('ca_dims', 1, 3),  # Spatial dimensions
        'ca_alphabet_size': trial.suggest_int('ca_alphabet_size', 2, 8),
        'ca_radius': trial.suggest_int('ca_radius', 1, 3),
        'ca_window': trial.suggest_int('ca_window', 3, 7),
        'ca_time_depth': trial.suggest_int('ca_time_depth', 1, 32),
    }


# =============================================================================
# COMBINED SEARCH SPACE
# =============================================================================

def suggest_hyperparameters(trial, config: SearchSpaceConfig) -> Dict[str, Any]:
    """
    Suggest all enabled hyperparameters for a trial.
    
    Args:
        trial: Optuna trial object
        config: SearchSpaceConfig specifying which categories to enable
        
    Returns:
        Dictionary of all suggested hyperparameters
    """
    params = {}
    
    if config.enable_architecture:
        params.update(suggest_architecture_params(trial))
    
    if config.enable_connection:
        params.update(suggest_connection_params(trial))
    
    if config.enable_training:
        params.update(suggest_training_params(trial))
    
    if config.enable_embedding:
        params.update(suggest_embedding_params(trial))
    
    # Extended search spaces (HC-75+)
    if config.enable_memory:
        params.update(suggest_memory_params(trial))
    
    if config.enable_snn:
        params.update(suggest_snn_params(trial))
    
    if config.enable_ca:
        params.update(suggest_ca_params(trial))
    
    # Add constraint metadata
    if config.plv_constraint:
        params['_plv_constraint_min'] = config.plv_constraint[0]
        params['_plv_constraint_max'] = config.plv_constraint[1]
    
    logger.info(f"Suggested {len(params)} hyperparameters across enabled search spaces")
    
    return params


# =============================================================================
# PRESET CONFIGURATIONS
# =============================================================================

# Standard architecture search (original Cerebros)
STANDARD_CONFIG = SearchSpaceConfig(
    enable_architecture=True,
    enable_connection=True,
    enable_training=True,
    enable_embedding=True,
    enable_memory=False,
    enable_snn=False,
    enable_ca=False,
)

# MIRAS/Titans memory search (HC-78)
MEMORY_CONFIG = SearchSpaceConfig(
    enable_architecture=True,
    enable_connection=True,
    enable_training=True,
    enable_embedding=True,
    enable_memory=True,  # HC-78
    enable_snn=False,
    enable_ca=False,
    plv_constraint=(0.3, 0.6),  # Healthy criticality range
)

# Full neuro-symbolic search (HC-57 + HC-64 + HC-78)
FULL_CONFIG = SearchSpaceConfig(
    enable_architecture=True,
    enable_connection=True,
    enable_training=True,
    enable_embedding=True,
    enable_memory=True,   # HC-78
    enable_snn=True,      # HC-57
    enable_ca=True,       # HC-64
    plv_constraint=(0.3, 0.6),
    memory_budget_mb=256.0,
)


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def get_search_space_docs() -> str:
    """Return documentation for all search space parameters."""
    docs = []
    
    docs.append("# Cerebros TPE Search Space Documentation\n")
    
    docs.append("## Architecture Parameters")
    docs.append("- minimum_levels: Minimum network depth (1-3)")
    docs.append("- maximum_levels: Maximum network depth (min-4)")
    docs.append("- minimum_units_per_level: Min units per level (1-4)")
    docs.append("- maximum_units_per_level: Max units per level (min-6)")
    docs.append("- minimum_neurons_per_unit: Min neurons per unit (1-4)")
    docs.append("- maximum_neurons_per_unit: Max neurons per unit (min-6)")
    
    docs.append("\n## Memory Parameters (HC-78)")
    docs.append("- memory_depth: MLP layers in memory module (1-8)")
    docs.append("- memory_width: Hidden dimension per layer (64-1024)")
    docs.append("- memory_heads: Attention heads for retrieval (1-8)")
    docs.append("- surprise_threshold: Gradient norm cutoff (0.01-1.0)")
    docs.append("- write_gate_mode: Gate type (threshold/softmax/topk/gumbel)")
    docs.append("- write_lr: Memory update learning rate (0.001-0.1)")
    docs.append("- momentum_beta: Surprise smoothing factor (0.8-0.99)")
    docs.append("- weight_decay: Memory forgetting factor (0.9-0.999)")
    docs.append("- retention_mode: Decay strategy (decay/gru/none/adaptive)")
    docs.append("- attentional_bias: Attention type (none/softmax/slot)")
    docs.append("- retention_gate_enabled: Use learned gates (bool)")
    
    return "\n".join(docs)


def estimate_memory_footprint(params: Dict[str, Any]) -> float:
    """
    Estimate memory footprint in MB for given parameters.
    
    Args:
        params: Hyperparameter dictionary
        
    Returns:
        Estimated memory usage in MB
    """
    # Base architecture memory
    levels = params.get('maximum_levels', 3)
    units = params.get('maximum_units_per_level', 4)
    neurons = params.get('maximum_neurons_per_unit', 4)
    embedding_dim = params.get('embedding_dim', 18)
    
    # Rough estimate: 4 bytes per float32 parameter
    arch_params = levels * units * neurons * embedding_dim * 4
    arch_mb = arch_params / (1024 * 1024)
    
    # Memory module memory (if enabled)
    memory_mb = 0.0
    if 'memory_depth' in params:
        depth = params.get('memory_depth', 2)
        width = params.get('memory_width', 128)
        heads = params.get('memory_heads', 4)
        
        # Each layer: width * width parameters + biases
        memory_params = depth * (width * width + width)
        # Multi-head attention: 3 * heads * width^2 (Q, K, V projections)
        memory_params += 3 * heads * width * width
        memory_mb = (memory_params * 4) / (1024 * 1024)
    
    return arch_mb + memory_mb
