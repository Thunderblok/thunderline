# ONNX Integration Status

## ✅ Working Pipeline

```
Keras Model → Manual ONNX Build → Ortex → Ash.AI OnnxInference
```

### What Works
1. **Manual ONNX building** - bypasses tf2onnx NumPy 2.0 issues
2. **KerasONNX adapter** - loads/runs via Ortex
3. **OnnxInference resource** - Ash resource for MCP tool exposure
4. **End-to-end inference** - 7ms model inference, 65ms full pipeline

### Known Issues & Workarounds

| Issue | Status | Workaround |
|-------|--------|------------|
| CUDA 12.0 (RTX 5080) | ⚠️ | Use `CUDA_VISIBLE_DEVICES=""` for CPU |
| tf2onnx + NumPy 2.0 | ✅ Bypassed | Manual ONNX build via `onnx` package |
| Positional encoding extra input | ✅ Avoided | Manual build embeds weights |

### Files

**Python Tools:**
- `scripts/build_onnx_from_weights.py` - Train + build ONNX from scratch
- `scripts/cerebros_onnx_tools/build_onnx_manual.py` - Convert existing Keras to ONNX
- `scripts/cerebros_onnx_tools/test_onnx_pipeline.py` - Full pipeline test

**Elixir Modules:**
- `lib/thunderline/thunderbolt/ml/keras_onnx.ex` - Ortex-based ONNX adapter
- `lib/thunderline/thunderbolt/resources/onnx_inference.ex` - Ash resource

**Models:**
- `priv/models/cerebros_trained.onnx` - 217K params, vocab=1000, seq_len=40
- `priv/models/cerebros_manual.onnx` - 51K params, vocab=100 (test model)

### Usage

**Elixir:**
```elixir
# Direct
{:ok, session} = KerasONNX.load!("priv/models/cerebros_trained.onnx")
input = %Input{tensor: Nx.tensor([[1,2,3,...]], type: :s64), ...}
{:ok, output} = KerasONNX.infer(session, input)

# Via Ash resource
{:ok, result} = OnnxInference.infer("priv/models/cerebros_trained.onnx", %{data: tokens}, %{})
```

**Python (convert new model):**
```bash
python scripts/cerebros_onnx_tools/build_onnx_manual.py model.keras output.onnx
```

### Architecture Notes

The manual ONNX builder supports:
- Embedding layers → Gather op
- Dense layers → MatMul + Add + optional ReLU
- GlobalAveragePooling1D → ReduceMean

For more complex architectures (attention, etc.), extend `build_onnx_from_keras()`.
