#!/usr/bin/env python3
"""
Cerebros Keras → ONNX Converter

Converts trained CerebrosNotGPT .keras models to ONNX format for use with:
- Elixir/Thunderline (via Ortex/ONNX Runtime)
- Other ONNX-compatible runtimes (C++, Rust, JavaScript, etc.)

Usage:
    # Convert a single model
    python convert_keras_to_onnx.py model.keras --max-seq-length 40

    # Batch convert all .keras files in a directory
    python convert_keras_to_onnx.py ./models/ --batch

    # Specify custom output directory
    python convert_keras_to_onnx.py model.keras -o ./onnx_models/

    # With verification
    python convert_keras_to_onnx.py model.keras --verify

Requirements:
    pip install tensorflow tf2onnx onnx onnxruntime numpy
"""

import argparse
import os
import sys
import json
from pathlib import Path
from typing import Optional, Tuple, List, Dict, Any
from datetime import datetime

import numpy as np


def check_dependencies() -> bool:
    """Check if all required dependencies are installed."""
    missing = []
    
    try:
        import tensorflow as tf
    except ImportError:
        missing.append("tensorflow")
    
    try:
        import tf2onnx
    except ImportError:
        missing.append("tf2onnx")
    
    try:
        import onnx
    except ImportError:
        missing.append("onnx")
    
    try:
        import onnxruntime
    except ImportError:
        missing.append("onnxruntime")
    
    if missing:
        print(f"❌ Missing dependencies: {', '.join(missing)}")
        print(f"   Install with: pip install {' '.join(missing)}")
        return False
    
    return True


def load_keras_model(model_path: str) -> Tuple[Any, Dict[str, Any]]:
    """
    Load a Keras model and extract its configuration.
    
    Returns:
        Tuple of (model, config_dict)
    """
    import tensorflow as tf
    
    print(f"📂 Loading Keras model: {model_path}")
    
    # Load the model
    model = tf.keras.models.load_model(model_path)
    
    # Extract configuration
    config = {
        "input_shape": None,
        "output_shape": None,
        "num_parameters": model.count_params(),
    }
    
    # Get input shape from first layer
    if model.input_shape:
        config["input_shape"] = list(model.input_shape)
        # Replace None with -1 for dynamic dimensions
        config["input_shape"] = [-1 if x is None else x for x in config["input_shape"]]
    
    # Get output shape
    if model.output_shape:
        config["output_shape"] = list(model.output_shape)
        config["output_shape"] = [-1 if x is None else x for x in config["output_shape"]]
    
    print(f"   ✓ Model loaded successfully")
    print(f"   ✓ Parameters: {config['num_parameters']:,}")
    print(f"   ✓ Input shape: {config['input_shape']}")
    print(f"   ✓ Output shape: {config['output_shape']}")
    
    return model, config


def convert_to_onnx(
    model,
    output_path: str,
    max_seq_length: int = 40,
    opset: int = 14,
    input_dtype: str = "int32"
) -> str:
    """
    Convert a Keras model to ONNX format.
    
    Args:
        model: Loaded Keras model
        output_path: Path to save ONNX model
        max_seq_length: Maximum sequence length (must match training)
        opset: ONNX opset version (14 recommended for compatibility)
        input_dtype: Input data type (int32 for token IDs)
    
    Returns:
        Path to saved ONNX model
    """
    import tensorflow as tf
    import tf2onnx
    import onnx
    
    print(f"\n🔄 Converting to ONNX format...")
    print(f"   Opset version: {opset}")
    print(f"   Max sequence length: {max_seq_length}")
    print(f"   Input dtype: {input_dtype}")
    
    # Define input signature
    dtype_map = {
        "int32": tf.int32,
        "int64": tf.int64,
        "float32": tf.float32,
    }
    tf_dtype = dtype_map.get(input_dtype, tf.int32)
    
    input_signature = [
        tf.TensorSpec(
            shape=(None, max_seq_length),
            dtype=tf_dtype,
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
    
    print(f"   ✓ ONNX model saved to: {output_path}")
    
    # Verify the model
    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)
    print(f"   ✓ ONNX model verification passed!")
    
    return output_path


def verify_onnx_model(
    keras_model,
    onnx_path: str,
    max_seq_length: int = 40,
    vocabulary_size: int = 49152,
    num_tests: int = 3,
    tolerance: float = 1e-4
) -> bool:
    """
    Verify ONNX model produces equivalent outputs to Keras model.
    
    Args:
        keras_model: Original Keras model
        onnx_path: Path to ONNX model
        max_seq_length: Sequence length for test inputs
        vocabulary_size: Vocabulary size (for output shape verification)
        num_tests: Number of random test cases
        tolerance: Maximum acceptable difference
    
    Returns:
        True if verification passes
    """
    import tensorflow as tf
    import onnxruntime as ort
    
    print(f"\n🧪 Verifying ONNX model equivalence...")
    
    # Load ONNX model
    ort_session = ort.InferenceSession(onnx_path)
    input_name = ort_session.get_inputs()[0].name
    output_name = ort_session.get_outputs()[0].name
    
    all_passed = True
    
    for i in range(num_tests):
        # Generate random test input (simulating token IDs)
        test_input = np.random.randint(0, vocabulary_size, (1, max_seq_length), dtype=np.int32)
        
        # Run ONNX inference
        onnx_output = ort_session.run([output_name], {input_name: test_input})[0]
        
        # Run Keras inference
        keras_output = keras_model(tf.constant(test_input), training=False).numpy()
        
        # Compare
        max_diff = np.max(np.abs(onnx_output - keras_output))
        mean_diff = np.mean(np.abs(onnx_output - keras_output))
        
        passed = max_diff < tolerance
        status = "✓" if passed else "✗"
        
        print(f"   Test {i+1}: max_diff={max_diff:.2e}, mean_diff={mean_diff:.2e} [{status}]")
        
        if not passed:
            all_passed = False
    
    if all_passed:
        print(f"   ✅ All {num_tests} verification tests passed!")
    else:
        print(f"   ⚠️  Some tests showed differences > {tolerance}")
        print(f"      This may be acceptable for inference purposes.")
    
    return all_passed


def generate_metadata(
    keras_path: str,
    onnx_path: str,
    config: Dict[str, Any],
    max_seq_length: int,
    opset: int
) -> Dict[str, Any]:
    """Generate metadata JSON for the converted model."""
    import onnx
    
    onnx_model = onnx.load(onnx_path)
    
    metadata = {
        "source_model": os.path.basename(keras_path),
        "onnx_model": os.path.basename(onnx_path),
        "conversion_date": datetime.utcnow().isoformat() + "Z",
        "opset_version": opset,
        "ir_version": onnx_model.ir_version,
        "max_seq_length": max_seq_length,
        "input_shape": config["input_shape"],
        "output_shape": config["output_shape"],
        "num_parameters": config["num_parameters"],
        "inputs": [],
        "outputs": [],
        "thunderline_compatible": True,
        "usage": {
            "elixir": 'Thunderline.Thunderbolt.Resources.OnnxInference.infer("model.onnx", %{data: [[token_ids...]]}, %{})',
            "python": 'ort_session.run(["output"], {"input_ids": token_ids})',
        }
    }
    
    # Add input info
    for inp in onnx_model.graph.input:
        shape = [d.dim_value if d.dim_value else "batch" for d in inp.type.tensor_type.shape.dim]
        metadata["inputs"].append({
            "name": inp.name,
            "shape": shape,
            "dtype": "int32"
        })
    
    # Add output info
    for out in onnx_model.graph.output:
        shape = [d.dim_value if d.dim_value else "batch" for d in out.type.tensor_type.shape.dim]
        metadata["outputs"].append({
            "name": out.name,
            "shape": shape,
            "dtype": "float32"
        })
    
    return metadata


def convert_single_model(
    input_path: str,
    output_dir: Optional[str] = None,
    max_seq_length: int = 40,
    opset: int = 14,
    verify: bool = False,
    vocabulary_size: int = 49152
) -> Tuple[str, Dict[str, Any]]:
    """
    Convert a single Keras model to ONNX.
    
    Returns:
        Tuple of (onnx_path, metadata)
    """
    input_path = os.path.abspath(input_path)
    
    # Determine output path
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        onnx_filename = os.path.basename(input_path).replace('.keras', '.onnx')
        output_path = os.path.join(output_dir, onnx_filename)
    else:
        output_path = input_path.replace('.keras', '.onnx')
    
    # Load model
    model, config = load_keras_model(input_path)
    
    # Convert
    convert_to_onnx(
        model,
        output_path,
        max_seq_length=max_seq_length,
        opset=opset
    )
    
    # Verify if requested
    if verify:
        verify_onnx_model(
            model,
            output_path,
            max_seq_length=max_seq_length,
            vocabulary_size=vocabulary_size
        )
    
    # Generate metadata
    metadata = generate_metadata(
        input_path,
        output_path,
        config,
        max_seq_length,
        opset
    )
    
    # Save metadata
    metadata_path = output_path.replace('.onnx', '_metadata.json')
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"\n📋 Metadata saved to: {metadata_path}")
    
    return output_path, metadata


def batch_convert(
    input_dir: str,
    output_dir: Optional[str] = None,
    max_seq_length: int = 40,
    opset: int = 14,
    verify: bool = False,
    vocabulary_size: int = 49152
) -> List[Tuple[str, Dict[str, Any]]]:
    """
    Convert all .keras models in a directory.
    
    Returns:
        List of (onnx_path, metadata) tuples
    """
    input_dir = os.path.abspath(input_dir)
    keras_files = list(Path(input_dir).glob("**/*.keras"))
    
    if not keras_files:
        print(f"❌ No .keras files found in {input_dir}")
        return []
    
    print(f"🔍 Found {len(keras_files)} .keras file(s) to convert")
    
    results = []
    for i, keras_file in enumerate(keras_files, 1):
        print(f"\n{'='*60}")
        print(f"[{i}/{len(keras_files)}] Converting: {keras_file.name}")
        print(f"{'='*60}")
        
        try:
            onnx_path, metadata = convert_single_model(
                str(keras_file),
                output_dir=output_dir,
                max_seq_length=max_seq_length,
                opset=opset,
                verify=verify,
                vocabulary_size=vocabulary_size
            )
            results.append((onnx_path, metadata))
        except Exception as e:
            print(f"❌ Failed to convert {keras_file.name}: {e}")
    
    print(f"\n{'='*60}")
    print(f"✅ Successfully converted {len(results)}/{len(keras_files)} models")
    print(f"{'='*60}")
    
    return results


def main():
    parser = argparse.ArgumentParser(
        description="Convert Cerebros Keras models to ONNX format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Convert a single model
    python convert_keras_to_onnx.py model.keras --max-seq-length 40
    
    # Batch convert all .keras files in a directory
    python convert_keras_to_onnx.py ./models/ --batch
    
    # Specify custom output directory
    python convert_keras_to_onnx.py model.keras -o ./onnx_models/
    
    # With verification against original model
    python convert_keras_to_onnx.py model.keras --verify

For Thunderline/Elixir integration:
    Place the .onnx file in priv/models/ and use:
    
    {:ok, result} = Thunderline.Thunderbolt.Resources.OnnxInference.infer(
      "model.onnx",
      %{data: [[token_ids...]]},
      %{}
    )
"""
    )
    
    parser.add_argument(
        "input",
        help="Path to .keras model file or directory (with --batch)"
    )
    
    parser.add_argument(
        "-o", "--output-dir",
        help="Output directory for ONNX model(s). Default: same directory as input"
    )
    
    parser.add_argument(
        "--batch",
        action="store_true",
        help="Convert all .keras files in the input directory"
    )
    
    parser.add_argument(
        "--max-seq-length",
        type=int,
        default=40,
        help="Maximum sequence length (must match training). Default: 40"
    )
    
    parser.add_argument(
        "--opset",
        type=int,
        default=14,
        help="ONNX opset version. Default: 14"
    )
    
    parser.add_argument(
        "--vocabulary-size",
        type=int,
        default=49152,
        help="Vocabulary size (for verification). Default: 49152"
    )
    
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify ONNX model outputs match Keras model"
    )
    
    args = parser.parse_args()
    
    # Check dependencies
    if not check_dependencies():
        sys.exit(1)
    
    # Run conversion
    if args.batch:
        if not os.path.isdir(args.input):
            print(f"❌ --batch requires a directory, but {args.input} is not a directory")
            sys.exit(1)
        
        batch_convert(
            args.input,
            output_dir=args.output_dir,
            max_seq_length=args.max_seq_length,
            opset=args.opset,
            verify=args.verify,
            vocabulary_size=args.vocabulary_size
        )
    else:
        if not os.path.isfile(args.input):
            print(f"❌ File not found: {args.input}")
            sys.exit(1)
        
        if not args.input.endswith('.keras'):
            print(f"❌ Expected .keras file, got: {args.input}")
            sys.exit(1)
        
        convert_single_model(
            args.input,
            output_dir=args.output_dir,
            max_seq_length=args.max_seq_length,
            opset=args.opset,
            verify=args.verify,
            vocabulary_size=args.vocabulary_size
        )


if __name__ == "__main__":
    main()
