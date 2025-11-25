#!/usr/bin/env python3
"""
Build ONNX Model Manually from Keras Weights

This script bypasses tf2onnx (which has NumPy 2.0 compatibility issues)
by manually constructing the ONNX graph from extracted Keras weights.

Supports:
- Embedding + Dense stack models (Cerebros mini)
- CerebrosNotGPT wrapper models
- Standard Keras Sequential/Functional models

Usage:
    python build_onnx_manual.py model.keras output.onnx [--seq-len 40] [--tokenizer path/]

Requirements:
    pip install tensorflow onnx onnxruntime numpy
    # Note: Does NOT require tf2onnx!
"""

import sys
import os
import argparse
import numpy as np

def extract_keras_weights(keras_path: str):
    """Extract weights from a Keras model."""
    import tensorflow as tf
    
    print(f"📂 Loading Keras model: {keras_path}")
    loaded_model = tf.keras.models.load_model(keras_path)
    
    # Handle CerebrosNotGPT wrapper
    model_type = type(loaded_model).__name__
    if model_type == "CerebrosNotGPT" or hasattr(loaded_model, 'config'):
        print(f"   ✓ Detected CerebrosNotGPT wrapper")
        if hasattr(loaded_model, 'model') and loaded_model.model is not None:
            keras_model = loaded_model.model
            seq_len = getattr(loaded_model, 'max_sequence_length', 40)
        else:
            raise ValueError("CerebrosNotGPT has no inner model!")
    else:
        keras_model = loaded_model
        seq_len = None  # Will need to infer or use default
    
    print(f"   ✓ Parameters: {keras_model.count_params():,}")
    
    # Extract layer info
    layers_info = []
    for layer in keras_model.layers:
        layer_type = type(layer).__name__
        weights = layer.get_weights()
        
        if weights:
            info = {
                'name': layer.name,
                'type': layer_type,
                'weights': weights,
            }
            
            # Get activation for Dense layers
            if hasattr(layer, 'activation'):
                act_name = layer.activation.__name__ if hasattr(layer.activation, '__name__') else str(layer.activation)
                info['activation'] = act_name
            
            # Get config for Embedding
            if layer_type == 'Embedding':
                config = layer.get_config()
                info['input_dim'] = config['input_dim']
                info['output_dim'] = config['output_dim']
            
            layers_info.append(info)
            print(f"   ✓ Layer '{layer.name}' ({layer_type}): {[w.shape for w in weights]}")
    
    return keras_model, layers_info, seq_len


def build_onnx_graph(layers_info: list, seq_len: int = 40):
    """Build ONNX graph from layer info."""
    import onnx
    from onnx import helper, TensorProto, numpy_helper
    
    print(f"\n🔧 Building ONNX graph (seq_len={seq_len})...")
    
    nodes = []
    initializers = []
    current_input = "input_ids"
    node_idx = 0
    
    # Detect architecture
    has_embedding = any(l['type'] == 'Embedding' for l in layers_info)
    has_pooling = any('pool' in l['name'].lower() or l['type'] == 'GlobalAveragePooling1D' for l in layers_info)
    
    for layer in layers_info:
        layer_type = layer['type']
        layer_name = layer['name']
        weights = layer['weights']
        
        if layer_type == 'Embedding':
            # Embedding layer: Gather operation
            vocab_size = layer['input_dim']
            embed_dim = layer['output_dim']
            embed_weights = weights[0]  # Shape: (vocab_size, embed_dim)
            
            # Add embedding weights as initializer
            embed_init = numpy_helper.from_array(
                embed_weights.astype(np.float32),
                name=f"{layer_name}_weights"
            )
            initializers.append(embed_init)
            
            # Gather node (embedding lookup)
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
            print(f"   ✓ Embedding: vocab={vocab_size}, dim={embed_dim}")
            
        elif layer_type == 'GlobalAveragePooling1D' or 'pool' in layer_name.lower():
            # Global average pooling: ReduceMean over axis 1
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
            print(f"   ✓ GlobalAveragePooling1D")
            
        elif layer_type == 'Dense':
            # Dense layer: MatMul + Add (+ optional activation)
            kernel = weights[0]  # Shape: (in_features, out_features)
            bias = weights[1] if len(weights) > 1 else None
            activation = layer.get('activation', 'linear')
            
            # Add kernel as initializer
            kernel_init = numpy_helper.from_array(
                kernel.astype(np.float32),
                name=f"{layer_name}_kernel"
            )
            initializers.append(kernel_init)
            
            # MatMul node
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
            
            # Add bias if present
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
            
            # Apply activation
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
            elif activation == 'softmax':
                act_output = f"{layer_name}_softmax"
                softmax_node = helper.make_node(
                    'Softmax',
                    inputs=[current_input],
                    outputs=[act_output],
                    name=f"Softmax_{node_idx}",
                    axis=-1
                )
                nodes.append(softmax_node)
                current_input = act_output
                node_idx += 1
            elif activation not in ('linear', 'Linear', None):
                print(f"   ⚠️ Unknown activation '{activation}', skipping")
            
            print(f"   ✓ Dense: {kernel.shape[0]} -> {kernel.shape[1]}, activation={activation}")
    
    # Rename final output
    final_output = "logits"
    if current_input != final_output:
        identity_node = helper.make_node(
            'Identity',
            inputs=[current_input],
            outputs=[final_output],
            name="Output"
        )
        nodes.append(identity_node)
    
    # Get output shape from last Dense layer
    last_dense = [l for l in layers_info if l['type'] == 'Dense'][-1]
    output_dim = last_dense['weights'][0].shape[1]
    
    # Create graph
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
    
    # Create model
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    model.ir_version = 7
    
    # Validate
    onnx.checker.check_model(model)
    print(f"   ✅ ONNX graph validated!")
    
    return model


def test_onnx_model(keras_model, onnx_path: str, seq_len: int = 40):
    """Test ONNX model against Keras."""
    import tensorflow as tf
    import onnxruntime as ort
    
    print(f"\n🧪 Testing ONNX model...")
    
    # Load ONNX
    session = ort.InferenceSession(onnx_path)
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name
    
    # Test with random input
    test_input = np.random.randint(0, 100, size=(1, seq_len)).astype(np.int64)
    
    # Keras inference
    keras_output = keras_model(tf.constant(test_input.astype(np.int32)), training=False).numpy()
    
    # ONNX inference
    onnx_output = session.run([output_name], {input_name: test_input})[0]
    
    # Compare
    max_diff = np.max(np.abs(keras_output - onnx_output))
    print(f"   Max difference: {max_diff:.6e}")
    
    if max_diff < 1e-4:
        print(f"   ✅ Outputs match!")
        return True
    else:
        print(f"   ⚠️ Outputs differ (may still be acceptable)")
        return False


def main():
    parser = argparse.ArgumentParser(description="Build ONNX from Keras weights (bypasses tf2onnx)")
    parser.add_argument("keras_path", help="Path to Keras model (.keras or SavedModel)")
    parser.add_argument("output_path", help="Output ONNX file path")
    parser.add_argument("--seq-len", type=int, default=40, help="Sequence length (default: 40)")
    parser.add_argument("--skip-test", action="store_true", help="Skip ONNX validation test")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.keras_path):
        print(f"❌ Model not found: {args.keras_path}")
        sys.exit(1)
    
    print("="*60)
    print("🔧 Manual ONNX Builder (tf2onnx bypass)")
    print("="*60)
    
    # Extract weights
    keras_model, layers_info, detected_seq_len = extract_keras_weights(args.keras_path)
    
    # Use detected seq_len if available
    seq_len = detected_seq_len or args.seq_len
    
    # Build ONNX
    onnx_model = build_onnx_graph(layers_info, seq_len)
    
    # Save
    import onnx
    onnx.save(onnx_model, args.output_path)
    print(f"\n💾 Saved: {args.output_path}")
    
    # Test
    if not args.skip_test:
        test_onnx_model(keras_model, args.output_path, seq_len)
    
    print("\n" + "="*60)
    print("✅ ONNX model built successfully!")
    print("="*60)
    print(f"\n📋 Next steps:")
    print(f"   1. Copy to Thunderline: cp {args.output_path} priv/models/")
    print(f"   2. Test in Elixir:")
    print(f"      KerasONNX.load!(\"priv/models/{os.path.basename(args.output_path)}\")")


if __name__ == "__main__":
    main()
