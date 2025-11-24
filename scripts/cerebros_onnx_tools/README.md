# Cerebros ONNX Tools

Tools for converting CerebrosNotGPT Keras models to ONNX format and running inference.

## Installation

```bash
pip install tensorflow tf2onnx onnx onnxruntime numpy transformers
```

## Tools

### 1. Convert Keras to ONNX

Converts `.keras` models to `.onnx` format for cross-platform deployment.

```bash
# Convert a single model
python convert_keras_to_onnx.py final_phase_ib_model_tr_1-stage-i-b.keras

# With verification against original model
python convert_keras_to_onnx.py model.keras --verify

# Batch convert all .keras files in a directory
python convert_keras_to_onnx.py ./models/ --batch

# Custom output directory
python convert_keras_to_onnx.py model.keras -o ./onnx_models/

# With custom sequence length (must match training)
python convert_keras_to_onnx.py model.keras --max-seq-length 40
```

**Output files:**
- `model.onnx` - The converted ONNX model
- `model_metadata.json` - Model metadata including shapes and usage examples

### 2. ONNX Inference

Run text generation using the converted ONNX model.

```bash
# Interactive mode
python onnx_inference.py model.onnx tokenizer/ --interactive

# Single prompt
python onnx_inference.py model.onnx tokenizer/ --prompt "In the beginning"

# With custom sampling parameters
python onnx_inference.py model.onnx tokenizer/ --prompt "Hello" \
    --temperature 0.7 \
    --top-k 50 \
    --top-p 0.95 \
    --max-tokens 100

# Greedy decoding (deterministic)
python onnx_inference.py model.onnx tokenizer/ --prompt "Test" --greedy
```

## Integration with Thunderline/Elixir

Once you have the ONNX model, use it in Elixir:

### Direct API Call

```elixir
# Via OnnxInference Ash resource
{:ok, result} = Thunderline.Thunderbolt.Resources.OnnxInference.infer(
  "priv/models/cerebros_model.onnx",
  %{data: [[token_ids...]]},  # Padded to max_seq_length (40)
  %{max_seq_length: 40, vocabulary_size: 49152}
)

# result.predictions contains logits of shape (1, vocabulary_size)
# Apply softmax and sampling for next token
```

### MCP Tool (for AI assistants)

```json
{
  "tool": "onnx_infer",
  "parameters": {
    "model_path": "priv/models/cerebros_model.onnx",
    "input": {"data": [[1, 2, 3, ...]]},
    "metadata": {"max_seq_length": 40}
  }
}
```

### Full Text Generation in Elixir

```elixir
defmodule MyApp.CerebrosGenerator do
  @max_seq_length 40
  @vocab_size 49152
  @pad_token_id 0  # From tokenizer config
  
  def generate(model_path, tokenizer, prompt, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, 50)
    temperature = Keyword.get(opts, :temperature, 0.7)
    
    # Tokenize prompt (use your tokenizer adapter)
    token_ids = tokenize(tokenizer, prompt)
    
    # Generate tokens one at a time
    Enum.reduce_while(1..max_tokens, token_ids, fn _, acc ->
      # Pad to max_seq_length
      padded = pad_tokens(acc, @max_seq_length, @pad_token_id)
      
      # Run inference
      {:ok, result} = Thunderline.Thunderbolt.Resources.OnnxInference.infer(
        model_path,
        %{data: [padded]},
        %{}
      )
      
      # Get logits and sample next token
      logits = result.predictions |> List.first()
      next_token = sample_token(logits, temperature)
      
      if next_token == @pad_token_id do
        {:halt, acc}
      else
        {:cont, acc ++ [next_token]}
      end
    end)
    |> decode(tokenizer)
  end
  
  defp pad_tokens(tokens, max_len, pad_id) do
    len = length(tokens)
    if len >= max_len do
      Enum.take(tokens, -max_len)
    else
      tokens ++ List.duplicate(pad_id, max_len - len)
    end
  end
  
  defp sample_token(logits, temperature) do
    # Apply temperature
    scaled = Enum.map(logits, &(&1 / temperature))
    
    # Softmax
    max_val = Enum.max(scaled)
    exp_vals = Enum.map(scaled, &:math.exp(&1 - max_val))
    sum_exp = Enum.sum(exp_vals)
    probs = Enum.map(exp_vals, &(&1 / sum_exp))
    
    # Sample (simplified - for production use proper sampling)
    probs
    |> Enum.with_index()
    |> Enum.max_by(fn {prob, _} -> prob end)
    |> elem(1)
  end
end
```

## Model Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_seq_length` | 40 | Maximum token sequence length |
| `vocabulary_size` | 49152 | Tokenizer vocabulary size |
| `opset` | 14 | ONNX opset version |

**Important**: These values must match your training configuration!

## Troubleshooting

### "Input shape mismatch"
- Ensure `--max-seq-length` matches the value used during training
- Check that input is padded to exactly `max_seq_length` tokens

### "Model not loading"
- Verify TensorFlow and tf2onnx versions are compatible
- Try different opset versions (13-17 are commonly supported)

### "Outputs don't match Keras model"
- Small numerical differences (< 1e-4) are normal due to floating point
- Run with `--verify` to compare outputs

## Files

```
cerebros_onnx_tools/
├── README.md                    # This file
├── convert_keras_to_onnx.py     # Keras → ONNX converter
├── onnx_inference.py            # ONNX inference service
└── requirements.txt             # Python dependencies
```
