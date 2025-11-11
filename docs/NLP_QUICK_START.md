# NLP Integration Quick Start

**TL;DR**: We can now do industrial-grade NLP (entity extraction, tokenization, sentiment analysis) on any text in Thunderline with **zero external Elixir dependencies**. The integration is production-ready and verified working.

---

## 🚀 Quick Examples

### Extract Entities from Text

```elixir
alias Thunderline.Thunderbolt.CerebrosBridge.NLP

text = "Apple Inc. is buying a U.K. startup for $1 billion"

{:ok, %{"entities" => entities}} = NLP.extract_entities(text)

# Returns:
# [
#   %{"text" => "Apple Inc.", "label" => "ORG", "start" => 0, "end" => 10},
#   %{"text" => "U.K.", "label" => "GPE", "start" => 23, "end" => 27},
#   %{"text" => "$1 billion", "label" => "MONEY", "start" => 40, "end" => 50}
# ]
```

**Entity Types**: ORG (organizations), PERSON (people), GPE (geopolitical entities), MONEY, DATE, TIME, PERCENT, PRODUCT, EVENT, WORK_OF_ART, LAW, LANGUAGE, etc.

---

### Tokenize Text for Search

```elixir
text = "The quick brown fox jumps over the lazy dog"

{:ok, %{"tokens" => tokens}} = NLP.tokenize(text)

# Returns:
# [
#   %{"text" => "The", "pos" => "DET", "lemma" => "the", "dep" => "det"},
#   %{"text" => "quick", "pos" => "ADJ", "lemma" => "quick", "dep" => "amod"},
#   %{"text" => "brown", "pos" => "ADJ", "lemma" => "brown", "dep" => "amod"},
#   %{"text" => "fox", "pos" => "NOUN", "lemma" => "fox", "dep" => "nsubj"},
#   %{"text" => "jumps", "pos" => "VERB", "lemma" => "jump", "dep" => "ROOT"},
#   ...
# ]

# Extract just nouns for indexing
keywords = 
  tokens
  |> Enum.filter(fn t -> t["pos"] in ["NOUN", "PROPN"] end)
  |> Enum.map(fn t -> t["lemma"] end)
  |> Enum.uniq()
# => ["fox", "dog"]
```

**POS Tags**: DET (determiner), ADJ (adjective), NOUN, VERB, ADV (adverb), PROPN (proper noun), etc.

---

### Analyze Sentiment

```elixir
positive = "This product is absolutely fantastic! I love it!"
negative = "This is terrible. I hate it."

{:ok, %{"polarity" => pos_score, "label" => pos_label}} = NLP.analyze_sentiment(positive)
# => %{"polarity" => 0.8, "subjectivity" => 0.9, "label" => "positive"}

{:ok, %{"polarity" => neg_score, "label" => neg_label}} = NLP.analyze_sentiment(negative)
# => %{"polarity" => -0.8, "subjectivity" => 1.0, "label" => "negative"}
```

**Values**:
- `polarity`: -1.0 (negative) to +1.0 (positive)
- `subjectivity`: 0.0 (objective) to 1.0 (subjective)
- `label`: "positive", "negative", or "neutral"

---

### Parse Syntax (Advanced)

```elixir
text = "The CEO announced a major acquisition yesterday."

{:ok, %{"sentences" => sentences, "noun_chunks" => chunks}} = NLP.analyze_syntax(text)

# sentences = [
#   %{
#     "text" => "The CEO announced a major acquisition yesterday.",
#     "start" => 0,
#     "end" => 48,
#     "tokens" => [...]
#   }
# ]
#
# chunks = [
#   %{"text" => "The CEO", "root" => "CEO", "root_pos" => "NOUN"},
#   %{"text" => "a major acquisition", "root" => "acquisition", "root_pos" => "NOUN"}
# ]
```

---

### Full Processing Pipeline

```elixir
text = """
Apple Inc. is buying a U.K. startup for $1 billion.
This is a strategic acquisition that will boost innovation.
"""

{:ok, results} = NLP.process(text, %{
  extract_entities: true,
  tokenize: true,
  analyze_sentiment: true,
  analyze_syntax: true
})

# Returns ALL features in one call:
# %{
#   "entities" => [...],
#   "tokens" => [...],
#   "sentiment" => %{"polarity" => ..., "label" => ...},
#   "sentences" => [...],
#   "noun_chunks" => [...]
# }
```

---

## 🔧 Error Handling

```elixir
case NLP.extract_entities(text) do
  {:ok, result} ->
    # Success - process result
    entities = result["entities"]
    
  {:error, :timeout} ->
    # NLP operation took too long (>30s)
    Logger.warn("NLP timeout - text too large?")
    
  {:error, {:python_error, msg}} ->
    # Python subprocess failed
    Logger.error("Python error: #{msg}")
    
  {:error, reason} ->
    # Other error
    Logger.error("NLP failed: #{inspect(reason)}")
end
```

---

## ⚙️ Configuration

### Timeouts

```elixir
# Default timeout: 30 seconds
NLP.extract_entities(text)

# Custom timeout (in milliseconds)
NLP.extract_entities(text, %{timeout: 60_000})  # 60 seconds
```

### Options

```elixir
# Full processing with selective features
NLP.process(text, %{
  extract_entities: true,   # Named entities
  tokenize: false,          # Skip tokenization
  analyze_sentiment: true,  # Sentiment only
  analyze_syntax: false     # Skip syntax parsing
})
```

---

## 📊 Performance

- **Entity extraction**: ~1.8s (includes model load)
- **Tokenization**: ~1.5s
- **Sentiment analysis**: ~1.5s
- **Full processing**: ~2-3s (all features)

**Note**: Each call spawns a fresh Python subprocess (clean, no state pollution). For batch processing, consider using Oban workers to parallelize.

---

## 🐛 Troubleshooting

### "Python not found"

```bash
# Ensure Python 3.13 is in PATH
which python3
# /usr/bin/python3

# Or set explicit path
export THUNDERLINE_PYTHON_PATH="/path/to/python3"
```

### "Spacy model not found"

```bash
# Install en_core_web_sm model
python3 -m spacy download en_core_web_sm

# Verify installation
python3 -c "import spacy; spacy.load('en_core_web_sm')"
```

### Timeout errors

```elixir
# Increase timeout for very large texts
NLP.extract_entities(huge_text, %{timeout: 120_000})  # 2 minutes
```

### Empty results

```elixir
# Check if text is actually being passed
{:ok, result} = NLP.extract_entities("", %{})
# => %{"entities" => []}  # Empty input = empty output

# For debugging, use the demo script
mix run demo_nlp.exs
```

---

## 🧪 Testing Integration

```elixir
# Run demo script to verify everything works
mix run demo_nlp.exs

# Expected output:
# 🚀 Thunderline NLP Integration Demo
# 
# 📝 Test 1: Entity Extraction
# ✅ Success!
# Found 3 entities:
#   • Apple Inc. (ORG)
#   • U.K. (GPE)
#   • $1 billion (MONEY)
# 
# 📝 Test 2: Tokenization
# ✅ Success!
# Tokens: 10
#   • The (DET)
#   • quick (ADJ)
#   ...
```

---

## 🔜 Next Steps: Building the Ingestion Pipeline

Now that NLP is ready, here's how to build the full ingestion pipeline:

### 1. Install Magika (File Detection)

```bash
pip install magika
# or download binary: https://github.com/google/magika/releases
```

### 2. Use NLP in Your Pipeline

```elixir
defmodule MyApp.DocumentProcessor do
  alias Thunderline.Thunderbolt.CerebrosBridge.NLP
  
  def process_document(text) do
    # Extract key information
    {:ok, entities} = NLP.extract_entities(text)
    {:ok, sentiment} = NLP.analyze_sentiment(text)
    {:ok, tokens} = NLP.tokenize(text)
    
    # Package for storage/indexing
    %{
      text: text,
      entities: entities["entities"],
      sentiment: sentiment,
      keywords: extract_keywords(tokens["tokens"]),
      processed_at: DateTime.utc_now()
    }
  end
  
  defp extract_keywords(tokens) do
    tokens
    |> Enum.filter(fn t -> t["pos"] in ["NOUN", "PROPN", "VERB"] end)
    |> Enum.map(fn t -> t["lemma"] end)
    |> Enum.uniq()
  end
end
```

### 3. Create Voxel Schema

```elixir
# See INGESTION_PIPELINE_BLUEPRINT.md for full schema
defmodule Thunderline.Thunderblock.Voxel do
  use Ash.Resource,
    domain: Thunderline.Thunderblock,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :text, :string
    attribute :entities, :map      # Store NLP results
    attribute :tokens, :map
    attribute :sentiment, :map
    # ... more fields
  end
end
```

### 4. Build Ingestion Worker

```elixir
defmodule MyApp.IngestionWorker do
  use Oban.Worker
  alias Thunderline.Thunderbolt.CerebrosBridge.NLP
  
  @impl Oban.Worker
  def perform(%{args: %{"text" => text, "voxel_id" => voxel_id}}) do
    with {:ok, entities} <- NLP.extract_entities(text),
         {:ok, sentiment} <- NLP.analyze_sentiment(text),
         {:ok, tokens} <- NLP.tokenize(text) do
      # Update voxel with NLP results
      update_voxel(voxel_id, entities, sentiment, tokens)
    end
  end
end
```

---

## 📚 Resources

- **Full Status Report**: `docs/NLP_INTEGRATION_STATUS.md`
- **Pipeline Blueprint**: `INGESTION_PIPELINE_BLUEPRINT.md`
- **Spacy Documentation**: https://spacy.io/usage
- **Entity Types Reference**: https://spacy.io/api/annotation#named-entities
- **POS Tags Reference**: https://universaldependencies.org/u/pos/

---

## ✅ Verification Checklist

Before using NLP in production:

- [ ] Run demo script: `mix run demo_nlp.exs` ✅
- [ ] Verify Python 3.13 is installed
- [ ] Verify Spacy 3.8.3 is installed: `python3 -m spacy --version`
- [ ] Verify en_core_web_sm model is installed
- [ ] Test with your actual use case text
- [ ] Set appropriate timeouts for your text sizes
- [ ] Add error handling for edge cases
- [ ] Monitor performance in production

---

**Status**: 🚀 **READY TO USE**  
**Questions?** See `docs/NLP_INTEGRATION_STATUS.md` for complete details
