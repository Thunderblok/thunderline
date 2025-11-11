# Simple NLP Test - Works in Mix Project
# Tests the Spacy NLP integration via Pythonx

alias Thunderline.Thunderbolt.CerebrosBridge.NLP

IO.puts("\n🧪 Testing Spacy NLP Integration via Pythonx")
IO.puts(String.duplicate("=", 60))

# Wait for application to start
Process.sleep(2000)

# Test 1: Health Check
IO.puts("\n📊 Test 1: Health Check")
IO.puts(String.duplicate("-", 60))

case NLP.health_check() do
  {:ok, health} ->
    IO.puts("✅ NLP Service is healthy!")
    IO.puts("Health Status: #{inspect(health, pretty: true)}")

  {:error, error} ->
    IO.puts("❌ NLP Service unhealthy!")
    IO.puts("Error: #{inspect(error)}")
end

# Test 2: Named Entity Recognition
IO.puts("\n📊 Test 2: Named Entity Recognition")
IO.puts(String.duplicate("-", 60))

test_text = "Apple Inc. was founded by Steve Jobs in Cupertino, California on April 1, 1976."

case NLP.extract_entities(test_text) do
  {:ok, result} ->
    IO.puts("✅ Entity extraction successful!")
    IO.puts("Input text: #{test_text}")
    IO.puts("\nFound #{result["entity_count"]} entities:")

    if result["entities"] do
      Enum.each(result["entities"], fn entity ->
        IO.puts("  • #{entity["text"]} (#{entity["label"]}) [#{entity["start"]}:#{entity["end"]}]")
      end)
    end

  {:error, error} ->
    IO.puts("❌ Entity extraction failed!")
    IO.puts("Error: #{inspect(error)}")
end

# Test 3: Tokenization
IO.puts("\n📊 Test 3: Tokenization")
IO.puts(String.duplicate("-", 60))

test_sentence = "The quick brown fox jumps over the lazy dog."

case NLP.tokenize(test_sentence) do
  {:ok, result} ->
    IO.puts("✅ Tokenization successful!")
    IO.puts("Input: #{test_sentence}")
    IO.puts("\nTokens (showing first 10):")

    if result["tokens"] do
      result["tokens"]
      |> Enum.take(10)
      |> Enum.each(fn token ->
        IO.puts("  • #{token["text"]} | POS: #{token["pos"]} | Lemma: #{token["lemma"]} | Stop: #{token["is_stop"]}")
      end)
    end

  {:error, error} ->
    IO.puts("❌ Tokenization failed!")
    IO.puts("Error: #{inspect(error)}")
end

# Test 4: Sentiment Analysis
IO.puts("\n📊 Test 4: Sentiment Analysis")
IO.puts(String.duplicate("-", 60))

sentiments = [
  "This is absolutely wonderful and amazing!",
  "This is terrible and disappointing.",
  "The weather is okay today."
]

Enum.each(sentiments, fn text ->
  case NLP.analyze_sentiment(text) do
    {:ok, result} ->
      emoji =
        case result["sentiment"] do
          "positive" -> "😊"
          "negative" -> "😞"
          "neutral" -> "😐"
          _ -> "❓"
        end

      IO.puts("#{emoji} \"#{text}\"")
      IO.puts("   Sentiment: #{result["sentiment"]} (Score: #{result["score"]})")

    {:error, error} ->
      IO.puts("❌ Failed: #{text}")
      IO.puts("   Error: #{inspect(error)}")
  end
end)

# Test 5: Full Processing
IO.puts("\n📊 Test 5: Full NLP Processing")
IO.puts(String.duplicate("-", 60))

complex_text = "Elon Musk announced that Tesla will open a new factory in Berlin, Germany."

case NLP.process(complex_text,
       include_entities: true,
       include_tokens: false,
       include_sentiment: true,
       include_syntax: true
     ) do
  {:ok, result} ->
    IO.puts("✅ Full processing successful!")
    IO.puts("Input: #{complex_text}")

    if result["entities"] do
      IO.puts("\nEntities found: #{length(result["entities"])}")

      Enum.each(result["entities"], fn entity ->
        IO.puts("  • #{entity["text"]} (#{entity["label"]})")
      end)
    end

    if result["sentiment"] do
      IO.puts("\nSentiment: #{result["sentiment"]}")
    end

    if result["noun_chunks"] do
      IO.puts("\nNoun Chunks: #{length(result["noun_chunks"])}")

      Enum.each(result["noun_chunks"], fn chunk ->
        IO.puts("  • #{chunk["text"]}")
      end)
    end

  {:error, error} ->
    IO.puts("❌ Full processing failed!")
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("🎉 NLP Integration Tests Complete!")
IO.puts(String.duplicate("=", 60) <> "\n")
