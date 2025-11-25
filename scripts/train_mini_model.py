#!/usr/bin/env python3
"""
Minimal Cerebros-style model training for ONNX export testing.
Skips NAS - just creates a simple model, trains briefly, and exports to ONNX.
"""

import os
import sys
import numpy as np

# Add paths
sys.path.insert(0, "/home/mo/DEV/Thunderline/python/cerebros/core")

print("=" * 60)
print("🧠 Minimal Model Training for ONNX Export")
print("=" * 60)

import tensorflow as tf
print(f"✓ TensorFlow: {tf.__version__}")

# Configuration
MAX_SEQ_LENGTH = 40
VOCAB_SIZE = 1000  # Small vocab for testing
EMBEDDING_DIM = 64
HIDDEN_DIM = 128
BATCH_SIZE = 8
EPOCHS = 3

print(f"\n📐 Config: seq_len={MAX_SEQ_LENGTH}, vocab={VOCAB_SIZE}, embed={EMBEDDING_DIM}")

# Create a simple transformer-like model
print("\n🔨 Building model...")

inputs = tf.keras.Input(shape=(MAX_SEQ_LENGTH,), dtype=tf.int32, name="input_ids")

# Embedding
x = tf.keras.layers.Embedding(VOCAB_SIZE, EMBEDDING_DIM)(inputs)

# Simple positional encoding (learned)
positions = tf.keras.layers.Embedding(MAX_SEQ_LENGTH, EMBEDDING_DIM)(
    tf.range(MAX_SEQ_LENGTH)
)
x = x + positions

# A few dense layers (simplified from Cerebros architecture)
x = tf.keras.layers.Dense(HIDDEN_DIM, activation='relu')(x)
x = tf.keras.layers.Dense(HIDDEN_DIM, activation='relu')(x)
x = tf.keras.layers.GlobalAveragePooling1D()(x)
x = tf.keras.layers.Dense(HIDDEN_DIM, activation='relu')(x)

# Output layer - predict next token probabilities
outputs = tf.keras.layers.Dense(VOCAB_SIZE, name="logits")(x)

model = tf.keras.Model(inputs=inputs, outputs=outputs)
model.compile(
    optimizer='adam',
    loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
    metrics=['accuracy']
)

print(f"✓ Model built: {model.count_params():,} parameters")
model.summary()

# Generate synthetic training data
print("\n📊 Generating synthetic data...")
num_samples = 500
X_train = np.random.randint(0, VOCAB_SIZE, (num_samples, MAX_SEQ_LENGTH)).astype(np.int32)
y_train = np.random.randint(0, VOCAB_SIZE, (num_samples,)).astype(np.int32)

print(f"✓ Training data: {X_train.shape}")

# Train
print(f"\n🏋️ Training for {EPOCHS} epochs...")
history = model.fit(
    X_train, y_train,
    batch_size=BATCH_SIZE,
    epochs=EPOCHS,
    validation_split=0.1,
    verbose=1
)

print(f"✓ Training complete!")

# Save Keras model
os.makedirs("priv/models", exist_ok=True)
keras_path = "priv/models/cerebros_mini.keras"
model.save(keras_path)
print(f"\n💾 Keras model saved: {keras_path}")

# Convert to ONNX
print("\n🔄 Converting to ONNX...")
import subprocess
import onnx

onnx_path = "priv/models/cerebros_mini.onnx"

# Use command line tf2onnx to avoid numpy compatibility issue
result = subprocess.run([
    "python", "-m", "tf2onnx.convert",
    "--saved-model", keras_path.replace('.keras', '_saved'),
    "--output", onnx_path,
    "--opset", "14"
], capture_output=True, text=True)

# First save as SavedModel format for tf2onnx CLI
saved_model_path = keras_path.replace('.keras', '_saved')
model.export(saved_model_path)
print(f"✓ SavedModel exported: {saved_model_path}")

# Now convert with tf2onnx CLI
result = subprocess.run([
    "python", "-m", "tf2onnx.convert", 
    "--saved-model", saved_model_path,
    "--output", onnx_path,
    "--opset", "14"
], capture_output=True, text=True)

if result.returncode != 0:
    print(f"tf2onnx stderr: {result.stderr}")
    # Try alternative: use onnx directly via keras2onnx pattern
    print("Trying alternative ONNX export...")
    import tf2onnx
    # Patch numpy issue
    import numpy as np
    np.object = object
    np.bool = bool
    np.int = int
    np.float = float
    np.complex = complex
    np.str = str
    
    input_signature = [tf.TensorSpec(shape=(None, MAX_SEQ_LENGTH), dtype=tf.int32, name="input_ids")]
    model_proto, _ = tf2onnx.convert.from_keras(
        model,
        input_signature=input_signature,
        opset=14,
        output_path=onnx_path
    )

print(f"✓ ONNX model saved: {onnx_path}")

# Verify ONNX
onnx_model = onnx.load(onnx_path)
onnx.checker.check_model(onnx_model)
print(f"✓ ONNX verification passed!")

# Test inference
print("\n🧪 Testing ONNX inference...")
import onnxruntime as ort

session = ort.InferenceSession(onnx_path)
test_input = np.random.randint(0, VOCAB_SIZE, (1, MAX_SEQ_LENGTH)).astype(np.int32)
output = session.run(None, {"input_ids": test_input})[0]

print(f"✓ Input shape: {test_input.shape}")
print(f"✓ Output shape: {output.shape}")
print(f"✓ Top 5 predicted tokens: {np.argsort(output[0])[-5:][::-1]}")

print("\n" + "=" * 60)
print("✅ SUCCESS! Model ready for Ash.AI integration")
print("=" * 60)
print(f"\nFiles created:")
print(f"  - {keras_path}")
print(f"  - {onnx_path}")
print(f"\nTest in Elixir:")
print(f'  Thunderline.Thunderbolt.Resources.OnnxInference.infer("{onnx_path}", %{{data: [[1,2,3,...]]}}, %{{}})')
