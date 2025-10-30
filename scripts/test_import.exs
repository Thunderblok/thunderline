#!/usr/bin/env elixir
# Test CSV import functionality

alias Thunderline.Thunderbolt.CerebrosDataExplorer
alias Thunderline.Thunderbolt.Domain

IO.puts("\n=== Testing CSV Import ===\n")

result = CerebrosDataExplorer.import_csv_as_dataset("/tmp/test_gutenberg.csv",
  name: "test_gutenberg_sample",
  description: "Test import of Gutenberg dataset",
  text_column: "text",
  metadata_columns: ["title", "author", "year"]
)

case result do
  {:ok, dataset} ->
    IO.puts("✅ Dataset created successfully!")
    IO.puts("\n📦 Dataset Details:")
    IO.puts("  ID: #{dataset.id}")
    IO.puts("  Name: #{dataset.name}")
    IO.puts("  Description: #{dataset.description}")
    IO.puts("  Status: #{dataset.status}")
    IO.puts("  Corpus path: #{dataset.corpus_path}")

    if File.exists?(dataset.corpus_path) do
      IO.puts("\n📄 JSONL Corpus File:")
      lines = File.read!(dataset.corpus_path) |> String.split("\n", trim: true)
      IO.puts("  Total entries: #{length(lines)}")

      IO.puts("\n🔍 First 2 entries:")
      lines
      |> Enum.take(2)
      |> Enum.with_index(1)
      |> Enum.each(fn {line, idx} ->
        case Jason.decode(line) do
          {:ok, entry} ->
            IO.puts("\n  Entry #{idx}:")
            IO.puts("    Text: #{String.slice(entry["text"], 0..70)}...")
            if entry["metadata"] do
              IO.puts("    Title: #{entry["metadata"]["title"]}")
              IO.puts("    Author: #{entry["metadata"]["author"]}")
            end
          {:error, _} ->
            IO.puts("    (failed to parse)")
        end
      end)
    else
      IO.puts("\n⚠️  JSONL file not found at: #{dataset.corpus_path}")
    end

  {:error, error} ->
    IO.puts("❌ Import failed!")
    IO.puts("\nError details:")
    IO.inspect(error, pretty: true)
end
