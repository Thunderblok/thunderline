#!/usr/bin/env elixir

# Test script for NLP integration via Pythonx
# Run: mix run test_nlp.exs

Mix.install([])

# Load the application
{:ok, _} = Application.ensure_all_started(:thunderline)

alias Thunderline.Thunderbolt.CerebrosBridge.NLP

IO.puts("\n🧪 Testing NLP Integration via Pythonx\n")
IO.puts("=" <> String.duplicate("=", 60))

# Test 1: Health Check
IO.puts("\n📊 Test 1: Health Check")
IO.puts("-" <> String.duplicate("-", 60))

case NLP.health_check() do
  {:ok, health} ->
    IO.puts("✅ NLP Service is healthy!")
    IO.inspect(health, label: "Health Status")

  {:error, reason} ->
    IO.puts("❌ NLP Service unavailable: #{inspect(reason)}")
    System.halt(1)
end

# Test 2: Entity Extraction
IO.puts("\n📊 Test 2: Named Entity Recognition")
IO.puts("-" <> String.duplicate("-", 60))

sample_text =
  "Apple Inc. was founded by Steve Jobs in Cupertino, California in 1976. Microsoft, Google, and Amazon are also major tech companies."

case NLP.extract_entities(sample_text) do
  {:ok, result} ->
    IO.puts("✅ Entity extraction successful!")
    IO.puts("\nText: #{result["text"]}")
    IO.puts("\nEntities found (#{result["entity_count"]}):")

    Enum.each(result["entities"], fn entity ->
      IO.puts(
        "  • #{entity["text"]} (#{entity["label"]}) at position #{entity["start"]}-#{entity["end"]}"
      )
    end)

    IO.puts("\nUnique labels: #{inspect(result["labels"])}")

  {:error, reason} ->
    IO.puts("❌ Entity extraction failed: #{inspect(reason)}")
end

# Test 3: Tokenization
IO.puts("\n📊 Test 3: Tokenization")
IO.puts("-" <> String.duplicate("-", 60))
simple_text = "The quick brown fox jumps over the lazy dog."

case NLP.tokenize(simple_text) do
  {:ok, result} ->
    IO.puts("✅ Tokenization successful!")
    IO.puts("\nText: #{result["text"]}")
    IO.puts("\nTokens (#{result["token_count"]}):")

    result["tokens"]
    # Show first 10 tokens
    |> Enum.take(10)
    |> Enum.each(fn token ->
      IO.puts(
        "  • #{token["text"]} | POS: #{token["pos"]} | Lemma: #{token["lemma"]} | Stop: #{token["is_stop"]}"
      )
    end)

  {:error, reason} ->
    IO.puts("❌ Tokenization failed: #{inspect(reason)}")
end

# Test 4: Sentiment Analysis
IO.puts("\n📊 Test 4: Sentiment Analysis")
IO.puts("-" <> String.duplicate("-", 60))

sentiment_texts = [
  "This is absolutely wonderful! I love it!",
  "This is terrible and awful. I hate it.",
  "The weather is okay today."
]

Enum.each(sentiment_texts, fn text ->
  case NLP.analyze_sentiment(text) do
    {:ok, result} ->
      sentiment = result["sentiment"]
      score = result["score"]

      emoji =
        case sentiment do
          "positive" -> "😊"
          "negative" -> "😞"
          _ -> "😐"
        end

      IO.puts("\n#{emoji} \"#{text}\"")
      IO.puts("   Sentiment: #{sentiment} (score: #{Float.round(score, 2)})")

    {:error, reason} ->
      IO.puts("❌ Sentiment analysis failed for \"#{text}\": #{inspect(reason)}")
  end
end)

# Test 5: Syntax Analysis
IO.puts("\n\n📊 Test 5: Syntax Analysis")
IO.puts("-" <> String.duplicate("-", 60))
syntax_text = "The big brown dog chased the small cat across the green field."

case NLP.analyze_syntax(syntax_text) do
  {:ok, result} ->
    IO.puts("✅ Syntax analysis successful!")
    IO.puts("\nText: #{result["text"]}")

    IO.puts("\nNoun Chunks:")

    Enum.each(result["noun_chunks"], fn chunk ->
      IO.puts("  • #{chunk["text"]} (root: #{chunk["root"]})")
    end)

    IO.puts("\nSentences (#{result["sentence_count"]}):")

    Enum.each(result["sentences"], fn sent ->
      IO.puts("  • #{sent["text"]} (root: #{sent["root"]})")
    end)

  {:error, reason} ->
    IO.puts("❌ Syntax analysis failed: #{inspect(reason)}")
end

# Test 6: Full Processing
IO.puts("\n\n📊 Test 6: Full NLP Processing Pipeline")
IO.puts("-" <> String.duplicate("-", 60))

full_text =
  "Elon Musk announced that Tesla will open a new factory in Berlin next year. This is exciting news for the electric vehicle industry!"

case NLP.process(full_text, include_tokens: false) do
  {:ok, result} ->
    IO.puts("✅ Full NLP processing successful!")
    IO.puts("\nText: #{result["text"]}")

    if result["entities"] do
      IO.puts("\nEntities: #{length(result["entities"])}")

      Enum.each(result["entities"], fn e ->
        IO.puts("  • #{e["text"]} (#{e["label"]})")
      end)
    end

    if result["sentiment"] do
      IO.puts(
        "\nSentiment: #{result["sentiment"]} (score: #{Float.round(result["sentiment_score"], 2)})"
      )
    end

    if result["noun_chunks"] do
      IO.puts("\nNoun Chunks: #{length(result["noun_chunks"])}")

      Enum.take(result["noun_chunks"], 5)
      |> Enum.each(fn chunk ->
        IO.puts("  • #{chunk["text"]}")
      end)
    end

    if result["sentences"] do
      IO.puts("\nSentences: #{length(result["sentences"])}")
    end

  {:error, reason} ->
    IO.puts("❌ Full processing failed: #{inspect(reason)}")
end

IO.puts("\n\n" <> String.duplicate("=", 62))
IO.puts("🎉 NLP Integration Tests Complete!")
IO.puts(String.duplicate("=", 62) <> "\n")
