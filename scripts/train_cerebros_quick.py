#!/usr/bin/env python3
"""
Quick Cerebros LLM Training & ONNX Export

A simplified script to train a small LLM and export to ONNX for Thunderline testing.
Based on the demo_train_an_llm_with_cerebros notebook.
"""

import os
import sys

# Add our local cerebros packages to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, "python/cerebros/core"))

print("=" * 60)
print("🧠 Cerebros Quick Training Script")
print("=" * 60)

# Suppress TensorFlow warnings
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import tensorflow as tf
import numpy as np
from transformers import AutoTokenizer
from gc import collect

print(f"✓ TensorFlow version: {tf.__version__}")
print(f"✓ GPU available: {len(tf.config.list_physical_devices('GPU')) > 0}")

# Import Cerebros components
print("\n📦 Loading Cerebros components...")
from cerebros.simplecerebrosrandomsearch.simple_cerebros_random_search import SimpleCerebrosRandomSearch
from cerebrosllmutils.llm_utils import (
    CerebrosNotGPT, 
    InterleavedRoPE, 
    Perplexity,
    WarmupCosineDecayRestarts
)
from vanilladatasets.web_english_bible import web_english_bible
print("✓ Cerebros components loaded")

# ============================================================
# Configuration - keep it small for quick testing
# ============================================================
BATCH_SIZE = 4
MAX_SEQ_LENGTH = 40
PROMPT_LENGTH = MAX_SEQ_LENGTH - 1
EMBEDDING_DIM = 128
PROJECTION_N = 3
PHASE_I_A_SAMPLES = 5       # Reduced for speed
PHASE_I_A_EPOCHS = 3        # Reduced for speed  
PHASE_I_B_SAMPLES = 10      # Reduced for speed
PHASE_I_B_EPOCHS = 5        # Reduced for speed
TRIAL_NUMBER = 1

print(f"\n📊 Configuration:")
print(f"   Batch size: {BATCH_SIZE}")
print(f"   Max sequence length: {MAX_SEQ_LENGTH}")
print(f"   Embedding dim: {EMBEDDING_DIM}")
print(f"   Phase I-a samples: {PHASE_I_A_SAMPLES}")
print(f"   Phase I-b samples: {PHASE_I_B_SAMPLES}")

# ============================================================
# Load tokenizer
# ============================================================
print("\n📖 Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained("HuggingFaceTB/SmolLM3-3B")
VOCABULARY_SIZE = tokenizer.vocab_size
print(f"✓ Tokenizer loaded (vocab_size: {VOCABULARY_SIZE})")

# ============================================================
# Load and prepare data
# ============================================================
print("\n📚 Loading Bible text dataset...")
bible_text = web_english_bible()
print(f"✓ Loaded {len(bible_text)} text samples")

def prepare_data(data_0, tokenizer_0, max_seq_length, prompt_length):
    """Prepare training data from raw text."""
    input_ids_list = []
    labels_list = []
    
    for text in data_0:
        tokens = tokenizer_0.encode(text, add_special_tokens=False)
        
        # Create sliding window samples
        for i in range(0, len(tokens) - max_seq_length, max_seq_length // 2):
            chunk = tokens[i:i + max_seq_length]
            if len(chunk) == max_seq_length:
                input_ids = chunk[:prompt_length]
                # Pad input to max_seq_length
                input_ids = input_ids + [tokenizer_0.pad_token_id or 0] * (max_seq_length - len(input_ids))
                
                # Label is one-hot of next token
                next_token = chunk[prompt_length]
                label = np.zeros(VOCABULARY_SIZE, dtype=np.float32)
                label[next_token] = 1.0
                
                input_ids_list.append(input_ids)
                labels_list.append(label)
    
    return input_ids_list, labels_list, len(input_ids_list)

# Prepare Phase I-a data (small subset)
print(f"\n🔧 Preparing Phase I-a training data...")
phase_i_a_samples = bible_text[:PHASE_I_A_SAMPLES]
train_inputs, train_labels, n_samples = prepare_data(
    phase_i_a_samples, tokenizer, MAX_SEQ_LENGTH, PROMPT_LENGTH
)
print(f"✓ Created {n_samples} training samples")

# Convert to tensors
X_train = np.array(train_inputs, dtype=np.int32)
y_train = np.array(train_labels, dtype=np.float32)

# ============================================================
# Build the model using SimpleCerebrosRandomSearch (NAS)
# ============================================================
print("\n🏗️ Building model with Cerebros NAS...")

# Create embedding model
input_layer = tf.keras.layers.Input(shape=(MAX_SEQ_LENGTH,), dtype=tf.int32, name="input_ids")

# Token embedding
token_embedding = tf.keras.layers.Embedding(
    input_dim=VOCABULARY_SIZE,
    output_dim=EMBEDDING_DIM,
    name="token_embedding"
)(input_layer)

# Positional embedding with iRoPE
positional_embedding = InterleavedRoPE(
    dim=EMBEDDING_DIM,
    max_seq_len=MAX_SEQ_LENGTH,
    base=10000.0,
    name="irope"
)(token_embedding)

# Concatenate and project
combined = tf.keras.layers.Concatenate(axis=-1)([token_embedding, positional_embedding])
projected = tf.keras.layers.Dense(EMBEDDING_DIM * PROJECTION_N, activation='relu')(combined)
flattened = tf.keras.layers.Flatten()(projected)

base_model = tf.keras.Model(inputs=input_layer, outputs=flattened, name="embedding_model")
print(f"✓ Base embedding model built (output shape: {base_model.output_shape})")

# NAS configuration (minimal for speed)
nas = SimpleCerebrosRandomSearch(
    unit_type='dense',
    moieties_to_try=[1, 2],  # Reduced
    rows_to_try=[1, 2],      # Reduced
    connectivity_chances_to_try=[0.3, 0.5],  # Reduced
    predecessor_level_connection_affinity_factor_to_try=[1.0],
    successor_level_connection_affinity_factor_to_try=[1.0],
    first_layer_units_to_try=[128, 256],  # Reduced
    last_layer_units_to_try=[VOCABULARY_SIZE],
    first_layer_activation_to_try=['relu'],
    rest_of_layers_activation_to_try=['relu'],
    last_layer_activation_to_try=['linear'],
    loss=tf.keras.losses.CategoricalCrossentropy(),
    optimizer_to_try=[tf.keras.optimizers.AdamW(learning_rate=0.001)],
    evaluation_metric=Perplexity(name='perplexity'),
    evaluation_metric_direction='min',
    input_model=base_model,
    epochs=PHASE_I_A_EPOCHS,
    patience=2,
    batch_size=BATCH_SIZE,
    verbose=1
)

# Run NAS
print("\n🔍 Running Neural Architecture Search (Phase I-a)...")
best_model, best_score = nas.fit(X_train, y_train)
print(f"✓ NAS complete! Best perplexity: {best_score:.4f}")

# ============================================================
# Wrap in CerebrosNotGPT for generation
# ============================================================
print("\n🎁 Wrapping model in CerebrosNotGPT...")
generator = CerebrosNotGPT(
    tokenizer=tokenizer,
    model=best_model,
    max_sequence_length=MAX_SEQ_LENGTH,
    padding_token=tokenizer.pad_token_id or 0
)
print("✓ Generator ready")

# Quick test
print("\n📝 Testing generation...")
test_prompt = "In the beginning"
result = generator.generate(test_prompt, max_new_tokens=10)
decoded = tokenizer.decode(result, skip_special_tokens=True)
print(f"   Prompt: '{test_prompt}'")
print(f"   Output: '{decoded}'")

# ============================================================
# Save Keras model
# ============================================================
print("\n💾 Saving models...")
os.makedirs("priv/models", exist_ok=True)

TOKENIZER_PATH = f"priv/models/tokenizer-tr-{TRIAL_NUMBER}"
MODEL_PATH = f"priv/models/cerebros_model_tr_{TRIAL_NUMBER}.keras"

tokenizer.save_pretrained(TOKENIZER_PATH)
print(f"✓ Tokenizer saved to: {TOKENIZER_PATH}")

generator.save(MODEL_PATH)
print(f"✓ Keras model saved to: {MODEL_PATH}")

# ============================================================
# Convert to ONNX
# ============================================================
print("\n🔄 Converting to ONNX format...")
import tf2onnx
import onnx

# Reload the model (to get clean state)
saved_model = tf.keras.models.load_model(MODEL_PATH)

# Define input signature
input_signature = [
    tf.TensorSpec(shape=(None, MAX_SEQ_LENGTH), dtype=tf.int32, name="input_ids")
]

ONNX_PATH = MODEL_PATH.replace('.keras', '.onnx')

# Convert
model_proto, _ = tf2onnx.convert.from_keras(
    saved_model,
    input_signature=input_signature,
    opset=14,
    output_path=ONNX_PATH
)

print(f"✓ ONNX model saved to: {ONNX_PATH}")

# Verify
onnx_model = onnx.load(ONNX_PATH)
onnx.checker.check_model(onnx_model)
print("✓ ONNX model verification passed!")

# ============================================================
# Test ONNX inference
# ============================================================
print("\n🧪 Testing ONNX inference...")
import onnxruntime as ort

ort_session = ort.InferenceSession(ONNX_PATH)
input_name = ort_session.get_inputs()[0].name
output_name = ort_session.get_outputs()[0].name

# Prepare test input
test_tokens = tokenizer.encode(test_prompt, add_special_tokens=False)
if len(test_tokens) < MAX_SEQ_LENGTH:
    test_tokens = test_tokens + [tokenizer.pad_token_id or 0] * (MAX_SEQ_LENGTH - len(test_tokens))
test_input = np.array([test_tokens], dtype=np.int32)

# Run inference
onnx_output = ort_session.run([output_name], {input_name: test_input})[0]
print(f"✓ ONNX inference successful!")
print(f"   Output shape: {onnx_output.shape}")

# Show top predictions
probs = tf.nn.softmax(onnx_output[0]).numpy()
top_5 = np.argsort(probs)[-5:][::-1]
print(f"\n   Top 5 next token predictions:")
for idx in top_5:
    token = tokenizer.decode([idx])
    print(f"      {repr(token)}: {probs[idx]:.4f}")

# ============================================================
# Summary
# ============================================================
print("\n" + "=" * 60)
print("✅ Training & Export Complete!")
print("=" * 60)
print(f"\nArtifacts created:")
print(f"   📁 {TOKENIZER_PATH}/")
print(f"   📄 {MODEL_PATH}")
print(f"   📄 {ONNX_PATH}")
print("\nTo use in Elixir:")
print(f'''
  {{:ok, result}} = Thunderline.Thunderbolt.Resources.OnnxInference.infer(
    "{ONNX_PATH}",
    %{{data: [[token_ids...]]}},
    %{{}}
  )
''')
print("=" * 60)
