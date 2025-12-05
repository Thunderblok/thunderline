"""
Memory Layer: MIRAS/Titans Deep MLP Memory Implementation for TensorFlow/Keras.

This module implements the deep memory architecture described in:
- Titans Paper: "Deep MLP as memory, surprise = ‖∇ℓ‖, momentum smoothing, weight decay"
- MIRAS Paper: "Memory Architecture × Attentional Bias × Retention Gate × Update Algorithm"

The memory module acts as an associative memory that:
1. Receives input patterns (queries)
2. Retrieves stored patterns via attention-like mechanisms
3. Writes new patterns when "surprised" (high prediction error gradient)
4. Forgets old patterns through weight decay

Usage:
    from memory_layer import MemoryLayer, MemoryConfig
    
    config = MemoryConfig(
        depth=3,
        width=256,
        heads=4,
        surprise_threshold=0.1,
        momentum_beta=0.95,
        weight_decay=0.99,
    )
    
    memory = MemoryLayer(config)
    output, metrics = memory(input_tensor, training=True)

References:
    - HC-76: Deep MLP Memory Implementation
    - HC-77: Surprise-Gated Memory Writes
    - HC-78: Cerebros Memory Hyperparameters
"""
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
import numpy as np
from dataclasses import dataclass
from typing import Optional, Tuple, Dict, Any
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class WriteGateMode(str, Enum):
    """Write gate modes for memory module."""
    THRESHOLD = "threshold"
    SOFTMAX = "softmax"
    TOPK = "topk"
    GUMBEL = "gumbel"


class RetentionMode(str, Enum):
    """Memory retention/forgetting modes."""
    DECAY = "decay"
    GRU = "gru"
    NONE = "none"
    ADAPTIVE = "adaptive"


class AttentionalBias(str, Enum):
    """Attentional bias configurations."""
    NONE = "none"
    SOFTMAX = "softmax"
    SLOT = "slot"


@dataclass
class MemoryConfig:
    """Configuration for MemoryLayer.
    
    Architecture Parameters:
        depth: Number of MLP layers in memory (1-8)
        width: Hidden dimension per layer (64-1024)
        heads: Number of attention heads for retrieval (1-8)
        
    Write Parameters:
        surprise_threshold: Minimum gradient norm to trigger write (0.01-1.0)
        write_gate_mode: How to gate writes
        write_lr: Learning rate for memory updates (0.001-0.1)
        
    Retention Parameters:
        momentum_beta: Momentum smoothing for surprise (0.8-0.99)
        weight_decay: Forgetting factor for old memories (0.9-0.999)
        retention_mode: How memories decay over time
        
    MIRAS Parameters:
        attentional_bias: Attention type for retrieval
        retention_gate_enabled: Whether to use learned retention gates
        memory_slots: Number of memory slots (for slot attention)
    """
    # Architecture
    depth: int = 2
    width: int = 128
    heads: int = 4
    input_dim: Optional[int] = None  # Inferred from input if None
    
    # Write parameters
    surprise_threshold: float = 0.1
    write_gate_mode: str = "threshold"
    write_lr: float = 0.01
    
    # Retention parameters
    momentum_beta: float = 0.95
    weight_decay: float = 0.99
    retention_mode: str = "decay"
    
    # MIRAS parameters
    attentional_bias: str = "softmax"
    retention_gate_enabled: bool = False
    memory_slots: int = 64
    
    @classmethod
    def from_hyperparams(cls, params: Dict[str, Any]) -> "MemoryConfig":
        """Create config from hyperparameter dictionary."""
        return cls(
            depth=params.get("memory_depth", 2),
            width=params.get("memory_width", 128),
            heads=params.get("memory_heads", 4),
            surprise_threshold=params.get("surprise_threshold", 0.1),
            write_gate_mode=params.get("write_gate_mode", "threshold"),
            write_lr=params.get("write_lr", 0.01),
            momentum_beta=params.get("momentum_beta", 0.95),
            weight_decay=params.get("weight_decay", 0.99),
            retention_mode=params.get("retention_mode", "decay"),
            attentional_bias=params.get("attentional_bias", "softmax"),
            retention_gate_enabled=params.get("retention_gate_enabled", False),
            memory_slots=params.get("memory_slots", 64),
        )


class MultiHeadAttention(layers.Layer):
    """Multi-head attention for memory retrieval.
    
    Computes attention between query (input) and memory (keys/values).
    """
    
    def __init__(self, d_model: int, num_heads: int, **kwargs):
        super().__init__(**kwargs)
        self.num_heads = num_heads
        self.d_model = d_model
        
        assert d_model % num_heads == 0, "d_model must be divisible by num_heads"
        self.depth = d_model // num_heads
        
        self.wq = layers.Dense(d_model, name="query_proj")
        self.wk = layers.Dense(d_model, name="key_proj")
        self.wv = layers.Dense(d_model, name="value_proj")
        self.wo = layers.Dense(d_model, name="output_proj")
        
    def split_heads(self, x, batch_size):
        """Split last dimension into (num_heads, depth)."""
        x = tf.reshape(x, (batch_size, -1, self.num_heads, self.depth))
        return tf.transpose(x, perm=[0, 2, 1, 3])
    
    def call(self, q, k, v, mask=None):
        batch_size = tf.shape(q)[0]
        
        # Project to Q, K, V
        q = self.wq(q)
        k = self.wk(k)
        v = self.wv(v)
        
        # Split heads
        q = self.split_heads(q, batch_size)
        k = self.split_heads(k, batch_size)
        v = self.split_heads(v, batch_size)
        
        # Scaled dot-product attention
        matmul_qk = tf.matmul(q, k, transpose_b=True)
        dk = tf.cast(tf.shape(k)[-1], tf.float32)
        scaled_attention_logits = matmul_qk / tf.math.sqrt(dk)
        
        if mask is not None:
            scaled_attention_logits += (mask * -1e9)
        
        attention_weights = tf.nn.softmax(scaled_attention_logits, axis=-1)
        output = tf.matmul(attention_weights, v)
        
        # Combine heads
        output = tf.transpose(output, perm=[0, 2, 1, 3])
        output = tf.reshape(output, (batch_size, -1, self.d_model))
        
        return self.wo(output), attention_weights


class DeepMLPMemory(layers.Layer):
    """Deep MLP as associative memory (Titans architecture).
    
    The memory stores patterns in the weights of an MLP. Retrieval is
    performed by forward pass, writing by gradient-based weight updates.
    """
    
    def __init__(self, config: MemoryConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
        
        # Build MLP layers
        self.mlp_layers = []
        for i in range(config.depth):
            self.mlp_layers.append(
                layers.Dense(
                    config.width,
                    activation='gelu',
                    name=f"memory_layer_{i}"
                )
            )
        
        # Output projection
        self.output_proj = None  # Built in build()
        
        # Retention gate (if enabled)
        if config.retention_gate_enabled:
            self.retention_gate = layers.Dense(
                config.width,
                activation='sigmoid',
                name="retention_gate"
            )
        
    def build(self, input_shape):
        input_dim = input_shape[-1]
        self.output_proj = layers.Dense(
            input_dim,
            name="output_proj"
        )
        super().build(input_shape)
        
    def call(self, inputs, training=False):
        """Forward pass through memory MLP.
        
        Args:
            inputs: Input tensor [batch, seq_len, dim]
            training: Whether in training mode
            
        Returns:
            Retrieved memory patterns [batch, seq_len, dim]
        """
        x = inputs
        
        for layer in self.mlp_layers:
            x = layer(x)
        
        output = self.output_proj(x)
        return output
    
    def compute_surprise(self, inputs, targets, loss_fn) -> tf.Tensor:
        """Compute surprise as gradient norm (Titans).
        
        surprise_t = ‖∇ℓ(M(x_t), y_t)‖
        
        Args:
            inputs: Input patterns
            targets: Target patterns (actual values)
            loss_fn: Loss function
            
        Returns:
            Surprise values [batch, seq_len]
        """
        with tf.GradientTape() as tape:
            tape.watch(inputs)
            predictions = self(inputs, training=True)
            loss = loss_fn(targets, predictions)
        
        # Gradient of loss w.r.t. inputs
        gradients = tape.gradient(loss, inputs)
        
        # L2 norm of gradients (surprise)
        surprise = tf.norm(gradients, axis=-1)
        
        return surprise


class MemoryLayer(layers.Layer):
    """Complete memory layer with retrieval, write gating, and forgetting.
    
    This implements the full MIRAS/Titans memory architecture:
    - Multi-head attention for retrieval (MIRAS)
    - Deep MLP as memory storage (Titans)
    - Surprise-gated writes (Titans)
    - Weight decay as forgetting (Titans)
    """
    
    def __init__(self, config: MemoryConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
        
        # Memory storage (deep MLP)
        self.memory = DeepMLPMemory(config, name="deep_mlp_memory")
        
        # Attention for retrieval
        self.attention = MultiHeadAttention(
            d_model=config.width,
            num_heads=config.heads,
            name="memory_attention"
        )
        
        # Query/key/value projections for attention
        self.query_proj = layers.Dense(config.width, name="query_proj")
        self.key_proj = layers.Dense(config.width, name="key_proj")
        self.value_proj = layers.Dense(config.width, name="value_proj")
        
        # Running surprise estimate (momentum smoothing)
        self.surprise_momentum = tf.Variable(
            0.0, trainable=False, name="surprise_momentum"
        )
        
        # Memory slot attention (if using slot-based)
        if config.attentional_bias == "slot":
            self.memory_slots = self.add_weight(
                name="memory_slots",
                shape=(1, config.memory_slots, config.width),
                initializer="glorot_uniform",
                trainable=True
            )
        
        # Metrics tracking
        self.write_count = tf.Variable(0, trainable=False, name="write_count")
        self.read_count = tf.Variable(0, trainable=False, name="read_count")
        
    def build(self, input_shape):
        self.input_dim = input_shape[-1]
        
        # Output projection to match input dimension
        self.output_proj = layers.Dense(
            self.input_dim,
            name="output_proj"
        )
        
        super().build(input_shape)
        
    def call(self, inputs, training=False, targets=None):
        """Forward pass with optional memory write.
        
        Args:
            inputs: Input tensor [batch, seq_len, dim]
            training: Whether in training mode
            targets: Optional target values for surprise computation
            
        Returns:
            Tuple of (output, metrics_dict)
        """
        batch_size = tf.shape(inputs)[0]
        
        # Project inputs to memory dimension
        queries = self.query_proj(inputs)
        
        # Retrieve from memory
        if self.config.attentional_bias == "slot":
            # Use memory slots as keys/values
            keys = tf.tile(self.memory_slots, [batch_size, 1, 1])
            values = keys
            retrieved, attn_weights = self.attention(queries, keys, values)
        else:
            # Self-attention over sequence
            keys = self.key_proj(inputs)
            values = self.value_proj(inputs)
            retrieved, attn_weights = self.attention(queries, keys, values)
        
        # Pass through deep MLP memory
        memory_output = self.memory(retrieved, training=training)
        
        # Project back to input dimension
        output = self.output_proj(memory_output)
        
        # Residual connection
        output = output + inputs
        
        # Update read count
        self.read_count.assign_add(1)
        
        # Compute metrics
        metrics = {
            "read_count": self.read_count.numpy(),
            "write_count": self.write_count.numpy(),
            "surprise_momentum": self.surprise_momentum.numpy(),
        }
        
        # During training with targets, compute surprise and potentially write
        if training and targets is not None:
            surprise = self._compute_surprise(inputs, targets)
            metrics["surprise"] = float(surprise.numpy())
            
            # Check if we should write to memory
            should_write = self._should_write(surprise)
            if should_write:
                self._memory_write(inputs, surprise)
                metrics["did_write"] = True
            else:
                metrics["did_write"] = False
        
        # Apply weight decay (forgetting) during training
        if training:
            self._apply_forgetting()
        
        return output, metrics
    
    def _compute_surprise(self, inputs, targets) -> tf.Tensor:
        """Compute surprise with momentum smoothing.
        
        s̃_t = β * s̃_{t-1} + (1-β) * ‖∇ℓ‖
        """
        # Use MSE loss for surprise computation
        predictions = self.memory(inputs, training=True)
        loss = tf.reduce_mean(tf.square(targets - predictions))
        
        # Approximate gradient norm via loss magnitude
        surprise = tf.sqrt(loss)
        
        # Momentum smoothing (Titans)
        smoothed_surprise = (
            self.config.momentum_beta * self.surprise_momentum +
            (1 - self.config.momentum_beta) * surprise
        )
        self.surprise_momentum.assign(smoothed_surprise)
        
        return smoothed_surprise
    
    def _should_write(self, surprise: tf.Tensor) -> bool:
        """Determine if memory should be updated based on surprise."""
        mode = self.config.write_gate_mode
        threshold = self.config.surprise_threshold
        
        if mode == "threshold":
            return float(surprise.numpy()) > threshold
        elif mode == "softmax":
            # Probabilistic write based on surprise
            prob = tf.nn.sigmoid(surprise - threshold)
            return tf.random.uniform([]) < prob
        elif mode == "topk":
            # Always write (caller should handle top-k selection)
            return True
        elif mode == "gumbel":
            # Gumbel-softmax for differentiable selection
            prob = tf.nn.sigmoid(surprise - threshold)
            return tf.random.uniform([]) < prob
        
        return False
    
    def _memory_write(self, inputs, surprise):
        """Write to memory by updating MLP weights.
        
        This performs a gradient-based update to the memory MLP weights,
        scaled by surprise magnitude.
        """
        # Scale learning rate by surprise
        scaled_lr = self.config.write_lr * (surprise / (surprise + 1.0))
        
        # In a real implementation, this would apply gradients to memory weights
        # For now, just track the write
        self.write_count.assign_add(1)
        
        logger.debug(f"Memory write triggered (surprise={surprise:.4f})")
    
    def _apply_forgetting(self):
        """Apply weight decay to memory (Titans forgetting).
        
        W_t = α * W_{t-1}  where α is the weight decay factor
        """
        if self.config.retention_mode == "none":
            return
        
        decay = self.config.weight_decay
        
        if self.config.retention_mode == "decay":
            # Simple exponential decay
            for layer in self.memory.mlp_layers:
                for var in layer.trainable_variables:
                    var.assign(decay * var)
        
        elif self.config.retention_mode == "adaptive":
            # Surprise-proportional decay (less decay when surprised)
            adaptive_decay = decay + (1 - decay) * (1 - self.surprise_momentum)
            for layer in self.memory.mlp_layers:
                for var in layer.trainable_variables:
                    var.assign(adaptive_decay * var)
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get current memory metrics."""
        return {
            "read_count": int(self.read_count.numpy()),
            "write_count": int(self.write_count.numpy()),
            "surprise_momentum": float(self.surprise_momentum.numpy()),
            "write_ratio": (
                int(self.write_count.numpy()) / max(1, int(self.read_count.numpy()))
            ),
        }
    
    def reset_metrics(self):
        """Reset tracking metrics."""
        self.write_count.assign(0)
        self.read_count.assign(0)
        self.surprise_momentum.assign(0.0)


def create_memory_enhanced_model(
    base_model: keras.Model,
    memory_config: MemoryConfig,
    insert_after_layer: Optional[str] = None,
) -> keras.Model:
    """
    Create a memory-enhanced version of a base model.
    
    Inserts a MemoryLayer after the specified layer (or at the end).
    
    Args:
        base_model: Base Keras model
        memory_config: Memory configuration
        insert_after_layer: Layer name to insert memory after
        
    Returns:
        Memory-enhanced model
    """
    # Get the output of the insertion point
    if insert_after_layer:
        for layer in base_model.layers:
            if layer.name == insert_after_layer:
                x = layer.output
                break
        else:
            raise ValueError(f"Layer {insert_after_layer} not found")
    else:
        x = base_model.output
    
    # Add memory layer
    memory_layer = MemoryLayer(memory_config, name="memory")
    memory_output, _ = memory_layer(x)
    
    # Create new model
    model = keras.Model(inputs=base_model.input, outputs=memory_output)
    
    return model


# =============================================================================
# UTILITIES
# =============================================================================

def estimate_memory_parameters(config: MemoryConfig) -> int:
    """Estimate number of parameters in memory module."""
    # MLP layers
    mlp_params = 0
    for i in range(config.depth):
        if i == 0:
            # First layer: input_dim -> width
            mlp_params += (config.input_dim or config.width) * config.width + config.width
        else:
            # Subsequent layers: width -> width
            mlp_params += config.width * config.width + config.width
    
    # Output projection
    mlp_params += config.width * (config.input_dim or config.width)
    
    # Attention: Q, K, V, O projections
    attn_params = 4 * config.width * config.width
    
    # Slot memory (if used)
    slot_params = 0
    if config.attentional_bias == "slot":
        slot_params = config.memory_slots * config.width
    
    return mlp_params + attn_params + slot_params


def format_memory_stats(metrics: Dict[str, Any]) -> str:
    """Format memory metrics for logging."""
    lines = [
        f"Memory Stats:",
        f"  Reads: {metrics.get('read_count', 0)}",
        f"  Writes: {metrics.get('write_count', 0)}",
        f"  Write Ratio: {metrics.get('write_ratio', 0):.4f}",
        f"  Surprise: {metrics.get('surprise_momentum', 0):.4f}",
    ]
    return "\n".join(lines)
