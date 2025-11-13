# Test Models

This directory contains ONNX models used for testing the ML pipeline.

## Demo Model

**File**: `demo.onnx`
**Purpose**: Simple 2-class classifier for unit tests
**Input**: `(batch_size, 3)` - 3 numerical features
**Output**: `(batch_size, 2)` - 2 class probabilities (softmax)

### Generating the Model

The demo model is generated using PyTorch. To regenerate:

```bash
# Ensure you're in the Python virtual environment
cd /home/mo/DEV/Thunderline
source .venv/bin/activate

# Install dependencies
pip install torch onnx onnxruntime

# Generate model
python test/fixtures/models/generate_demo_model.py
```

### Model Architecture

```
Input (3 features)
    ↓
Linear (3 → 8)
    ↓
ReLU
    ↓
Linear (8 → 2)
    ↓
Softmax
    ↓
Output (2 class probabilities)
```

### Usage in Tests

```elixir
# Load model
{:ok, session} = KerasONNX.load!("test/fixtures/models/demo.onnx")

# Prepare input
input = Input.new!(%{data: Nx.tensor([[1.0, 2.0, 3.0]])}, :tabular, %{})

# Run inference
{:ok, output} = KerasONNX.infer(session, input)

# Cleanup
:ok = KerasONNX.close(session)
```

### Model Properties

- **Opset Version**: 11
- **Execution Providers**: CPUExecutionProvider
- **Input Type**: float32
- **Output Type**: float32
- **File Size**: ~2KB
- **Parameters**: ~50 weights + biases

### Validation

The model is validated using:
1. ONNX checker (shape inference, type checking)
2. ONNX Runtime (inference test)
3. PyTorch export verification

### Notes

- This is a toy model for testing only
- Not trained on real data (random weights)
- Output probabilities will be meaningless
- Used to verify ONNX loading, inference, and output formatting
