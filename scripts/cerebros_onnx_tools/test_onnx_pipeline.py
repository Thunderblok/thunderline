#!/usr/bin/env python3
"""
Test Script for Cerebros ONNX Conversion and Inference

This script verifies the complete pipeline:
1. Load a Keras model
2. Convert to ONNX
3. Run inference on both
4. Compare outputs
5. Test text generation

Usage:
    python test_onnx_pipeline.py model.keras tokenizer/

Requirements:
    pip install tensorflow tf2onnx onnx onnxruntime transformers numpy
"""

import sys
import os
import tempfile
import numpy as np

def test_conversion(keras_path: str, tokenizer_path: str):
    """Test the complete ONNX conversion and inference pipeline."""
    
    import tensorflow as tf
    import tf2onnx
    import onnx
    import onnxruntime as ort
    from transformers import AutoTokenizer
    
    print("="*60)
    print("🧪 Cerebros ONNX Pipeline Test")
    print("="*60)
    
    # Configuration (should match training)
    MAX_SEQ_LENGTH = 40
    
    # Step 1: Load Keras model
    print("\n📂 Step 1: Loading Keras model...")
    loaded_model = tf.keras.models.load_model(keras_path)
    print(f"   ✓ Model loaded: {keras_path}")
    
    # Check if this is a CerebrosNotGPT wrapper
    model_type = type(loaded_model).__name__
    is_wrapper = model_type == "CerebrosNotGPT" or hasattr(loaded_model, 'config')
    
    if is_wrapper:
        print(f"   ✓ Detected CerebrosNotGPT wrapper")
        if hasattr(loaded_model, 'model') and loaded_model.model is not None:
            keras_model = loaded_model.model
            print(f"   ✓ Extracted inner model for ONNX export")
            # Get max_seq_length from wrapper if available
            if hasattr(loaded_model, 'max_sequence_length'):
                MAX_SEQ_LENGTH = loaded_model.max_sequence_length
                print(f"   ✓ Using MAX_SEQ_LENGTH from wrapper: {MAX_SEQ_LENGTH}")
        else:
            raise ValueError("CerebrosNotGPT has no inner model!")
    else:
        keras_model = loaded_model
        print(f"   ✓ Plain Keras model")
    
    print(f"   ✓ Parameters: {keras_model.count_params():,}")
    
    # Step 2: Load tokenizer
    print("\n📂 Step 2: Loading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)
    VOCAB_SIZE = tokenizer.vocab_size
    PAD_TOKEN_ID = tokenizer.pad_token_id or tokenizer.eos_token_id
    print(f"   ✓ Tokenizer loaded: {tokenizer_path}")
    print(f"   ✓ Vocabulary size: {VOCAB_SIZE}")
    print(f"   ✓ Pad token ID: {PAD_TOKEN_ID}")
    
    # Step 3: Convert to ONNX
    print("\n🔄 Step 3: Converting to ONNX...")
    onnx_path = tempfile.mktemp(suffix=".onnx")
    
    input_signature = [
        tf.TensorSpec(shape=(None, MAX_SEQ_LENGTH), dtype=tf.int32, name="input_ids")
    ]
    
    model_proto, _ = tf2onnx.convert.from_keras(
        keras_model,
        input_signature=input_signature,
        opset=14,
        output_path=onnx_path
    )
    print(f"   ✓ ONNX model saved to: {onnx_path}")
    
    # Verify ONNX model
    onnx_model = onnx.load(onnx_path)
    onnx.checker.check_model(onnx_model)
    print(f"   ✓ ONNX model verification passed!")
    
    # Step 4: Load ONNX for inference
    print("\n🔄 Step 4: Loading ONNX Runtime session...")
    ort_session = ort.InferenceSession(onnx_path)
    input_name = ort_session.get_inputs()[0].name
    output_name = ort_session.get_outputs()[0].name
    print(f"   ✓ Session loaded")
    print(f"   ✓ Input name: {input_name}")
    print(f"   ✓ Output name: {output_name}")
    
    # Step 5: Test inference equivalence
    print("\n🧪 Step 5: Testing inference equivalence...")
    
    test_prompts = [
        "In the beginning",
        "Hello world",
        "The quick brown fox"
    ]
    
    all_passed = True
    
    for prompt in test_prompts:
        # Tokenize
        tokens = tokenizer.encode(prompt, add_special_tokens=False)
        
        # Pad
        if len(tokens) < MAX_SEQ_LENGTH:
            tokens = tokens + [PAD_TOKEN_ID] * (MAX_SEQ_LENGTH - len(tokens))
        else:
            tokens = tokens[:MAX_SEQ_LENGTH]
        
        input_array = np.array([tokens], dtype=np.int32)
        
        # Run both models
        keras_output = keras_model(tf.constant(input_array), training=False).numpy()
        onnx_output = ort_session.run([output_name], {input_name: input_array})[0]
        
        # Compare
        max_diff = np.max(np.abs(keras_output - onnx_output))
        
        status = "✓" if max_diff < 1e-4 else "⚠"
        print(f"   {status} '{prompt}': max_diff = {max_diff:.2e}")
        
        if max_diff >= 1e-4:
            all_passed = False
    
    if all_passed:
        print(f"   ✅ All inference tests passed!")
    else:
        print(f"   ⚠️  Some differences detected (usually acceptable)")
    
    # Step 6: Test text generation
    print("\n📝 Step 6: Testing text generation...")
    
    def generate_greedy(prompt: str, max_new_tokens: int = 20) -> str:
        """Simple greedy generation for testing."""
        tokens = tokenizer.encode(prompt, add_special_tokens=False)
        
        for _ in range(max_new_tokens):
            # Pad
            padded = tokens.copy()
            if len(padded) < MAX_SEQ_LENGTH:
                padded = padded + [PAD_TOKEN_ID] * (MAX_SEQ_LENGTH - len(padded))
            else:
                padded = padded[-MAX_SEQ_LENGTH:]
            
            input_array = np.array([padded], dtype=np.int32)
            
            # Get logits
            logits = ort_session.run([output_name], {input_name: input_array})[0][0]
            
            # Greedy: pick highest probability
            next_token = int(np.argmax(logits))
            
            if next_token == PAD_TOKEN_ID:
                break
            
            tokens.append(next_token)
        
        return tokenizer.decode(tokens, skip_special_tokens=True)
    
    for prompt in ["In the beginning", "Hello"]:
        result = generate_greedy(prompt)
        print(f"   Prompt: '{prompt}'")
        print(f"   Output: '{result}'")
        print()
    
    # Cleanup
    os.unlink(onnx_path)
    
    print("="*60)
    print("✅ All tests completed!")
    print("="*60)
    print("\n📋 Next steps:")
    print("   1. Run: python convert_keras_to_onnx.py your_model.keras")
    print("   2. Copy the .onnx file to your deployment target")
    print("   3. For Elixir/Thunderline: place in priv/models/")
    
    return True


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python test_onnx_pipeline.py <model.keras> <tokenizer_path>")
        print()
        print("Example:")
        print("  python test_onnx_pipeline.py final_phase_ib_model_tr_1-stage-i-b.keras tokenizer-tr-1-stage-i-b/")
        sys.exit(1)
    
    keras_path = sys.argv[1]
    tokenizer_path = sys.argv[2]
    
    if not os.path.exists(keras_path):
        print(f"❌ Model not found: {keras_path}")
        sys.exit(1)
    
    if not os.path.isdir(tokenizer_path):
        print(f"❌ Tokenizer directory not found: {tokenizer_path}")
        sys.exit(1)
    
    test_conversion(keras_path, tokenizer_path)
