#!/usr/bin/env elixir
#
# Cerebros Data Explorer - Interactive CSV exploration script
#
# Usage:
#   mix run scripts/explore_data.exs path/to/file.csv
#
# This script helps you explore CSV files before importing them as training datasets.
# It shows structure, statistics, and helps you decide which columns to use.

alias Thunderline.Thunderbolt.CerebrosDataExplorer

defmodule ExploreHelper do
  def main(args) do
    case args do
      [] ->
        IO.puts("""
        Usage: mix run scripts/explore_data.exs <csv_file> [options]

        Options:
          --sample N       Show first N rows (default: 5)
          --import         Import as training dataset (interactive)
          --stats          Show detailed statistics only

        Examples:
          mix run scripts/explore_data.exs data/gutenberg.csv
          mix run scripts/explore_data.exs data/gutenberg.csv --sample 10
          mix run scripts/explore_data.exs data/gutenberg.csv --import
        """)

        System.halt(1)

      [csv_path | opts] ->
        explore(csv_path, parse_opts(opts))
    end
  end

  defp parse_opts(opts) do
    Enum.reduce(opts, %{sample: 5, import: false, stats: false}, fn
      "--sample", acc -> Map.put(acc, :next_is_sample, true)
      "--import", acc -> Map.put(acc, :import, true)
      "--stats", acc -> Map.put(acc, :stats, true)
      value, %{next_is_sample: true} = acc ->
        acc
        |> Map.delete(:next_is_sample)
        |> Map.put(:sample, String.to_integer(value))
      _, acc -> acc
    end)
  end

  defp explore(csv_path, opts) do
    IO.puts("\n=== Cerebros Data Explorer ===\n")
    IO.puts("Analyzing: #{csv_path}\n")

    case CerebrosDataExplorer.explore_csv(csv_path) do
      {:ok, summary} ->
        print_summary(summary, opts)

        if opts.import do
          interactive_import(csv_path, summary)
        end

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp print_summary(summary, _opts) do
    IO.puts("📊 Dataset Overview:")
    IO.puts("  Rows: #{summary.rows}")
    IO.puts("  Columns: #{summary.columns}")
    IO.puts("\n📋 Columns:")

    Enum.each(summary.column_names, fn col ->
      IO.puts("  - #{col}")
    end)

    if map_size(summary.text_stats) > 0 do
      IO.puts("\n📝 Text Column Statistics:")
      Enum.each(summary.text_stats, fn {col, stats} ->
        IO.puts("\n  #{col}:")
        IO.puts("    Min length: #{stats.min_length}")
        IO.puts("    Max length: #{stats.max_length}")
        IO.puts("    Avg length: #{stats.avg_length}")
        IO.puts("    Total chars: #{format_number(stats.total_chars)}")
      end)
    end

    IO.puts("\n🔍 Sample Data (first 5 rows):")
    Enum.with_index(summary.sample, 1)
    |> Enum.each(fn {row, idx} ->
      IO.puts("\n  Row #{idx}:")
      Enum.each(row, fn {k, v} ->
        display_val = if String.length(v) > 60, do: String.slice(v, 0, 57) <> "...", else: v
        IO.puts("    #{k}: #{display_val}")
      end)
    end)
  end

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}K"
  end

  defp format_number(num), do: to_string(num)

  defp interactive_import(csv_path, summary) do
    IO.puts("\n\n=== Interactive Import ===\n")

    # Ask for dataset name
    dataset_name = IO.gets("Enter dataset name: ") |> String.trim()

    # Ask for description
    description = IO.gets("Enter description (optional): ") |> String.trim()

    # Show text columns and ask which to use
    text_columns = summary.text_stats |> Map.keys()

    IO.puts("\nAvailable text columns:")
    Enum.with_index(text_columns, 1)
    |> Enum.each(fn {col, idx} ->
      stats = summary.text_stats[col]
      IO.puts("  #{idx}. #{col} (avg: #{stats.avg_length} chars)")
    end)

    text_col_idx =
      IO.gets("\nSelect text column number: ")
      |> String.trim()
      |> String.to_integer()

    text_column = Enum.at(text_columns, text_col_idx - 1)

    # Ask for metadata columns
    IO.puts("\nSelect metadata columns (comma-separated, or press Enter to skip):")
    IO.puts("Available: #{Enum.join(summary.column_names -- [text_column], ", ")}")

    metadata_input = IO.gets("> ") |> String.trim()

    metadata_columns =
      if metadata_input == "" do
        []
      else
        metadata_input
        |> String.split(",")
        |> Enum.map(&String.trim/1)
      end

    # Confirm
    IO.puts("\n📋 Import Configuration:")
    IO.puts("  Name: #{dataset_name}")
    IO.puts("  Description: #{description}")
    IO.puts("  Text column: #{text_column}")
    IO.puts("  Metadata columns: #{inspect(metadata_columns)}")

    confirm = IO.gets("\nProceed with import? (y/n): ") |> String.trim() |> String.downcase()

    if confirm == "y" do
      perform_import(csv_path, dataset_name, description, text_column, metadata_columns)
    else
      IO.puts("Import cancelled.")
    end
  end

  defp perform_import(csv_path, name, description, text_column, metadata_columns) do
    IO.puts("\n🚀 Importing dataset...")

    opts = [
      name: name,
      description: description,
      text_column: text_column,
      metadata_columns: metadata_columns,
      freeze: false
    ]

    case CerebrosDataExplorer.import_csv_as_dataset(csv_path, opts) do
      {:ok, dataset} ->
        IO.puts("\n✅ Dataset imported successfully!")
        IO.puts("  ID: #{dataset.id}")
        IO.puts("  Name: #{dataset.name}")
        IO.puts("  Corpus path: #{dataset.corpus_path}")
        IO.puts("  Status: #{dataset.status}")
        IO.puts("\nYou can now create a training job with:")
        IO.puts("  Thunderbolt.create_training_job(%{")
        IO.puts("    training_dataset_id: \"#{dataset.id}\",")
        IO.puts("    model_id: \"gpt-4o-mini\",")
        IO.puts("    hyperparameters: %{")
        IO.puts("      batch_size: 1,")
        IO.puts("      learning_rate_multiplier: 1.8,")
        IO.puts("      n_epochs: 3")
        IO.puts("    }")
        IO.puts("  })")

      {:error, reason} ->
        IO.puts("\n❌ Import failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

# Run the script
ExploreHelper.main(System.argv())
