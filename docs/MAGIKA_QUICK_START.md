# Magika Integration Quick Start

## Overview

Thunderline integrates [Google Magika](https://github.com/google/magika), an AI-powered file type detection tool, to classify uploaded content with high accuracy. This guide covers installation, configuration, and usage of the Magika wrapper.

## What is Magika?

Magika is a deep learning model that identifies file types with greater accuracy than traditional methods. It:

- Uses a custom neural network trained on millions of files
- Provides confidence scores for classifications
- Supports 100+ content types including documents, images, code, archives
- Runs as a CLI tool with JSON output

Thunderline wraps Magika in an Elixir module that integrates with the event-driven ML pipeline.

## Installation

### Option 1: pip (Recommended)

```bash
# Install via pip
pip install magika

# Verify installation
magika --version
```

### Option 2: Binary Release

Download pre-built binaries from [Magika releases](https://github.com/google/magika/releases):

```bash
# Example for Linux
wget https://github.com/google/magika/releases/download/v0.5.0/magika-linux-x64
chmod +x magika-linux-x64
sudo mv magika-linux-x64 /usr/local/bin/magika
```

### Option 3: Docker (for development)

```bash
# Already configured in Thunderline Dockerfile
# See: Dockerfile line 45-50
```

## Configuration

Magika behavior is configured in `config/runtime.exs`:

```elixir
config :thunderline, Thunderline.Thundergate.Magika,
  # CLI path (override with MAGIKA_CLI_PATH env var)
  cli_path: System.get_env("MAGIKA_CLI_PATH", "magika"),
  
  # Confidence threshold (0.0-1.0, default 0.85)
  confidence_threshold: String.to_float(
    System.get_env("MAGIKA_CONFIDENCE_THRESHOLD", "0.85")
  ),
  
  # Timeout in milliseconds (default 5000)
  timeout: String.to_integer(
    System.get_env("MAGIKA_TIMEOUT_MS", "5000")
  )
```

### Environment Variables

- **MAGIKA_CLI_PATH**: Path to magika executable (default: `"magika"`)
- **MAGIKA_CONFIDENCE_THRESHOLD**: Minimum confidence for accepting result (default: `0.85`)
- **MAGIKA_TIMEOUT_MS**: CLI execution timeout in milliseconds (default: `5000`)

### Classifier Consumer Configuration

```elixir
config :thunderline, Thunderline.Thunderflow.Consumers.Classifier,
  batch_size: String.to_integer(System.get_env("CLASSIFIER_BATCH_SIZE", "10")),
  batch_timeout: String.to_integer(System.get_env("CLASSIFIER_BATCH_TIMEOUT_MS", "1000")),
  concurrency: String.to_integer(System.get_env("CLASSIFIER_CONCURRENCY", "4"))
```

## API Reference

### Thunderline.Thundergate.Magika

#### classify_file/2

Classifies a file at the given path.

```elixir
alias Thunderline.Thundergate.Magika

{:ok, result} = Magika.classify_file("/path/to/document.pdf")

# Result structure:
%{
  content_type: "application/pdf",
  label: "pdf",
  confidence: 0.99,
  filename: "document.pdf",
  sha256: "abc123...",
  fallback?: false
}
```

**Parameters:**

- `path` (string, required) - Absolute path to file
- `opts` (keyword, optional) - Options:
  - `:emit_event?` (boolean) - Emit `system.ingest.classified` event (default: `true`)
  - `:correlation_id` (string) - Correlation ID for event tracing
  - `:causation_id` (string) - Causation ID (ID of triggering event)

**Returns:**

- `{:ok, result}` - Successfully classified
- `{:error, {:file_not_found, path}}` - File does not exist
- `{:error, {:cli_failed, exit_code, stderr}}` - Magika CLI failed
- `{:error, {:json_decode_error, _}}` - Invalid JSON response

**Example with correlation:**

```elixir
{:ok, result} = Magika.classify_file(
  "/uploads/report.xlsx",
  correlation_id: "550e8400-e29b-41d4-a716-446655440000",
  causation_id: "parent-event-id"
)
```

#### classify_bytes/3

Classifies raw bytes by writing to a temporary file.

```elixir
{:ok, result} = Magika.classify_bytes(
  pdf_bytes,
  "document.pdf",
  correlation_id: correlation_id
)
```

**Parameters:**

- `bytes` (binary, required) - File content
- `filename` (string, required) - Original filename (preserves extension for fallback)
- `opts` (keyword, optional) - Same as `classify_file/2`

**Returns:** Same as `classify_file/2`

**Note:** Temporary file is automatically cleaned up after classification.

### Fallback Behavior

When Magika returns low confidence (< threshold) or the CLI fails, the wrapper automatically falls back to extension-based detection:

```elixir
{:ok, result} = Magika.classify_file("unknown.xyz")

# Result with fallback:
%{
  content_type: "application/octet-stream",
  label: "generic",
  confidence: 0.0,
  filename: "unknown.xyz",
  sha256: "...",
  fallback?: true  # Indicates extension-based detection
}
```

**Supported extensions** (30+ types):

| Extension | MIME Type |
|-----------|-----------|
| .pdf | application/pdf |
| .docx | application/vnd.openxmlformats-officedocument.wordprocessingml.document |
| .xlsx | application/vnd.openxmlformats-officedocument.spreadsheetml.sheet |
| .pptx | application/vnd.openxmlformats-officedocument.presentationml.presentation |
| .jpg, .jpeg | image/jpeg |
| .png | image/png |
| .gif | image/gif |
| .mp4 | video/mp4 |
| .mp3 | audio/mpeg |
| .zip | application/zip |
| .tar.gz | application/gzip |
| .json | application/json |
| .xml | application/xml |
| .html | text/html |
| .css | text/css |
| .js | application/javascript |
| .py | text/x-python |
| .rb | text/x-ruby |
| .go | text/x-go |
| .rs | text/x-rust |
| .c, .h | text/x-c |
| .cpp | text/x-c++ |
| .java | text/x-java |
| .ex, .exs | text/x-elixir |
| .sql | application/sql |
| .md | text/markdown |
| .txt | text/plain |
| *(unknown)* | application/octet-stream |

## Event Flow

### Input Event: `ui.command.ingest.received`

Triggered by file upload in LiveView:

```elixir
%Event{
  type: "ui.command.ingest.received",
  source: "thundergate.uploader",
  data: %{
    path: "/tmp/uploads/abc123.pdf",  # or bytes: <<binary>>
    filename: "document.pdf"
  },
  metadata: %{
    correlation_id: "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

### Output Event: `system.ingest.classified`

Emitted after successful classification:

```elixir
%Event{
  type: "system.ingest.classified",
  source: "thundergate.magika",
  data: %{
    content_type: "application/pdf",
    label: "pdf",
    confidence: 0.99,
    filename: "document.pdf",
    sha256: "abc123...",
    fallback?: false
  },
  metadata: %{
    correlation_id: "550e8400-e29b-41d4-a716-446655440000",  # Inherited
    causation_id: "parent-event-id",  # ID of ingestion event
    processor: Thunderline.Thundergate.Magika
  }
}
```

### DLQ Event: `system.dlq.classification_failed`

Emitted when classification fails:

```elixir
%Event{
  type: "system.dlq.classification_failed",
  source: "thunderflow.classifier",
  data: %{
    error: "File not found: /path/to/missing.pdf",
    event_id: "failed-event-id",
    retry_count: 0
  },
  metadata: %{
    processor: Thunderline.Thunderflow.Consumers.Classifier,
    severity: "error"
  }
}
```

## Telemetry Events

Magika emits telemetry for observability:

### Classification Start

```elixir
[:thunderline, :thundergate, :magika, :classify, :start]

# Measurements: %{system_time: integer()}
# Metadata: %{path: string(), filename: string(), correlation_id: string()}
```

### Classification Stop (Success)

```elixir
[:thunderline, :thundergate, :magika, :classify, :stop]

# Measurements: %{duration: integer()}  # nanoseconds
# Metadata: %{
#   path: string(),
#   filename: string(),
#   content_type: string(),
#   confidence: float(),
#   correlation_id: string()
# }
```

### Classification Error

```elixir
[:thunderline, :thundergate, :magika, :classify, :error]

# Measurements: %{duration: integer()}
# Metadata: %{
#   path: string(),
#   filename: string(),
#   error: term(),
#   correlation_id: string()
# }
```

### Example Telemetry Handler

```elixir
:telemetry.attach_many(
  "magika-metrics",
  [
    [:thunderline, :thundergate, :magika, :classify, :start],
    [:thunderline, :thundergate, :magika, :classify, :stop],
    [:thunderline, :thundergate, :magika, :classify, :error]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info("Magika event: #{inspect(event)}", 
      measurements: measurements,
      metadata: metadata
    )
  end,
  nil
)
```

## Broadway Pipeline

Magika is integrated into the ThunderFlow event pipeline via a Broadway consumer.

### Architecture

```
[EventBus] → [BroadwayProducer] → [Classifier Consumer]
                                          ↓
                                   [Magika Wrapper]
                                          ↓
                            [system.ingest.classified event]
```

### Classifier Consumer

The `Thunderline.Thunderflow.Consumers.Classifier` module:

1. Subscribes to `ui.command.ingest.**` events
2. Validates event payload (supports `bytes`/`filename` or `path`)
3. Invokes Magika wrapper
4. Batches successful classifications
5. Routes failures to DLQ

**Configuration:**

```elixir
config :thunderline, Thunderline.Throughflow.Consumers.Classifier,
  batch_size: 10,           # Number of events per batch
  batch_timeout: 1000,      # Max wait time (ms) for batch
  concurrency: 4            # Parallel processors
```

### Supervision

The classifier consumer is supervised under the ML pipeline:

```elixir
# lib/thunderline/application.ex
defp ml_pipeline_children do
  if Feature.enabled?(:ml_pipeline, default: true) do
    [Thunderline.Thunderflow.Consumers.Classifier]
  else
    []
  end
end
```

**Feature flag:** `:ml_pipeline` (enabled by default)

**Disable ML pipeline:**

```elixir
# config/config.exs
config :thunderline, :features, ml_pipeline: false
```

## Testing

### Unit Tests

```elixir
# test/thunderline/thundergate/magika_test.exs
use ExUnit.Case

test "classifies PDF with high confidence" do
  {:ok, result} = Thunderline.Thundergate.Magika.classify_file("test/fixtures/sample.pdf")
  
  assert result.content_type == "application/pdf"
  assert result.confidence > 0.85
  refute result.fallback?
end
```

### Integration Tests

```elixir
# test/thunderline/integration/magika_integration_test.exs
@tag :integration
test "processes PDF through complete pipeline" do
  correlation_id = Thunderline.UUID.v7()
  
  # Publish ingestion event
  {:ok, _} = EventBus.publish(:bus, [
    Event.new(%{
      type: "ui.command.ingest.received",
      source: "test",
      data: %{path: "/tmp/test.pdf"},
      metadata: %{correlation_id: correlation_id}
    })
  ])
  
  # Expect classification event
  assert_receive {:event, %Event{type: "system.ingest.classified"} = classified}, 5_000
  assert classified.metadata.correlation_id == correlation_id
end
```

### Mocking Magika CLI

For tests without Magika installed:

```elixir
setup do
  # Mock Magika CLI response
  Application.put_env(:thunderline, Thunderline.Thundergate.Magika, :mock, fn _path ->
    {:ok, ~s({"output": {"label": "pdf", "score": 0.99, "mime_type": "application/pdf"}})}
  end)
  
  on_exit(fn -> Application.delete_env(:thunderline, Thunderline.Thundergate.Magika, :mock) end)
end
```

## Troubleshooting

### Magika CLI Not Found

**Error:** `{:error, {:cli_failed, :enoent, ""}}`

**Solution:** Ensure Magika is installed and in PATH:

```bash
which magika
# or set MAGIKA_CLI_PATH
export MAGIKA_CLI_PATH=/usr/local/bin/magika
```

### Low Confidence Warnings

**Symptom:** Frequent fallback to extension detection

**Solutions:**

1. Lower confidence threshold (not recommended):
   ```bash
   export MAGIKA_CONFIDENCE_THRESHOLD=0.70
   ```

2. Update Magika to latest version:
   ```bash
   pip install --upgrade magika
   ```

3. Check file integrity (corrupted files yield low confidence)

### CLI Timeout

**Error:** `{:error, {:cli_failed, :timeout, ""}}`

**Solution:** Increase timeout for large files:

```bash
export MAGIKA_TIMEOUT_MS=10000  # 10 seconds
```

### JSON Decode Error

**Error:** `{:error, {:json_decode_error, ...}}`

**Cause:** Magika CLI output changed or corrupted

**Solution:**

1. Test CLI manually:
   ```bash
   magika --json --output-score /path/to/file
   ```

2. Verify JSON output format

3. Update Magika wrapper if schema changed

## Performance Considerations

### Throughput

- **Single file:** ~100-500ms (includes CLI startup)
- **Batch processing:** Broadway batching amortizes overhead
- **Concurrency:** Set `CLASSIFIER_CONCURRENCY` based on CPU cores

### Optimization Tips

1. **Use bytes classification for uploads:** Avoids writing to disk twice
   ```elixir
   Magika.classify_bytes(upload.bytes, upload.filename)
   ```

2. **Adjust batch size:** Larger batches = better throughput, higher latency
   ```bash
   export CLASSIFIER_BATCH_SIZE=50
   ```

3. **Monitor telemetry:** Track duration metrics to identify bottlenecks

4. **Cache results:** Store content_type with file metadata to avoid re-classification

## Next Steps

After Magika classification:

1. **NLP Analysis:** Extract entities, sentiment from text files
2. **ML Inference:** Run ONNX models on classified content
3. **Voxel Packaging:** Package results into DAG commits

See [ML_PIPELINE_INTEGRATION.md](ML_PIPELINE_INTEGRATION.md) for full pipeline architecture.

## References

- [Google Magika GitHub](https://github.com/google/magika)
- [Magika Paper](https://arxiv.org/abs/2308.13194)
- [ThunderFlow Architecture](THUNDERLINE_MASTER_PLAYBOOK.md#thunderflow-event-pipeline)
- [Event Taxonomy](EVENT_TAXONOMY.md)
