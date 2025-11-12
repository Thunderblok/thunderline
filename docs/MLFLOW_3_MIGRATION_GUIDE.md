# MLflow 3.0 Migration Guide

**Status**: Dependency Updated | Code Migration Pending  
**Current Version**: 2.9.0  
**Target Version**: 3.1.0+  
**Breaking Changes**: Yes (see below)

---

## Quick Start: Install MLflow 3.0

```bash
# Update dependencies
cd /home/mo/DEV/Thunderline/thunderhelm/cerebros_service
pip install -r requirements.txt

# Verify installation
python -c "import mlflow; print(mlflow.__version__)"
# Expected: 3.1.0 or higher
```

---

## Breaking Changes & Required Updates

### 1. LoggedModel Entity (Major Change)

**Before (MLflow 2.x)**:
```python
with mlflow.start_run():
    mlflow.pyfunc.log_model(
        artifact_path="model",  # ← Old API
        python_model=model
    )
```

**After (MLflow 3.x)**:
```python
# No start_run() required!
mlflow.pyfunc.log_model(
    name="model",  # ← New API (artifact_path deprecated)
    python_model=model
)
```

**Why This Matters**:
- Models are now first-class entities (not tied to runs)
- Can log models without starting a run
- Models become the central hub for linking traces, evaluations, prompts
- Better for production model management

**Migration Steps**:
1. Search codebase for `artifact_path=` usage
2. Replace with `name=` parameter
3. Remove unnecessary `mlflow.start_run()` wrappers
4. Test model logging still works

---

### 2. Removed Features

**MLflow Recipes** ❌ REMOVED
```python
# This no longer works in MLflow 3.x
from mlflow.recipes import ...  # ← REMOVED
```

**Deprecated Flavors** ❌ REMOVED
- `mlflow.fastai.*` - No longer supported
- `mlflow.mleap.*` - No longer supported

**AI Gateway Client APIs** ❌ REMOVED
```python
# This no longer works
from mlflow.gateway import ...  # ← REMOVED
# Use mlflow.deployments instead
```

**Migration Steps**:
1. Search for `mlflow.recipes`, `mlflow.fastai`, `mlflow.mleap`, `mlflow.gateway`
2. If found, refactor to use alternative approaches
3. For gateway functionality, use `mlflow.deployments`

---

### 3. Model Storage Location Changed

**Before**: Models stored in run artifacts  
**After**: Models stored in separate model artifacts location

**Implications**:
- Both client AND server must be upgraded to MLflow 3.x
- Mixed versions (client 3.x + server 2.x) will cause issues
- Check your MLflow tracking server version

**Migration Steps**:
1. Upgrade MLflow server to 3.x (if self-hosted)
2. Ensure all clients upgrade to 3.x
3. Don't deploy with mixed versions

---

## New Features & Capabilities

### 1. Active Model Pattern (Trace Linking)

**Use Case**: Group all traces related to a specific model

```python
# Set the active model context
mlflow.set_active_model(name="cerebros_classifier")

# Enable autologging
mlflow.tensorflow.autolog()  # or pytorch, sklearn, etc.

# All subsequent operations auto-link to this model
model = train_your_model(data)

# Get the active model ID
active_model_id = mlflow.get_active_model_id()

# Search traces for this model
traces = mlflow.search_traces(model_id=active_model_id)
```

**Benefits**:
- Automatic lineage tracking
- Group traces from dev and production
- Compare model versions easily
- No manual trace management

---

### 2. GenAI Evaluation Metrics

**Use Case**: Evaluate LLM/GenAI outputs with state-of-the-art metrics

```python
from mlflow.metrics.genai import (
    answer_correctness,
    answer_similarity,
    faithfulness
)

# Define evaluation metrics
metrics = {
    # How similar is the answer to ground truth?
    "answer_similarity": answer_similarity(model="openai:/gpt-4o"),
    
    # Is the answer correct based on context?
    "answer_correctness": answer_correctness(model="openai:/gpt-4o"),
    
    # Is the answer faithful to the source material?
    "faithfulness": faithfulness(model="openai:/gpt-4o")
}

# Evaluate your model
results = mlflow.evaluate(
    model="cerebros_classifier",
    data=eval_dataset,
    metrics=metrics,
    model_type="question-answering"  # or "text-generation", "text-classification", etc.
)

# Log metrics linked to active model
mlflow.log_metrics(results.metrics, model_id=active_model_id)
```

**Available Metrics**:
- `answer_similarity` - Semantic similarity to ground truth
- `answer_correctness` - Correctness based on context
- `answer_relevance` - Relevance to the question
- `faithfulness` - Faithfulness to source documents
- `answer_conciseness` - Conciseness of answer
- Custom metrics via LLM judges

**Requirements**:
- OpenAI API key (or other LLM provider)
- Install: `pip install openai>=1.0.0`
- Set: `export OPENAI_API_KEY="your-key"`

---

### 3. Prompt Registry

**Use Case**: Version and optimize prompts systematically

```python
# Register a prompt template
prompt = mlflow.genai.register_prompt(
    name="classification_prompt",
    template="""
You are an expert classifier. Categorize the following text:

## Text:
{{text}}

## Categories:
{{categories}}

## Instructions:
Respond with only the category name, no explanation.
""",
    commit_message="Initial classification prompt"
)

# Use the prompt
loaded_prompt = mlflow.genai.load_prompt("classification_prompt")
formatted = loaded_prompt.format(
    text="Apple Inc. announced new products",
    categories="Technology, Finance, Sports"
)

# Update prompt version
mlflow.genai.register_prompt(
    name="classification_prompt",
    template="<improved template>",
    commit_message="Added few-shot examples"
)
```

**Benefits**:
- Version control for prompts
- A/B test different prompt versions
- Track prompt performance
- Systematic prompt engineering

---

### 4. Comprehensive Tracing

**Use Case**: Track all LLM/GenAI calls automatically

```python
# Enable autologging
mlflow.openai.autolog()  # For OpenAI
# or mlflow.langchain.autolog()  # For LangChain
# or mlflow.llamaindex.autolog()  # For LlamaIndex

# Set active model for trace linking
mlflow.set_active_model(name="cerebros_assistant")

# Make LLM calls (automatically traced)
import openai
response = openai.ChatCompletion.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Classify this text"}]
)

# All traces automatically linked to active model
active_model_id = mlflow.get_active_model_id()
traces = mlflow.search_traces(
    model_id=active_model_id,
    filter_string="attributes.trace_name = 'ChatCompletion'"
)
```

**What Gets Traced**:
- LLM API calls (input, output, latency)
- Token usage and costs
- Prompt templates used
- Error conditions
- Metadata (timestamps, versions, etc.)

---

## Migration Checklist for Cerebros Team

### Phase 1: Preparation (1 hour)

- [x] Update `thunderhelm/cerebros_service/requirements.txt`
- [ ] Verify MLflow tracking server is also 3.x (if self-hosted)
- [ ] Review codebase for breaking changes:
  ```bash
  # Search for potential issues
  cd /home/mo/DEV/Thunderline/thunderhelm
  grep -r "artifact_path" .
  grep -r "mlflow.recipes" .
  grep -r "mlflow.fastai" .
  grep -r "mlflow.mleap" .
  grep -r "mlflow.gateway" .
  ```
- [ ] Read MLflow 3.0 docs: https://mlflow.org/docs/latest/genai/mlflow-3

### Phase 2: Update Code (2-4 hours)

- [ ] Replace `artifact_path` with `name` in all `log_model` calls
- [ ] Remove unnecessary `mlflow.start_run()` wrappers
- [ ] Update to `LoggedModel` pattern where appropriate
- [ ] Add active model context for trace linking
- [ ] Test existing functionality still works

### Phase 3: Add New Features (2-4 hours)

- [ ] Implement active model pattern
- [ ] Add GenAI evaluation metrics (if using LLMs)
- [ ] Register prompts in prompt registry (if using prompts)
- [ ] Enable autologging for comprehensive tracing
- [ ] Test new features work as expected

### Phase 4: Testing & Validation (1-2 hours)

- [ ] Run existing experiments to verify compatibility
- [ ] Test model logging and retrieval
- [ ] Verify traces are captured correctly
- [ ] Check metrics logging works
- [ ] Validate prompt registry if used
- [ ] Performance test (ensure no regressions)

---

## Code Examples: Before & After

### Example 1: Basic Model Logging

**Before (MLflow 2.x)**:
```python
import mlflow
import mlflow.pyfunc

# Create custom model
class CerebrosClassifier(mlflow.pyfunc.PythonModel):
    def predict(self, context, model_input):
        # Your prediction logic
        return predictions

# Log model (required run context)
with mlflow.start_run():
    mlflow.pyfunc.log_model(
        artifact_path="cerebros_classifier",  # ← Old API
        python_model=CerebrosClassifier(),
        conda_env={
            "dependencies": [
                "tensorflow>=2.15.0",
                "numpy>=1.24.0"
            ]
        }
    )
    mlflow.log_params({"epochs": 10, "batch_size": 32})
    mlflow.log_metrics({"accuracy": 0.95, "f1_score": 0.92})
```

**After (MLflow 3.x)**:
```python
import mlflow
import mlflow.pyfunc

# Same custom model
class CerebrosClassifier(mlflow.pyfunc.PythonModel):
    def predict(self, context, model_input):
        return predictions

# Set active model for trace linking
mlflow.set_active_model(name="cerebros_classifier")

# Log model (no run required!)
mlflow.pyfunc.log_model(
    name="cerebros_classifier",  # ← New API
    python_model=CerebrosClassifier(),
    conda_env={
        "dependencies": [
            "tensorflow>=2.15.0",
            "numpy>=1.24.0"
        ]
    }
)

# Log metrics linked to model
active_model_id = mlflow.get_active_model_id()
mlflow.log_metrics({
    "accuracy": 0.95,
    "f1_score": 0.92
}, model_id=active_model_id)
```

---

### Example 2: Training with Tracing

**Before (MLflow 2.x)**:
```python
import mlflow
import tensorflow as tf

# Manual run management
with mlflow.start_run():
    # Enable autologging
    mlflow.tensorflow.autolog()
    
    # Train model
    model = tf.keras.Sequential([...])
    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy')
    model.fit(X_train, y_train, epochs=10)
    
    # Log model
    mlflow.tensorflow.log_model(
        model=model,
        artifact_path="model"  # ← Old API
    )
```

**After (MLflow 3.x)**:
```python
import mlflow
import tensorflow as tf

# Set active model
mlflow.set_active_model(name="cerebros_tf_model")

# Enable autologging (auto-links to active model)
mlflow.tensorflow.autolog()

# Train model (automatically traced)
model = tf.keras.Sequential([...])
model.compile(optimizer='adam', loss='sparse_categorical_crossentropy')
model.fit(X_train, y_train, epochs=10)

# Log model (no run or artifact_path needed!)
mlflow.tensorflow.log_model(
    model=model,
    name="cerebros_tf_model"  # ← New API
)

# Get model ID and search traces
active_model_id = mlflow.get_active_model_id()
traces = mlflow.search_traces(model_id=active_model_id)
print(f"Captured {len(traces)} training traces")
```

---

### Example 3: LLM Evaluation with GenAI Metrics

**New in MLflow 3.x**:
```python
import mlflow
from mlflow.metrics.genai import answer_similarity, faithfulness

# Prepare evaluation data
eval_data = [
    {
        "question": "What is the capital of France?",
        "ground_truth": "Paris",
        "prediction": "The capital of France is Paris."
    },
    {
        "question": "Who wrote Romeo and Juliet?",
        "ground_truth": "William Shakespeare",
        "prediction": "Shakespeare wrote Romeo and Juliet."
    }
]

# Define GenAI metrics
metrics = {
    "answer_similarity": answer_similarity(model="openai:/gpt-4o"),
    "faithfulness": faithfulness(model="openai:/gpt-4o")
}

# Evaluate model
results = mlflow.evaluate(
    model="cerebros_qa_model",
    data=eval_data,
    metrics=metrics,
    model_type="question-answering"
)

# Log results linked to model
mlflow.log_metrics(results.metrics, model_id=active_model_id)

# View detailed results
print(results.tables)
```

---

## Integration with NLP Pipeline

### Example: Track NLP + Classification Pipeline

```python
import mlflow
from thunderline_nlp import extract_entities, analyze_sentiment

# Set active model
mlflow.set_active_model(name="cerebros_nlp_classifier")

# Enable autologging
mlflow.autolog()

def preprocess_with_nlp(texts):
    """Preprocess texts with NLP features"""
    processed = []
    
    for text in texts:
        # NLP extraction (can be traced)
        entities = extract_entities(text)
        sentiment = analyze_sentiment(text)
        
        # Log NLP features
        mlflow.log_dict({
            "text": text,
            "entities": entities,
            "sentiment": sentiment
        }, f"nlp_features_{len(processed)}.json")
        
        processed.append({
            "text": text,
            "entity_count": len(entities),
            "sentiment_score": sentiment["polarity"]
        })
    
    return processed

# Train classification model with NLP features
nlp_features = preprocess_with_nlp(training_texts)
model = train_classifier(nlp_features, labels)

# Log model with NLP pipeline
mlflow.pyfunc.log_model(
    name="cerebros_nlp_classifier",
    python_model=model,
    artifacts={"nlp_processor": "nlp_service.py"}
)

# Search traces for full pipeline
active_model_id = mlflow.get_active_model_id()
traces = mlflow.search_traces(model_id=active_model_id)
```

---

## Troubleshooting

### Issue: "artifact_path is deprecated"

**Error**:
```
Warning: artifact_path is deprecated in MLflow 3.x. Use 'name' instead.
```

**Solution**:
```python
# Replace this:
mlflow.pyfunc.log_model(artifact_path="model", ...)

# With this:
mlflow.pyfunc.log_model(name="model", ...)
```

---

### Issue: "Model not found in tracking server"

**Possible Causes**:
1. Server is still MLflow 2.x (mixed versions)
2. Model was logged to wrong location
3. Tracking URI not configured

**Solution**:
```python
# Check MLflow server version
import requests
response = requests.get(f"{mlflow.get_tracking_uri()}/version")
print(f"Server version: {response.json()}")

# Ensure both client and server are 3.x
import mlflow
print(f"Client version: {mlflow.__version__}")

# If server is 2.x, upgrade it before using MLflow 3.x client
```

---

### Issue: "Cannot find active model"

**Error**:
```
RuntimeError: No active model set. Call mlflow.set_active_model() first.
```

**Solution**:
```python
# Always set active model before operations that need it
mlflow.set_active_model(name="your_model_name")

# Then proceed with tracing, logging, etc.
```

---

### Issue: "GenAI metrics failing"

**Error**:
```
AuthenticationError: No API key provided
```

**Solution**:
```bash
# Set OpenAI API key
export OPENAI_API_KEY="your-key"

# Or use alternative LLM provider
# See: https://mlflow.org/docs/latest/llms/deployments/
```

---

## Performance Considerations

### Model Storage

**MLflow 3.x stores models separately from run artifacts**

**Implications**:
- Faster model retrieval
- Better model versioning
- Larger storage requirements (models + runs)

**Optimization**:
```python
# Clean up old model versions
from mlflow.tracking import MlflowClient
client = MlflowClient()

# Delete old versions (keep last 5)
model_versions = client.search_model_versions(f"name='cerebros_classifier'")
for version in sorted(model_versions, key=lambda v: v.version)[:-5]:
    client.delete_model_version(
        name="cerebros_classifier",
        version=version.version
    )
```

---

### Trace Volume

**Autologging can generate many traces**

**Best Practices**:
```python
# Disable tracing for high-frequency operations
with mlflow.disable_autologging():
    # Batch predictions (no tracing)
    predictions = model.predict(large_batch)

# Enable tracing only for important operations
mlflow.autolog()
results = model.evaluate(test_data)  # Traced
```

---

## Additional Resources

- **MLflow 3.0 Release Notes**: https://github.com/mlflow/mlflow/releases/tag/v3.0.0
- **GenAI Guide**: https://mlflow.org/docs/latest/genai/mlflow-3
- **Migration FAQ**: https://mlflow.org/docs/latest/genai/migration-guide
- **API Reference**: https://mlflow.org/docs/latest/python_api/index.html

---

## Summary

**Key Takeaways**:

1. **LoggedModel** is the major change - models are now first-class entities
2. **Breaking changes** exist - review code for `artifact_path`, removed features
3. **GenAI features** are powerful - leverage for LLM/NLP work
4. **Both client and server** must upgrade to 3.x
5. **Backward compatibility** is limited - plan migration carefully

**Migration Priority**: MEDIUM-HIGH

- ✅ Dependency updated (`requirements.txt`)
- ⏳ Code review needed (search for breaking changes)
- ⏳ Testing required (verify existing functionality)
- 📅 Estimated effort: 4-8 hours total

**Next Steps**:

1. Review this guide completely
2. Search codebase for breaking changes
3. Plan migration in phases
4. Test thoroughly before production deployment
5. Leverage new GenAI features for better experiments

---

**Questions or Issues?**

- Check MLflow docs: https://mlflow.org/docs/latest/
- Review examples in this guide
- Ask in team Slack channel
- Open issue on MLflow GitHub if needed
