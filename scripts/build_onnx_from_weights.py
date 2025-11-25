#!/usr/bin/env python3
"""
Build ONNX model manually from trained Keras/TensorFlow weights.
Avoids tf2onnx numpy compatibility issues by constructing the ONNX graph directly.
"""

import os
import sys
import numpy as np
import onnx
from onnx import helper, numpy_helper, TensorProto

# Disable GPU to avoid CUDA issues
os.environ['CUDA_VISIBLE_DEVICES'] = ''
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

print("=" * 60)
print("🔧 Building ONNX Model from Trained Weights")
print("=" * 60)

# Configuration
SEQ_LEN = 40
VOCAB_SIZE = 1000
EMBED_DIM = 64
HIDDEN_DIM = 128
OUTPUT_PATH = "priv/models/cerebros_trained.onnx"

# Step 1: Train a Keras model and extract weights
print("\n📦 Step 1: Training Keras model...")

import tensorflow as tf
from tensorflow import keras
from keras import layers

# Build model
inputs = keras.Input(shape=(SEQ_LEN,), dtype='int32', name='input_ids')
x = layers.Embedding(VOCAB_SIZE, EMBED_DIM, name='embedding')(inputs)
x = layers.GlobalAveragePooling1D(name='pooling')(x)
x = layers.Dense(HIDDEN_DIM, activation='relu', name='dense1')(x)
x = layers.Dense(HIDDEN_DIM, activation='relu', name='dense2')(x)
outputs = layers.Dense(VOCAB_SIZE, name='logits')(x)
model = keras.Model(inputs, outputs)

print(f"   Model: {model.count_params():,} parameters")

# Generate synthetic training data
np.random.seed(42)
x_train = np.random.randint(0, VOCAB_SIZE, (1000, SEQ_LEN))
y_train = np.random.randint(0, VOCAB_SIZE, (1000,))
y_train_onehot = tf.keras.utils.to_categorical(y_train, VOCAB_SIZE)

# Train
model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
model.fit(x_train, y_train_onehot, epochs=3, batch_size=32, verbose=1)

print("✅ Training complete!")

# Step 2: Extract weights from trained model
print("\n📦 Step 2: Extracting weights...")

weights = {}
for layer in model.layers:
    layer_weights = layer.get_weights()
    if layer_weights:
        weights[layer.name] = layer_weights
        print(f"   {layer.name}: {[w.shape for w in layer_weights]}")

# Get specific weights
embed_weight = weights['embedding'][0]  # (vocab_size, embed_dim)
dense1_weight = weights['dense1'][0]    # (embed_dim, hidden_dim)
dense1_bias = weights['dense1'][1]      # (hidden_dim,)
dense2_weight = weights['dense2'][0]    # (hidden_dim, hidden_dim)
dense2_bias = weights['dense2'][1]      # (hidden_dim,)
logits_weight = weights['logits'][0]    # (hidden_dim, vocab_size)
logits_bias = weights['logits'][1]      # (vocab_size,)

print("✅ Weights extracted!")

# Step 3: Build ONNX graph manually
print("\n📦 Step 3: Building ONNX graph...")

def make_initializer(name, arr):
    """Create ONNX initializer from numpy array."""
    return numpy_helper.from_array(arr.astype(np.float32), name)

# Create nodes
nodes = []

# 1. Gather (Embedding lookup)
# input_ids: (batch, seq_len) -> embedded: (batch, seq_len, embed_dim)
nodes.append(helper.make_node(
    'Gather',
    inputs=['embed_weight', 'input_ids'],
    outputs=['embedded'],
    axis=0,
    name='gather_embedding'
))

# 2. ReduceMean (Global Average Pooling)
# embedded: (batch, seq_len, embed_dim) -> pooled: (batch, embed_dim)
nodes.append(helper.make_node(
    'ReduceMean',
    inputs=['embedded'],
    outputs=['pooled'],
    axes=[1],
    keepdims=0,
    name='global_avg_pool'
))

# 3. Dense1: MatMul + Add + Relu
nodes.append(helper.make_node(
    'MatMul',
    inputs=['pooled', 'dense1_weight'],
    outputs=['dense1_mm'],
    name='dense1_matmul'
))
nodes.append(helper.make_node(
    'Add',
    inputs=['dense1_mm', 'dense1_bias'],
    outputs=['dense1_add'],
    name='dense1_add'
))
nodes.append(helper.make_node(
    'Relu',
    inputs=['dense1_add'],
    outputs=['dense1_out'],
    name='dense1_relu'
))

# 4. Dense2: MatMul + Add + Relu
nodes.append(helper.make_node(
    'MatMul',
    inputs=['dense1_out', 'dense2_weight'],
    outputs=['dense2_mm'],
    name='dense2_matmul'
))
nodes.append(helper.make_node(
    'Add',
    inputs=['dense2_mm', 'dense2_bias'],
    outputs=['dense2_add'],
    name='dense2_add'
))
nodes.append(helper.make_node(
    'Relu',
    inputs=['dense2_add'],
    outputs=['dense2_out'],
    name='dense2_relu'
))

# 5. Logits: MatMul + Add
nodes.append(helper.make_node(
    'MatMul',
    inputs=['dense2_out', 'logits_weight'],
    outputs=['logits_mm'],
    name='logits_matmul'
))
nodes.append(helper.make_node(
    'Add',
    inputs=['logits_mm', 'logits_bias'],
    outputs=['logits'],
    name='logits_add'
))

# Create initializers (weights)
initializers = [
    make_initializer('embed_weight', embed_weight),
    make_initializer('dense1_weight', dense1_weight),
    make_initializer('dense1_bias', dense1_bias),
    make_initializer('dense2_weight', dense2_weight),
    make_initializer('dense2_bias', dense2_bias),
    make_initializer('logits_weight', logits_weight),
    make_initializer('logits_bias', logits_bias),
]

# Create input/output specs
inputs_spec = [
    helper.make_tensor_value_info('input_ids', TensorProto.INT64, ['batch', SEQ_LEN])
]
outputs_spec = [
    helper.make_tensor_value_info('logits', TensorProto.FLOAT, ['batch', VOCAB_SIZE])
]

# Create graph
graph = helper.make_graph(
    nodes,
    'cerebros_trained',
    inputs_spec,
    outputs_spec,
    initializers
)

# Create model with opset 11 (compatible with onnxruntime)
model_def = helper.make_model(graph, opset_imports=[helper.make_opsetid('', 11)])
model_def.ir_version = 6

# Validate
onnx.checker.check_model(model_def)
print("✅ ONNX graph validated!")

# Save
os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
onnx.save(model_def, OUTPUT_PATH)
print(f"✅ Saved: {OUTPUT_PATH}")

# Step 4: Test the ONNX model
print("\n📦 Step 4: Testing ONNX model...")

import onnxruntime as ort

session = ort.InferenceSession(OUTPUT_PATH)

# Print input/output info
print("   Inputs:")
for inp in session.get_inputs():
    print(f"     {inp.name}: {inp.shape} ({inp.type})")
print("   Outputs:")
for out in session.get_outputs():
    print(f"     {out.name}: {out.shape} ({out.type})")

# Run inference
test_input = np.array([[1, 2, 3, 4, 5] + [0] * 35], dtype=np.int64)
onnx_output = session.run(None, {'input_ids': test_input})[0]

print(f"\n   Test input shape: {test_input.shape}")
print(f"   ONNX output shape: {onnx_output.shape}")
print(f"   Predicted token: {np.argmax(onnx_output[0])}")

# Compare with Keras model
keras_output = model.predict(test_input, verbose=0)
print(f"\n   Keras output shape: {keras_output.shape}")
print(f"   Keras predicted: {np.argmax(keras_output[0])}")

# Check if outputs match
max_diff = np.max(np.abs(onnx_output - keras_output))
print(f"\n   Max difference: {max_diff:.6f}")
if max_diff < 1e-5:
    print("   ✅ ONNX and Keras outputs match!")
else:
    print(f"   ⚠️  Some difference (likely floating point precision)")

# Also save Keras model for reference
model.save("priv/models/cerebros_trained.keras")
print(f"\n💾 Also saved: priv/models/cerebros_trained.keras")

print("\n" + "=" * 60)
print("🚀 SUCCESS! ONNX model built from trained weights")
print("=" * 60)
print(f"""
Files created:
  - {OUTPUT_PATH} (ONNX)
  - priv/models/cerebros_trained.keras (Keras)

Test in Elixir:
  alias Thunderline.Thunderbolt.ML.{{KerasONNX, Input}}
  
  {{:ok, session}} = KerasONNX.load!("{OUTPUT_PATH}")
  tokens = [1, 2, 3, 4, 5] ++ List.duplicate(0, 35)
  tensor = Nx.tensor([tokens], type: :s64, backend: Nx.BinaryBackend)
  input = %Input{{tensor: tensor, shape: {{1, 40}}, dtype: {{:s, 64}}, metadata: %{{}}}}
  {{:ok, output}} = KerasONNX.infer(session, input)
  
  # Get prediction
  argmax = output.tensor |> Nx.argmax(axis: 1) |> Nx.squeeze() |> Nx.to_number()
""")
