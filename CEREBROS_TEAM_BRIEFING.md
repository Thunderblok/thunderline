# Cerebros Team Briefing: NLP Integration & GenAI Pipeline

**Date**: November 11, 2025  
**Status**: Production-Ready Core Features | Expanding Capabilities  
**Team**: Thunderline Engineering

---

## Executive Summary

We've successfully integrated production-grade NLP capabilities into Thunderline using **Spacy 3.8** and are now expanding to a comprehensive **GenAI-powered data ingestion and classification pipeline**. This briefing explains:

1. **What we've built** (verified NLP integration)
2. **Why it matters** (business value & use cases)
3. **How it fits** (architecture & integration touchpoints)
4. **Where we're going** (MLflow 3.0 GenAI + advanced tooling)
5. **What Cerebros team needs to know** (integration points, APIs, workflows)

---

## 1. What We've Built: NLP Integration

### Current State: Production-Ready Core (60% Complete)

**Architecture**: Zero-dependency subprocess via Port API + line-delimited JSON

**Verified Capabilities** (3/5 functions tested in production):

```elixir
alias Thunderline.Thunderbolt.CerebrosBridge.NLP

# 1. Entity Extraction ✅ (VERIFIED)
{:ok, %{"entities" => entities}} = 
  NLP.extract_entities("Apple Inc. is buying a U.K. startup for $1 billion")
# => [
#   %{"text" => "Apple Inc.", "label" => "ORG"},
#   %{"text" => "U.K.", "label" => "GPE"},
#   %{"text" => "$1 billion", "label" => "MONEY"}
# ]

# 2. Tokenization ✅ (VERIFIED)
{:ok, %{"tokens" => tokens}} = 
  NLP.tokenize("The quick brown fox jumps")
# => [
#   %{"text" => "The", "pos" => "DET", "lemma" => "the"},
#   %{"text" => "quick", "pos" => "ADJ", "lemma" => "quick"}
# ]

# 3. Sentiment Analysis ✅ (VERIFIED)
{:ok, %{"polarity" => score}} = 
  NLP.analyze_sentiment("This product is fantastic!")
# => %{"polarity" => 0.85, "subjectivity" => 0.9}
```

**Remaining Functions** (ready to test):
- `analyze_syntax/2` - Dependency parsing
- `process/2` - Full pipeline (all capabilities in one call)

**Performance Metrics**:
- ~1.5-2s per operation (includes model load)
- Zero external dependencies (pure subprocess)
- Robust error handling with timeouts

---

## 2. Why This Matters: Business Value

### Use Cases Enabled

**1. Intelligent Document Processing**
- Extract entities from contracts, reports, user uploads
- Classify document types automatically
- Route documents based on content

**2. User Content Analysis**
- Understand user sentiment in feedback/support tickets
- Extract key information from unstructured text
- Auto-categorize user submissions

**3. Data Quality & Enrichment**
- Normalize text data with lemmatization
- Detect and extract named entities
- Add semantic metadata to raw data

**4. ML Pipeline Foundation**
- Preprocessing for model training
- Feature extraction for classification
- Text normalization for embeddings

---

## 3. How It Fits: Architecture & Integration

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      THUNDERLINE SYSTEM                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────┐         ┌──────────────────┐               │
│  │  LiveView/  │────────>│  Thunderbolt     │               │
│  │  API Layer  │         │  (Core Logic)    │               │
│  └─────────────┘         └────────┬─────────┘               │
│                                    │                          │
│                          ┌─────────▼──────────┐              │
│                          │  CerebrosBridge    │              │
│                          │  (Integration)     │              │
│                          └─────────┬──────────┘              │
│                                    │                          │
│         ┌──────────────────────────┴───────────────┐         │
│         │                                           │         │
│  ┌──────▼──────┐                          ┌────────▼───────┐ │
│  │ NLP Module  │                          │ Cerebros       │ │
│  │ (Spacy)     │                          │ (TensorFlow)   │ │
│  └──────┬──────┘                          └────────┬───────┘ │
│         │                                           │         │
│  ┌──────▼──────────────────────────────────────────▼───────┐ │
│  │              Port API (Subprocess Bridge)                │ │
│  │  Line-delimited JSON stdin/stdout communication          │ │
│  └──────┬──────────────────────────────────────────┬───────┘ │
│         │                                           │         │
│  ┌──────▼──────┐                          ┌────────▼───────┐ │
│  │ nlp_cli.py  │                          │ cerebros_cli   │ │
│  │ nlp_service │                          │ TF models      │ │
│  └─────────────┘                          └────────────────┘ │
│                                                               │
│                    PYTHON SUBPROCESS LAYER                    │
└─────────────────────────────────────────────────────────────┘
```

### Integration Touchpoints

**For Cerebros Team**:

1. **Shared Infrastructure**:
   - Both NLP and Cerebros use the same Port API pattern
   - Same JSON communication protocol
   - Same error handling strategies
   - Same timeout/retry logic

2. **CerebrosBridge Module** (`lib/thunderline/thunderbolt/cerebros_bridge/`):
   - `nlp.ex` - NLP functions
   - `cerebros.ex` - Your model training/prediction
   - Shared utilities for subprocess management

3. **Python CLI Layer** (`thunderhelm/`):
   - `nlp_cli.py` - NLP wrapper
   - `cerebros_cli.py` - Your model wrapper
   - Both follow same stdin/stdout JSON pattern

---

## 4. Where We're Going: The Big Picture

### Phase 1: Current State ✅
- NLP integration (60% complete)
- Subprocess architecture proven
- Production-ready core functions

### Phase 2: GenAI Pipeline (IN PROGRESS)

**2.1 MLflow 3.0 GenAI Integration** 🚀

We're upgrading from **MLflow 2.9** to **MLflow 3.0** to leverage:

**Key MLflow 3.0 Features**:

1. **LoggedModel Entity** - First-class model versioning:
   ```python
   # OLD (MLflow 2.x)
   with mlflow.start_run():
       mlflow.log_model(artifact_path="model", python_model=model)
   
   # NEW (MLflow 3.x)
   mlflow.pyfunc.log_model(
       name="cerebros_classifier",  # Named models!
       python_model=model,
       # Links traces, evaluations, prompts
   )
   ```

2. **Comprehensive Tracing** - Track LLM interactions:
   ```python
   mlflow.set_active_model(name="openai_model")
   mlflow.openai.autolog()  # Auto-trace all calls
   
   # All traces linked to model
   mlflow.search_traces(model_id=active_model_id)
   ```

3. **GenAI Evaluation Metrics**:
   ```python
   from mlflow.metrics.genai import (
       answer_correctness,
       answer_similarity,
       faithfulness
   )
   
   metrics = {
       "answer_similarity": answer_similarity(model="openai:/gpt-4o"),
       "answer_correctness": answer_correctness(model="openai:/gpt-4o"),
       "faithfulness": faithfulness(model="openai:/gpt-4o"),
   }
   
   # Evaluate and link to model
   mlflow.log_metrics(metrics, model_id=active_model_id)
   ```

4. **Prompt Registry** - Version and optimize prompts:
   ```python
   prompt = mlflow.genai.register_prompt(
       name="ai_assistant_prompt",
       template="You are an expert...\n\n## Question:\n{{question}}",
       commit_message="Initial version"
   )
   ```

**Why This Matters for Cerebros**:
- Track all Cerebros model experiments with GenAI-enhanced features
- Link NLP preprocessing to model training runs
- Evaluate model outputs with LLM-based metrics
- Version prompts used for data augmentation
- Comprehensive lineage: data → NLP → training → evaluation

---

**2.2 Advanced Text Processing with HairyText** 📊

We're evaluating **HairyText** for interactive data labeling:

**What is HairyText?**
- Elixir + Phoenix LiveView + Spacy NLP tool
- Interactive web UI for labeling training data
- Built for NER (Named Entity Recognition) tasks
- Mobile-friendly, no database required

**Key Features**:
```elixir
# HairyText API predictions
curl 'http://localhost:4141/api/predict/PROJECT_ID?text=i+am+live+on+twitch'
# => {
#   "text": "i am live on twitch",
#   "label": "streaming",
#   "label_confidence": 0.999,
#   "entities": {"service": "twitch"}
# }
```

**Potential Integration**:
- Use for labeling training data for Cerebros models
- Interactive UI for team to review/correct predictions
- Export labeled data for model training
- REST API for predictions (can integrate with our pipeline)

**Decision Pending**: Evaluate if HairyText's features justify adding vs. building custom labeling UI

---

**2.3 Complete Ingestion Pipeline** (12-15 hours total work)

```
┌─────────────────────────────────────────────────────────────┐
│              WORLD-CLASS INGESTION PIPELINE                  │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. FILE-TYPE DETECTION (Magika 1.0)                         │
│     └─> 200+ file types: PDF, Office, images, audio, etc.    │
│                                                               │
│  2. TEXT EXTRACTION                                           │
│     ├─> PDF: pdfminer, pymupdf                               │
│     ├─> Office: python-docx, python-pptx, openpyxl           │
│     ├─> Images: Tesseract OCR, AWS Textract                  │
│     ├─> Audio: Whisper, AWS Transcribe                       │
│     └─> ML Artifacts: Jupyter, Parquet, NumPy                │
│                                                               │
│  3. NLP PROCESSING (Spacy) ✅                                 │
│     ├─> Entity extraction                                    │
│     ├─> Tokenization                                         │
│     ├─> Sentiment analysis                                   │
│     └─> Syntax analysis                                      │
│                                                               │
│  4. CLASSIFICATION                                            │
│     ├─> Domain labeling                                      │
│     ├─> Topic categorization                                 │
│     └─> Quality scoring                                      │
│                                                               │
│  5. VOXEL PACKAGING                                           │
│     └─> Standardized data structure                          │
│                                                               │
│  6. DOWNSTREAM ROUTING                                        │
│     ├─> Thunderflow (events)                                 │
│     ├─> Broadway (streaming)                                 │
│     └─> Storage/indexing                                     │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Voxel Data Structure** (standardized across pipeline):
```elixir
%Thunderline.Thunderblock.Voxel{
  source: "telemetry" | "user_upload" | "doc_conversion",
  file_type: "pdf",  # from Magika
  timestamp: ~U[2025-11-11 12:00:00Z],
  metadata: %{
    original_filename: "report.pdf",
    size_bytes: 1_234_567,
    detected_confidence: 0.98
  },
  text: "Extracted plain text...",
  
  # NLP Results
  entities: [
    %{"text" => "Apple Inc.", "label" => "ORG"},
    %{"text" => "$1B", "label" => "MONEY"}
  ],
  tokens: [...],
  sentiment: %{"polarity" => 0.5},
  syntax: %{"dependencies" => [...]},
  
  # Classification
  classification: [
    %{domain: "finance", confidence: 0.87},
    %{topic: "acquisitions", confidence: 0.93}
  ]
}
```

---

## 5. What Cerebros Team Needs to Know

### Integration Points

**1. Shared Code Patterns**

Both NLP and Cerebros modules follow the same patterns:

```elixir
# NLP Module
defmodule Thunderline.Thunderbolt.CerebrosBridge.NLP do
  @python_executable "python3.13"
  @script_path "thunderhelm/nlp_cli.py"
  
  def extract_entities(text, opts \\ []) do
    with {:ok, port} <- open_port(),
         {:ok, result} <- call_function(port, "extract_entities", [text]),
         :ok <- close_port(port) do
      {:ok, result}
    end
  end
end

# Cerebros Module (similar pattern)
defmodule Thunderline.Thunderbolt.CerebrosBridge.Cerebros do
  @python_executable "python3.13"
  @script_path "thunderhelm/cerebros_cli.py"
  
  def train_model(data, opts \\ []) do
    with {:ok, port} <- open_port(),
         {:ok, result} <- call_function(port, "train_model", [data]),
         :ok <- close_port(port) do
      {:ok, result}
    end
  end
end
```

**2. Python CLI Interface**

Your Python scripts should follow the same pattern:

```python
#!/usr/bin/env python3.13
import sys, json, logging

# Suppress logging for clean JSON
logging.basicConfig(level=logging.ERROR)

def main():
    try:
        # Read line-delimited JSON from stdin
        request_line = sys.stdin.readline()
        request = json.loads(request_line)
        
        function = request['function']
        args = request['args']
        
        # Route to your functions
        if function == 'train_model':
            result = your_train_function(*args)
        elif function == 'predict':
            result = your_predict_function(*args)
        
        # Output JSON to stdout
        print(json.dumps(result), flush=True)
        sys.exit(0)
        
    except Exception as e:
        error = {"error": str(e), "type": type(e).__name__}
        print(json.dumps(error), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
```

**3. MLflow Integration**

With MLflow 3.0 upgrade, both teams should:

```python
import mlflow

# Set active model for trace linking
mlflow.set_active_model(name="your_model_name")

# Enable autologging
mlflow.tensorflow.autolog()  # For TensorFlow
# or mlflow.pytorch.autolog()  # For PyTorch
# or mlflow.sklearn.autolog()  # For scikit-learn

# Train your model
model = train_your_model(data)

# Log model with name (not artifact_path!)
mlflow.pyfunc.log_model(
    name="cerebros_classifier_v2",  # Named models in MLflow 3
    python_model=model,
    # Automatically links traces, runs, evaluations
)

# Get active model ID
active_model_id = mlflow.get_active_model_id()

# Log metrics linked to model
mlflow.log_metrics({
    "accuracy": 0.95,
    "f1_score": 0.92
}, model_id=active_model_id)

# Search traces for this model
traces = mlflow.search_traces(model_id=active_model_id)
```

---

### API Usage Examples

**For Cerebros Team to Call NLP**:

```elixir
# In your Cerebros training code
defmodule YourCerebrosModule do
  alias Thunderline.Thunderbolt.CerebrosBridge.NLP
  
  def preprocess_training_data(raw_texts) do
    Enum.map(raw_texts, fn text ->
      # Extract entities for features
      {:ok, %{"entities" => entities}} = NLP.extract_entities(text)
      
      # Tokenize for text processing
      {:ok, %{"tokens" => tokens}} = NLP.tokenize(text)
      
      # Analyze sentiment
      {:ok, sentiment} = NLP.analyze_sentiment(text)
      
      %{
        original_text: text,
        entities: entities,
        tokens: tokens,
        sentiment: sentiment
      }
    end)
  end
  
  def classify_with_context(text) do
    # Get NLP features first
    {:ok, nlp_features} = NLP.process(text)
    
    # Use features for classification
    your_classify_function(text, nlp_features)
  end
end
```

**Error Handling Best Practices**:

```elixir
case NLP.extract_entities(text) do
  {:ok, result} ->
    # Process result
    handle_entities(result["entities"])
    
  {:error, :timeout} ->
    Logger.warning("NLP timeout, using fallback")
    fallback_entity_extraction(text)
    
  {:error, reason} ->
    Logger.error("NLP failed: #{inspect(reason)}")
    {:error, :nlp_unavailable}
end
```

---

### Configuration & Environment

**Python Dependencies** (updating `thunderhelm/cerebros_service/requirements.txt`):

```txt
# Current
mlflow>=2.9.0

# Upgrading to
mlflow>=3.1.0

# Additional for GenAI features
openai>=1.0.0  # If using OpenAI for evaluation
spacy>=3.8.0   # Already installed for NLP
```

**Environment Variables**:

```bash
# For MLflow 3.0 GenAI features
export OPENAI_API_KEY="your-key"  # If using OpenAI metrics

# For NLP (already configured)
export SPACY_MODEL="en_core_web_sm"
export NLP_TIMEOUT="5000"

# For Cerebros
export MLFLOW_TRACKING_URI="http://localhost:5000"
export MLFLOW_EXPERIMENT_NAME="cerebros_experiments"
```

---

### Testing & Validation

**Test NLP Integration**:

```bash
# From Thunderline root
cd /home/mo/DEV/Thunderline

# Run demo script (tests all NLP functions)
MIX_ENV=dev mix run demo_nlp.exs

# Or test individual functions in iex
iex -S mix
```

```elixir
iex> alias Thunderline.Thunderbolt.CerebrosBridge.NLP
iex> NLP.extract_entities("Apple Inc. bought a startup for $1B")
{:ok, %{"entities" => [...]}}
```

**Integration Testing**:

```elixir
# test/thunderline/thunderbolt/cerebros_bridge/integration_test.exs
defmodule Thunderline.Thunderbolt.CerebrosBridge.IntegrationTest do
  use ExUnit.Case
  
  alias Thunderline.Thunderbolt.CerebrosBridge.{NLP, Cerebros}
  
  test "NLP + Cerebros pipeline" do
    text = "Important financial news about Apple"
    
    # NLP preprocessing
    {:ok, nlp_result} = NLP.process(text)
    
    # Cerebros classification
    {:ok, classification} = Cerebros.classify(text, nlp_result)
    
    assert classification["category"] in ["finance", "technology"]
  end
end
```

---

### Documentation Resources

**For Cerebros Team**:

1. **NLP Quick Start**: `docs/NLP_QUICK_START.md`
   - Copy-paste examples for all NLP functions
   - Error handling patterns
   - Configuration options

2. **NLP Integration Status**: `docs/NLP_INTEGRATION_STATUS.md`
   - Detailed verification results
   - Performance metrics
   - Known issues

3. **Pipeline Blueprint**: `INGESTION_PIPELINE_BLUEPRINT.md`
   - Complete architecture design
   - Implementation roadmap
   - Voxel schema specification

4. **MLflow 3.0 Docs**: https://mlflow.org/docs/latest/genai/mlflow-3
   - GenAI features guide
   - Migration from 2.x
   - API reference

---

## 6. Timeline & Next Steps

### Immediate (This Week)

- [x] Complete NLP integration documentation
- [x] Create Cerebros team briefing (this doc)
- [ ] Upgrade MLflow 2.9 → 3.1 in thunderhelm
- [ ] Test remaining 2 NLP functions
- [ ] Add `:ml_nlp` feature flag

### Short-term (Next 2 Weeks)

- [ ] Implement Magika file-type detection
- [ ] Create text extraction pipeline
- [ ] Build Voxel packaging system
- [ ] Integrate MLflow 3.0 tracing with Cerebros
- [ ] Evaluate HairyText for data labeling

### Medium-term (Next Month)

- [ ] Complete ingestion pipeline (all 6 stages)
- [ ] Production deployment with feature flags
- [ ] Performance optimization
- [ ] Comprehensive testing
- [ ] Team training on new capabilities

---

## 7. Questions & Support

**For NLP Integration Issues**:
- Check: `docs/NLP_QUICK_START.md` (troubleshooting section)
- Test: Run `MIX_ENV=dev mix run demo_nlp.exs`
- Ask: Tag @thunderline-team in Slack

**For MLflow 3.0 Migration**:
- Docs: https://mlflow.org/docs/latest/genai/mlflow-3
- Migration guide: Check "Breaking changes" section
- Pattern: See examples in this document

**For Pipeline Architecture**:
- Blueprint: `INGESTION_PIPELINE_BLUEPRINT.md`
- Status: `docs/NLP_INTEGRATION_STATUS.md`
- Discuss: Weekly architecture sync

---

## Appendix: Technical Deep Dive

### Port API Communication Protocol

**Request Format** (Elixir → Python):
```json
{"function": "extract_entities", "args": ["Apple Inc. bought a startup"]}
```

**Response Format** (Python → Elixir):
```json
{
  "entities": [
    {"text": "Apple Inc.", "label": "ORG", "start": 0, "end": 10},
    {"text": "startup", "label": "ORG", "start": 22, "end": 29}
  ]
}
```

**Error Format**:
```json
{
  "error": "Model not found: en_core_web_sm",
  "type": "OSError"
}
```

### Performance Considerations

**Optimization Strategies**:

1. **Model Caching**: Load Spacy model once, reuse for all requests
2. **Batch Processing**: Send multiple texts in one call
3. **Async Processing**: Use Oban for background jobs
4. **Feature Flags**: Enable/disable NLP per environment

**Monitoring**:

```elixir
# Add telemetry for NLP calls
:telemetry.execute(
  [:thunderline, :nlp, :extract_entities],
  %{duration: duration_ms},
  %{text_length: String.length(text)}
)
```

---

## Summary: The Big Picture for Cerebros Team

**What We're Building**:
A world-class data ingestion and classification pipeline that combines:
- Production-grade NLP (Spacy)
- Advanced ML experiment tracking (MLflow 3.0 GenAI)
- Standardized data structures (Voxel)
- Seamless integration with Cerebros models

**Why It Matters**:
- Unified approach to text processing across the platform
- Better model training with NLP-enriched features
- Comprehensive tracking of experiments and evaluations
- Scalable architecture for future expansion

**What You Need to Do**:
1. Review this document and ask questions
2. Prepare for MLflow 3.0 migration
3. Consider how NLP features can enhance your models
4. Plan integration testing with NLP pipeline

**Where We're Going**:
From simple text processing → Comprehensive GenAI pipeline with state-of-the-art tooling

---

**Questions? Comments? Concerns?**

Reach out to the Thunderline team! We're here to make this integration smooth and powerful for everyone. 🚀
