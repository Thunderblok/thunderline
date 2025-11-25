"""
ONNX Export Utilities for Cerebros Models

This module provides functions to export CerebrosNotGPT models to ONNX format
for cross-platform deployment and inference.

Usage:
    from cerebrosllmutils.onnx_export import export_to_onnx, verify_onnx_export
    
    # After training
    generator = CerebrosNotGPT(config, model=best_model)
    
    # Export to ONNX
    onnx_path = export_to_onnx(
        generator, 
        "model.onnx",
        max_seq_length=40
    )
    
    # Verify export
    verify_onnx_export(generator, onnx_path, tokenizer)

Requirements:
    pip install tf2onnx onnx onnxruntime
"""

import json
import os
from typing import Any, Dict, Optional, Tuple
from datetime import datetime


def export_to_onnx(
    generator: Any,
    output_path: str,
    max_seq_length: int = 40,
    opset: int = 14,
    verify: bool = True,
    tokenizer: Optional[Any] = None
) -> str:
    """
    Export a CerebrosNotGPT model to ONNX format.
    
    Args:
        generator: CerebrosNotGPT instance (or the inner Keras model)
        output_path: Path to save the ONNX model
        max_seq_length: Maximum sequence length (must match training)
        opset: ONNX opset version (14 recommended)
        verify: If True, verify the exported model
        tokenizer: Optional tokenizer for verification tests
    
    Returns:
        Path to the saved ONNX model
    
    Example:
        >>> from cerebrosllmutils.onnx_export import export_to_onnx
        >>> onnx_path = export_to_onnx(generator, "model.onnx", max_seq_length=40)
        >>> print(f"Model exported to {onnx_path}")
    """
    import tensorflow as tf
    import tf2onnx
    import onnx
    
    # Extract the inner model if this is a CerebrosNotGPT wrapper
    if hasattr(generator, 'model') and generator.model is not None:
        model = generator.model
        print("✓ Extracted inner model from CerebrosNotGPT wrapper")
        
        # Get max_seq_length from wrapper config if available
        if hasattr(generator, 'max_sequence_length'):
            max_seq_length = generator.max_sequence_length
            print(f"✓ Using max_sequence_length from config: {max_seq_length}")
    else:
        model = generator
        print("✓ Using model directly")
    
    print(f"🔄 Converting to ONNX format...")
    print(f"   Max sequence length: {max_seq_length}")
    print(f"   Opset version: {opset}")
    print(f"   Parameters: {model.count_params():,}")
    
    # Define input signature
    input_signature = [
        tf.TensorSpec(
            shape=(None, max_seq_length),
            dtype=tf.int32,
            name="input_ids"
        )
    ]
    
    # Convert to ONNX
    model_proto, _ = tf2onnx.convert.from_keras(
        model,
        input_signature=input_signature,
        opset=opset,
        output_path=output_path
    )
    
    print(f"✓ ONNX model saved to: {output_path}")
    
    # Verify the model structure
    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)
    print("✓ ONNX model verification passed!")
    
    # Print model info
    print(f"\n📊 ONNX Model Info:")
    print(f"   IR Version: {onnx_model.ir_version}")
    print(f"   Opset Version: {onnx_model.opset_import[0].version}")
    
    for inp in onnx_model.graph.input:
        shape = [d.dim_value if d.dim_value else 'batch' for d in inp.type.tensor_type.shape.dim]
        print(f"   Input '{inp.name}': {shape}")
    
    for out in onnx_model.graph.output:
        shape = [d.dim_value if d.dim_value else 'batch' for d in out.type.tensor_type.shape.dim]
        print(f"   Output '{out.name}': {shape}")
    
    # Generate metadata
    metadata_path = output_path.replace('.onnx', '_metadata.json')
    metadata = _generate_metadata(model, output_path, max_seq_length, opset)
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"✓ Metadata saved to: {metadata_path}")
    
    # Optional verification
    if verify and tokenizer is not None:
        print("\n🧪 Running verification tests...")
        verify_onnx_export(generator, output_path, tokenizer, max_seq_length)
    
    return output_path


def verify_onnx_export(
    generator: Any,
    onnx_path: str,
    tokenizer: Any,
    max_seq_length: int = 40,
    tolerance: float = 1e-4
) -> bool:
    """
    Verify that ONNX model produces equivalent outputs to the original.
    
    Args:
        generator: Original CerebrosNotGPT or Keras model
        onnx_path: Path to ONNX model
        tokenizer: HuggingFace tokenizer
        max_seq_length: Sequence length for tests
        tolerance: Maximum acceptable difference
    
    Returns:
        True if verification passes
    """
    import tensorflow as tf
    import onnxruntime as ort
    import numpy as np
    
    # Get the inference model
    if hasattr(generator, 'model') and generator.model is not None:
        keras_model = generator.model
    else:
        keras_model = generator
    
    # Load ONNX model
    ort_session = ort.InferenceSession(onnx_path)
    input_name = ort_session.get_inputs()[0].name
    output_name = ort_session.get_outputs()[0].name
    
    pad_token_id = tokenizer.pad_token_id or tokenizer.eos_token_id
    
    test_prompts = [
        "In the beginning",
        "Hello world",
        "The quick brown"
    ]
    
    all_passed = True
    
    for prompt in test_prompts:
        # Tokenize and pad
        tokens = tokenizer.encode(prompt, add_special_tokens=False)
        if len(tokens) < max_seq_length:
            tokens = tokens + [pad_token_id] * (max_seq_length - len(tokens))
        else:
            tokens = tokens[:max_seq_length]
        
        input_array = np.array([tokens], dtype=np.int32)
        
        # Run both models
        keras_output = keras_model(tf.constant(input_array), training=False).numpy()
        onnx_output = ort_session.run([output_name], {input_name: input_array})[0]
        
        # Compare
        max_diff = np.max(np.abs(keras_output - onnx_output))
        passed = max_diff < tolerance
        
        status = "✓" if passed else "⚠"
        print(f"   {status} '{prompt}': max_diff = {max_diff:.2e}")
        
        if not passed:
            all_passed = False
    
    if all_passed:
        print("✅ All verification tests passed!")
    else:
        print("⚠️  Some differences detected (may still be acceptable)")
    
    return all_passed


def _generate_metadata(
    model: Any,
    onnx_path: str,
    max_seq_length: int,
    opset: int
) -> Dict[str, Any]:
    """Generate metadata for the exported model."""
    import onnx
    
    onnx_model = onnx.load(onnx_path)
    
    metadata = {
        "export_date": datetime.utcnow().isoformat() + "Z",
        "onnx_file": os.path.basename(onnx_path),
        "opset_version": opset,
        "ir_version": onnx_model.ir_version,
        "max_seq_length": max_seq_length,
        "num_parameters": model.count_params(),
        "architecture": "CerebrosNotGPT",
        "description": "Single-head LLM for next-token prediction",
        "inputs": [],
        "outputs": [],
        "usage_notes": [
            "Model outputs probabilities (softmax) over vocabulary",
            "Input: token IDs padded to max_seq_length",
            "For text generation, use autoregressive loop with sampling",
            "See cerebrosllmutils/onnx_inference.py for full generation example"
        ]
    }
    
    for inp in onnx_model.graph.input:
        shape = [d.dim_value if d.dim_value else "dynamic" for d in inp.type.tensor_type.shape.dim]
        metadata["inputs"].append({
            "name": inp.name,
            "shape": shape,
            "dtype": "int32",
            "description": "Token IDs (padded to max_seq_length)"
        })
    
    for out in onnx_model.graph.output:
        shape = [d.dim_value if d.dim_value else "dynamic" for d in out.type.tensor_type.shape.dim]
        metadata["outputs"].append({
            "name": out.name,
            "shape": shape,
            "dtype": "float32",
            "description": "Next-token probabilities over vocabulary"
        })
    
    return metadata


# Convenience function for use in notebooks
def quick_export(generator, tokenizer, output_dir: str = ".", trial_number: int = 1):
    """
    Quick export function for use at the end of training notebooks.
    
    Args:
        generator: Trained CerebrosNotGPT model
        tokenizer: HuggingFace tokenizer
        output_dir: Directory to save outputs
        trial_number: Trial number for filename
    
    Returns:
        Tuple of (onnx_path, metadata_path)
    
    Example:
        >>> # At the end of your training notebook:
        >>> from cerebrosllmutils.onnx_export import quick_export
        >>> onnx_path, meta_path = quick_export(generator, tokenizer, trial_number=1)
    """
    import os
    
    max_seq_length = getattr(generator, 'max_sequence_length', 40)
    
    onnx_filename = f"cerebros_model_tr_{trial_number}.onnx"
    onnx_path = os.path.join(output_dir, onnx_filename)
    
    export_to_onnx(
        generator,
        onnx_path,
        max_seq_length=max_seq_length,
        verify=True,
        tokenizer=tokenizer
    )
    
    metadata_path = onnx_path.replace('.onnx', '_metadata.json')
    
    print(f"\n📦 Export complete!")
    print(f"   ONNX model: {onnx_path}")
    print(f"   Metadata: {metadata_path}")
    print(f"\n💡 To use in Python:")
    print(f"   from cerebrosllmutils.onnx_inference import OnnxGenerator")
    print(f"   gen = OnnxGenerator('{onnx_filename}', 'tokenizer-tr-{trial_number}-stage-i-b')")
    print(f"   result = gen.generate('Hello world')")
    
    return onnx_path, metadata_path
