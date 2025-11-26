# PythonX Integration Guide

## Overview

Thunderline uses [PythonX](https://hex docs.pm/pythonx/) for seamless Elixir-Python interoperability, particularly for the Cerebros NAS bridge. This guide explains the proper patterns for encoding/decoding data between Elixir and Python.

## Key Concepts

### 1. PythonX Data Passing Mechanisms

There are two ways to pass data to Python:

#### ❌ **WRONG: Embedding JSON in Python code strings**
```elixir
# This is inefficient and error-prone
spec = %{"dataset_id" => "test"}
python_code = """
import json
spec = json.loads('#{Jason.encode!(spec)}')
"""
Pythonx.eval(python_code)
```

Problems:
- Requires JSON serialization/deserialization
- String escaping issues
- No type preservation
- Can't handle complex types (DateTime, custom structs)

#### ✅ **CORRECT: Using globals map with Pythonx.Encoder**
```elixir
# Let Pythonx handle data marshalling
spec = %{"dataset_id" => "test"}
python_code = """
# spec comes from Elixir via globals
result = process_data(spec)
"""
{result, _} = Pythonx.eval(python_code, %{"spec" => spec})
```

Benefits:
- Automatic type conversion
- Handles complex nested structures
- Preserves semantic meaning
- Extensible via protocol implementation

### 2. The Pythonx.Encoder Protocol

The `Pythonx.Encoder` protocol defines how Elixir data structures convert to Python objects.

#### Built-in Support

PythonX automatically encodes standard Elixir types:

- **Maps** → Python `dict`
- **Lists** → Python `list`  
- **Integers/Floats** → Python `int`/`float`
- **Strings** → Python `str`
- **Booleans** → Python `bool`
- **nil** → Python `None`

#### Custom Encoders

For custom structs (like our Cerebros contracts), implement the protocol:

```elixir
defimpl Pythonx.Encoder, for: MyApp.CustomStruct do
  def encode(struct, _encoder) do
    {result, %{}} = Pythonx.eval(
      """
      from datetime import datetime
      
      result = {
          'id': id_val,
          'timestamp': datetime.fromisoformat(timestamp),
          'data': data
      }
      """,
      %{
        "id_val" => struct.id,
        "timestamp" => DateTime.to_iso8601(struct.timestamp),
        "data" => struct.data
      }
    )
    
    result
  end
end
```

### 3. Data Normalization Patterns

When passing Elixir data to Python, normalize complex types:

```elixir
defp normalize_for_python(map) when is_map(map) do
  Enum.into(map, %{}, fn {k, v} -> 
    {to_string(k), normalize_for_python(v)} 
  end)
end

defp normalize_for_python(list) when is_list(list) do
  Enum.map(list, &normalize_for_python/1)
end

defp normalize_for_python(atom) when is_atom(atom) do
  # Convert atoms to strings (except true/false/nil)
  case atom do
    nil -> nil
    true -> true
    false -> false
    _ -> to_string(atom)
  end
end

defp normalize_for_python(%DateTime{} = dt) do
  DateTime.to_iso8601(dt)
end

defp normalize_for_python(value), do: value
```

## Cerebros Bridge Implementation

### Current Architecture

```
Elixir (ThunderBolt) → PythonxInvoker → cerebros_service.py → Cerebros NAS
                        ↑ proper data passing
                        ↑ Pythonx.Encoder protocol
```

### Invoker Pattern

The `PythonxInvoker` module demonstrates proper usage:

```elixir
defp call_python_run_nas(spec, opts) do
  python_code = """
  import cerebros_service
  
  # spec and opts passed from Elixir via globals
  result = cerebros_service.run_nas(spec, opts)
  result
  """

  # Pass normalized data through globals
  globals = %{
    "spec" => normalize_for_python(spec),
    "opts" => normalize_for_python(opts)
  }

  case Pythonx.eval(python_code, globals) do
    {result_obj, _} ->
      # Decode Python result back to Elixir
      {:ok, Pythonx.decode(result_obj)}
    {:error, reason} ->
      {:error, reason}
  end
end
```

### Contract Encoding

Custom Pythonx.Encoder implementations for Cerebros contracts are in:
- `lib/thunderline/thunderbolt/cerebros_bridge/python_encoder.ex`

These handle:
- DateTime conversion to ISO8601
- Atom-to-string conversion (for status fields)
- Nested struct marshalling
- Null/nil handling

## Testing Patterns

### Test Scripts

See `scripts/test_pythonx_cerebros.exs` for examples:

```elixir
# Setup Python environment
python_setup = """
import sys
sys.path.insert(0, '#{python_path}')
import my_module
"""
Pythonx.eval(python_setup, %{})

# Call with proper data passing
{result, _} = Pythonx.eval(
  """
  result = my_module.process(data)
  result
  """,
  %{"data" => %{"key" => "value"}}
)

# Decode result
decoded = Pythonx.decode(result)
```

### Testing Encoders

```elixir
test "encodes contract correctly" do
  contract = %Contracts.RunStartedV1{
    run_id: "test_123",
    timestamp: DateTime.utc_now(),
    search_space: %{"layers" => [32, 64]}
  }
  
  # Encode and verify Python object
  python_obj = Pythonx.encode!(contract)
  decoded = Pythonx.decode(python_obj)
  
  assert decoded["run_id"] == "test_123"
  assert decoded["search_space"]["layers"] == [32, 64]
end
```

## Performance Considerations

### Why PythonX Over Subprocesses?

| Aspect | Subprocess | PythonX |
|--------|-----------|---------|
| Startup overhead | High (~100ms per call) | Low (shared runtime) |
| Data marshalling | JSON encode/decode | Native type conversion |
| Error handling | Parse stderr | Structured exceptions |
| Type preservation | Limited (all strings) | Full type support |
| Memory efficiency | New process per call | Shared interpreter |

### Optimization Tips

1. **Reuse Python objects**: Keep expensive Python objects (models, datasets) in module-level scope
2. **Batch operations**: Process multiple items in one Python call rather than calling repeatedly
3. **Normalize once**: Pre-normalize Elixir data before passing to multiple Python calls
4. **Cache results**: Use PythonX objects directly without decoding if passing back to Python

## Troubleshooting

### Common Issues

#### 1. "undefined variable" errors

**Problem**: Forgot to pass data via globals
```elixir
# ❌ Wrong
Pythonx.eval("result = process(data)")

# ✅ Correct  
Pythonx.eval("result = process(data)", %{"data" => my_data})
```

#### 2. Atom encoding issues

**Problem**: Atoms aren't JSON-serializable
```elixir
# ❌ Wrong
%{"status" => :succeeded}  # Python doesn't understand atoms

# ✅ Correct
%{"status" => "succeeded"}  # Convert to string
```

#### 3. DateTime timezone issues

**Problem**: Python datetime objects need explicit timezone
```elixir
# Use ISO8601 format with timezone
DateTime.to_iso8601(datetime)
# Then in Python:
# datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
```

### Debug Patterns

```elixir
# Inspect what's being passed to Python
IO.inspect(normalize_for_python(data), label: "Python input")

# Capture Python side effects
python_code = """
import sys
print("Python received:", repr(data), file=sys.stderr)
result = process(data)
result
"""

# Check Python object before decoding
{python_obj, _} = Pythonx.eval(code, globals)
IO.inspect(python_obj, label: "Python object")
decoded = Pythonx.decode(python_obj)
IO.inspect(decoded, label: "Decoded")
```

## Best Practices

### ✅ DO

- Pass data through globals map
- Normalize atoms to strings before encoding
- Implement Pythonx.Encoder for custom structs
- Use Pythonx.decode to convert results back
- Keep Python code in separate files when complex
- Add Python path setup to application startup

### ❌ DON'T

- Embed JSON strings in Python code
- Pass atoms directly (except true/false/nil)
- Assume Python has Elixir modules available
- Parse stderr for structured errors (use exceptions)
- Create new Python interpreters per call

## References

- [PythonX Documentation](https://hexdocs.pm/pythonx/)
- [Pythonx.Encoder Protocol](https://hexdocs.pm/pythonx/Pythonx.Encoder.html)
- Cerebros Bridge: `lib/thunderline/thunderbolt/cerebros_bridge/pythonx_invoker.ex`
- Test Script: `scripts/test_pythonx_cerebros.exs`
- Contract Encoders: `lib/thunderline/thunderbolt/cerebros_bridge/python_encoder.ex`
