#!/usr/bin/env python3
"""
Generate a simple demo ONNX model for testing the KerasONNX adapter.

This creates a minimal 2-class classifier that takes 3 features as input
and outputs 2 class probabilities.
"""

import torch
import torch.nn as nn
import torch.onnx
import os


class DemoClassifier(nn.Module):
    """Simple 2-layer neural network classifier."""

    def __init__(self, input_size=3, hidden_size=8, output_size=2):
        super().__init__()
        self.fc1 = nn.Linear(input_size, hidden_size)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(hidden_size, output_size)
        self.softmax = nn.Softmax(dim=1)

    def forward(self, x):
        x = self.fc1(x)
        x = self.relu(x)
        x = self.fc2(x)
        x = self.softmax(x)
        return x


def main():
    # Create model instance
    model = DemoClassifier()
    model.eval()

    # Create dummy input for export (batch_size=1, features=3)
    dummy_input = torch.randn(1, 3)

    # Set output path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "demo.onnx")

    # Export to ONNX
    print(f"Exporting model to {output_path}")
    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=11,
        do_constant_folding=True,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={
            "input": {0: "batch_size"},
            "output": {0: "batch_size"},
        },
    )

    print("Model exported successfully!")
    print(f"Input shape: (batch_size, 3)")
    print(f"Output shape: (batch_size, 2)")

    # Verify the exported model
    import onnx

    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)
    print("ONNX model validated successfully!")

    # Test inference with ONNX Runtime
    try:
        import onnxruntime as ort

        session = ort.InferenceSession(output_path)
        test_input = dummy_input.numpy()
        result = session.run(None, {"input": test_input})

        print(f"\nTest inference:")
        print(f"Input: {test_input}")
        print(f"Output: {result[0]}")
        print(f"Sum of probabilities: {result[0].sum()}")

    except ImportError:
        print("\nonnxruntime not installed, skipping inference test")


if __name__ == "__main__":
    main()
