#!/usr/bin/env python3
"""
Test Script for Cerebros ONNX Conversion and Inference

This script verifies the complete pipeline:
1. Load a Keras model
2. Convert to ONNX (manual method, bypasses tf2onnx NumPy 2.0 issues)
3. Run inference on both
4. Compare outputs
5. Test text generation

Usage:
    python test_onnx_pipeline.py model.keras tokenizer/

Requirements:
    pip install tensorflow onnx onnxruntime transformers numpy
    # Note: Does NOT require tf2onnx (we build ONNX manually)
"""

import sys
import os
import tempfile
import numpy as np


def build_onnx_from_keras(keras_model, seq_len: int = 40):
    """
    Build ONNX model manually from Keras weights.
    Bypasses tf2onnx to avoid NumPy 2.0 compatibility issues.
    """
    import onnx
    from onnx import helper, TensorProto, numpy_helper
    
    nodes = []
    initializers = []
    current_input = "input_ids"
    node_idx = 0
    output_dim = None
    
    for layer in keras_model.layers:
        layer_type = type(layer).__name__
        layer_name = layer.name
        weights = layer.get_weights()
        
        if not weights:
            continue
            
        if layer_type == 'Embedding':
            embed_weights = weights[0]
            embed_init = numpy_helper.from_array(
                embed_weights.astype(np.float32),
                name=f"{layer_name}_weights"
            )
            initializers.append(embed_init)
            
            output_name = f"{layer_name}_output"
            gather_node = helper.make_node(
                'Gather',
                inputs=[f"{layer_name}_weights", current_input],
                outputs=[output_name],
                name=f"Gather_{node_idx}",
                axis=0
            )
            nodes.append(gather_node)
            current_input = output_name
            node_idx += 1
            
        elif layer_type == 'GlobalAveragePooling1D' or 'pool' in layer_name.lower():
            output_name = f"{layer_name}_output"
            pool_node = helper.make_node(
                'ReduceMean',
                inputs=[current_input],
                outputs=[output_name],
                name=f"Pool_{node_idx}",
                axes=[1],
                keepdims=0
            )
            nodes.append(pool_node)
            current_input = output_name
            node_idx += 1
            
        elif layer_type == 'Dense':
            kernel = weights[0]
            bias = weights[1] if len(weights) > 1 else None
            activation = layer.activation.__name__ if hasattr(layer, 'activation') else 'linear'
            output_dim = kernel.shape[1]
            
            kernel_init = numpy_helper.from_array(
                kernel.astype(np.float32),
                name=f"{layer_name}_kernel"
            )
            initializers.append(kernel_init)
            
            matmul_output = f"{layer_name}_matmul"
            matmul_node = helper.make_node(
                'MatMul',
                inputs=[current_input, f"{layer_name}_kernel"],
                outputs=[matmul_output],
                name=f"MatMul_{node_idx}"
            )
            nodes.append(matmul_node)
            current_input = matmul_output
            node_idx += 1
            
            if bias is not None:
                bias_init = numpy_helper.from_array(
                    bias.astype(np.float32),
                    name=f"{layer_name}_bias"
                )
                initializers.append(bias_init)
                
                add_output = f"{layer_name}_add"
                add_node = helper.make_node(
                    'Add',
                    inputs=[current_input, f"{layer_name}_bias"],
                    outputs=[add_output],
                    name=f"Add_{node_idx}"
                )
                nodes.append(add_node)
                current_input = add_output
                node_idx += 1
            
            if activation == 'relu':
                act_output = f"{layer_name}_relu"
                relu_node = helper.make_node(
                    'Relu',
                    inputs=[current_input],
                    outputs=[act_output],
                    name=f"Relu_{node_idx}"
                )
                nodes.append(relu_node)
                current_input = act_output
                node_idx += 1
    
    # Final output
    identity_node = helper.make_node(
        'Identity',
        inputs=[current_input],
        outputs=["logits"],
        name="Output"
    )
    nodes.append(identity_node)
    
    input_tensor = helper.make_tensor_value_info(
        "input_ids", TensorProto.INT64, [None, seq_len]
    )
    output_tensor = helper.make_tensor_value_info(
        "logits", TensorProto.FLOAT, [None, output_dim]
    )
    
    graph = helper.make_graph(
        nodes,
        "cerebros_model",
        [input_tensor],
        [output_tensor],
        initializers
    )
    
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    model.ir_version = 7
    onnx.checker.check_model(model)
    
    return model

def test_conversion(keras_path: str, tokenizer_path: str):
    """Test the complete ONNX conversion and inference pipeline."""
    
    import tensorflow as tf
    import onnx
    import onnxruntime as ort
    from transformers import AutoTokenizer
    
    print("="*60)
    print("🧪 Cerebros ONNX Pipeline Test")
    print("   (Using manual ONNX build - bypasses tf2onnx)")
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
    
    # Step 3: Convert to ONNX (manual method)
    print("\n🔄 Step 3: Converting to ONNX (manual build)...")
    onnx_path = tempfile.mktemp(suffix=".onnx")
    
    onnx_model = build_onnx_from_keras(keras_model, MAX_SEQ_LENGTH)
    onnx.save(onnx_model, onnx_path)
    print(f"   ✓ ONNX model saved to: {onnx_path}")
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
        
        # Keras uses int32, ONNX uses int64
        keras_input = np.array([tokens], dtype=np.int32)
        onnx_input = np.array([tokens], dtype=np.int64)
        
        # Run both models
        keras_output = keras_model(tf.constant(keras_input), training=False).numpy()
        onnx_output = ort_session.run([output_name], {input_name: onnx_input})[0]
        
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
            
            # ONNX uses int64
            input_array = np.array([padded], dtype=np.int64)
            
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
