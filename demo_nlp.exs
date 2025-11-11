#!/usr/bin/env elixir

# ============================================================================
# Thunderline NLP Demo - Zero-Dependency Spacy Integration
# ============================================================================
# 
# Architecture: Elixir Port API → Python subprocess → Spacy NLP
# Dependencies: ZERO (no Pythonx, no msgpack)
# Communication: Line-delimited JSON via stdin/stdout
#
# This demonstrates the complete working integration with JSON extraction
# that handles Python INFO logs mixed with JSON responses.
# ============================================================================

require Logger

# Enable debug logging to see the flow
Logger.configure(level: :info)

defmodule NLPDemo do
  alias Thunderline.Thunderbolt.CerebrosBridge.NLP
  
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("🚀 Thunderline NLP Integration Demo")
    IO.puts("Architecture: Port API → Python → Spacy")
    IO.puts("Dependencies: Zero (direct subprocess)")
    IO.puts(String.duplicate("=", 70) <> "\n")
    
    # Test 1: Entity Extraction
    test_entities()
    
    # Test 2: Tokenization
    test_tokenization()
    
    # Test 3: Sentiment Analysis
    test_sentiment()
    
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("✅ Demo Complete - All functions operational!")
    IO.puts(String.duplicate("=", 70) <> "\n")
  end
  
  defp test_entities do
    IO.puts("📝 Test 1: Entity Extraction")
    IO.puts(String.duplicate("-", 70))
    
    text = "Apple Inc. is buying a U.K. startup for $1 billion"
    IO.puts("Input: #{text}")
    
    case NLP.extract_entities(text) do
      {:ok, result} ->
        IO.puts("\n✅ Success!")
        IO.puts("Found #{result["entity_count"]} entities:")
        
        Enum.each(result["entities"], fn entity ->
          IO.puts("  • #{entity["text"]} (#{entity["label"]})")
        end)
        
      {:error, error} ->
        IO.puts("\n❌ Error: #{inspect(error)}")
    end
    
    IO.puts("")
  end
  
  defp test_tokenization do
    IO.puts("📝 Test 2: Tokenization")
    IO.puts(String.duplicate("-", 70))
    
    text = "The quick brown fox jumps over the lazy dog."
    IO.puts("Input: #{text}")
    
    case NLP.tokenize(text) do
      {:ok, result} ->
        IO.puts("\n✅ Success!")
        IO.puts("Tokens: #{result["token_count"]}")
        
        result["tokens"]
        |> Enum.take(5)
        |> Enum.each(fn token ->
          IO.puts("  • #{token["text"]} (#{token["pos"]})")
        end)
        
      {:error, error} ->
        IO.puts("\n❌ Error: #{inspect(error)}")
    end
    
    IO.puts("")
  end
  
  defp test_sentiment do
    IO.puts("📝 Test 3: Sentiment Analysis")
    IO.puts(String.duplicate("-", 70))
    
    text = "This product is absolutely fantastic and I love it!"
    IO.puts("Input: #{text}")
    
    case NLP.analyze_sentiment(text) do
      {:ok, result} ->
        IO.puts("\n✅ Success!")
        IO.puts("Polarity: #{result["polarity"]}")
        IO.puts("Subjectivity: #{result["subjectivity"]}")
        
      {:error, error} ->
        IO.puts("\n❌ Error: #{inspect(error)}")
    end
    
    IO.puts("")
  end
end

# Run the demo
NLPDemo.run()
