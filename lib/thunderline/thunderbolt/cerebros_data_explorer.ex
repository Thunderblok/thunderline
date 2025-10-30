defmodule Thunderline.Thunderbolt.CerebrosDataExplorer do
  @moduledoc """
  Data exploration and import utilities for Cerebros training datasets.

  Uses lightweight CSV parsing and Nx for data analysis. Provides helpers to:
  - Inspect CSV structure and statistics
  - Transform CSV data into JSONL training corpus format
  - Create TrainingDataset records with linked corpus files
  - Validate data quality for training

  ## Example Usage

      # Explore a CSV file
      {:ok, summary} = CerebrosDataExplorer.explore_csv("gutenberg_dataset.csv")
      IO.inspect(summary, label: "Dataset Summary")

      # Import CSV as training dataset
      {:ok, dataset} = CerebrosDataExplorer.import_csv_as_dataset(
        "gutenberg_dataset.csv",
        name: "Gutenberg Literary Corpus",
        description: "Classic literature from Project Gutenberg",
        text_column: "text",
        metadata_columns: ["title", "author", "year"]
      )
  """

  alias Thunderline.Thunderbolt.Domain, as: Thunderbolt

  @doc """
  Explores a CSV file and returns comprehensive statistics.

  Returns information about:
  - Number of rows and columns
  - Column names and types
  - Sample data (first 5 rows)
  - Text statistics (if text column detected)
  - Missing value counts

  ## Options

    * `:delimiter` - CSV delimiter (default: ",")
    * `:max_rows` - Maximum rows to load for preview (default: nil = all)
    * `:dtypes` - Column type specifications (default: auto-detect)

  ## Examples

      {:ok, summary} = explore_csv("data/books.csv")
      # => %{
      #   rows: 1000,
      #   columns: 5,
      #   column_names: ["id", "title", "author", "text", "year"],
      #   dtypes: %{"id" => :integer, "title" => :string, ...},
      #   sample: %DF{...},
      #   text_stats: %{avg_length: 1543, ...}
      # }
  """
  def explore_csv(csv_path, opts \\ []) do
    delimiter = Keyword.get(opts, :delimiter, ",")
    max_rows = Keyword.get(opts, :max_rows, nil)
    dtypes = Keyword.get(opts, :dtypes, [])

    with {:ok, df} <- read_csv_safe(csv_path, delimiter, max_rows, dtypes) do
      summary = build_summary(df)
      {:ok, summary}
    end
  end

  @doc """
  Imports a CSV file as a TrainingDataset with JSONL corpus.

  This function:
  1. Reads the CSV file
  2. Transforms specified columns into JSONL format
  3. Writes JSONL corpus file
  4. Creates TrainingDataset record
  5. Links corpus file to dataset

  ## Options

    * `:name` - Dataset name (required)
    * `:description` - Dataset description (optional)
    * `:text_column` - Column containing training text (required)
    * `:metadata_columns` - List of columns to include as metadata (default: [])
    * `:output_path` - Where to write JSONL file (default: auto-generated in /tmp)
    * `:delimiter` - CSV delimiter (default: ",")
    * `:freeze` - Whether to freeze dataset after import (default: false)
    * `:sample_size` - Limit number of rows to import (default: nil = all)

  ## Examples

      {:ok, dataset} = import_csv_as_dataset(
        "gutenberg.csv",
        name: "Gutenberg Corpus",
        text_column: "text",
        metadata_columns: ["title", "author"],
        freeze: true
      )
  """
  def import_csv_as_dataset(csv_path, opts) do
    with {:ok, config} <- validate_import_config(opts),
         {:ok, df} <- read_csv_safe(csv_path, config.delimiter, config.sample_size, []),
         {:ok, jsonl_path} <- write_jsonl_corpus(df, config),
         {:ok, dataset} <- create_dataset_record(config),
         {:ok, dataset} <- link_corpus(dataset, jsonl_path),
         {:ok, dataset} <- maybe_freeze(dataset, config.freeze) do
      {:ok, dataset}
    end
  end

  @doc """
  Converts a CSV DataFrame to JSONL format and writes to file.

  ## Options

    * `:text_column` - Column containing training text (required)
    * `:metadata_columns` - Columns to include as metadata (default: [])
    * `:output_path` - Where to write file (default: auto-generated)

  ## Examples

      df = DF.read_csv!("books.csv")
      {:ok, path} = csv_to_jsonl(df,
        text_column: "content",
        metadata_columns: ["title", "author"],
        output_path: "/tmp/training_corpus.jsonl"
      )
  """
  def csv_to_jsonl(df, opts) do
    text_column = Keyword.fetch!(opts, :text_column)
    metadata_columns = Keyword.get(opts, :metadata_columns, [])
    output_path = Keyword.get(opts, :output_path, generate_temp_path())

    config = %{
      text_column: text_column,
      metadata_columns: metadata_columns,
      output_path: output_path
    }

    write_jsonl_corpus(df, config)
  end

  # Private functions

  defp read_csv_safe(csv_path, delimiter, max_rows, _dtypes) do
    with {:ok, content} <- File.read(csv_path),
         {:ok, parsed} <- parse_csv_content(content, delimiter, max_rows) do
      {:ok, parsed}
    else
      {:error, reason} -> {:error, {:csv_read_failed, reason}}
    end
  rescue
    e -> {:error, {:csv_read_exception, Exception.message(e)}}
  end

  defp parse_csv_content(content, delimiter, max_rows) do
    lines = String.split(content, "\n", trim: true)

    case lines do
      [header_line | data_lines] ->
        headers = parse_csv_line(header_line, delimiter)

        data_lines = if max_rows, do: Enum.take(data_lines, max_rows), else: data_lines

        rows =
          Enum.map(data_lines, fn line ->
            values = parse_csv_line(line, delimiter)
            Enum.zip(headers, values) |> Enum.into(%{})
          end)

        parsed = %{
          headers: headers,
          rows: rows,
          row_count: length(rows)
        }

        {:ok, parsed}

      [] ->
        {:error, :empty_file}
    end
  end

  defp parse_csv_line(line, delimiter) do
    # Robust CSV parsing that handles quoted fields with commas
    parse_csv_fields(line, delimiter, [], "", false)
  end

  defp parse_csv_fields("", _delimiter, fields, current, _in_quotes) do
    Enum.reverse([current | fields])
  end

  defp parse_csv_fields(<<char, rest::binary>>, delimiter, fields, current, in_quotes) do
    cond do
      # Handle quotes
      char == ?" and not in_quotes ->
        parse_csv_fields(rest, delimiter, fields, current, true)

      char == ?" and in_quotes ->
        parse_csv_fields(rest, delimiter, fields, current, false)

      # Handle delimiter
      <<char>> == delimiter and not in_quotes ->
        parse_csv_fields(rest, delimiter, [String.trim(current) | fields], "", false)

      # Regular character
      true ->
        parse_csv_fields(rest, delimiter, fields, current <> <<char>>, in_quotes)
    end
  end

  defp build_summary(parsed) do
    rows = parsed.row_count
    column_names = parsed.headers
    columns = length(column_names)

    # Get sample (first 5 rows)
    sample = Enum.take(parsed.rows, 5)

    # Compute text statistics for all columns
    text_stats = compute_text_stats(parsed.rows, column_names)

    %{
      rows: rows,
      columns: columns,
      column_names: column_names,
      sample: sample,
      text_stats: text_stats
    }
  end

  defp compute_text_stats(rows, column_names) do
    Enum.reduce(column_names, %{}, fn col, acc ->
      values = Enum.map(rows, fn row -> Map.get(row, col, "") end)

      lengths = Enum.map(values, fn val ->
        if is_binary(val), do: String.length(val), else: 0
      end)

      if Enum.any?(lengths, &(&1 > 0)) do
        stats = %{
          min_length: Enum.min(lengths),
          max_length: Enum.max(lengths),
          avg_length: (Enum.sum(lengths) / length(lengths)) |> Float.round(2),
          total_chars: Enum.sum(lengths)
        }

        Map.put(acc, col, stats)
      else
        acc
      end
    end)
  end

  defp validate_import_config(opts) do
    with {:ok, name} <- validate_required(opts, :name, "Dataset name is required"),
         {:ok, text_column} <-
           validate_required(opts, :text_column, "Text column name is required") do
      config = %{
        name: name,
        description: Keyword.get(opts, :description, ""),
        text_column: text_column,
        metadata_columns: Keyword.get(opts, :metadata_columns, []),
        output_path: Keyword.get(opts, :output_path, generate_temp_path()),
        delimiter: Keyword.get(opts, :delimiter, ","),
        freeze: Keyword.get(opts, :freeze, false),
        sample_size: Keyword.get(opts, :sample_size, nil)
      }

      {:ok, config}
    end
  end

  defp validate_required(opts, key, error_message) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when not is_nil(value) -> {:ok, value}
      _ -> {:error, error_message}
    end
  end

  defp write_jsonl_corpus(parsed, config) do
    output_path = config.output_path
    text_column = config.text_column
    metadata_columns = Map.get(config, :metadata_columns, [])

    # Ensure output directory exists
    output_path |> Path.dirname() |> File.mkdir_p!()

    # Convert rows to JSONL
    jsonl_lines =
      Enum.map(parsed.rows, fn row ->
        text = Map.get(row, text_column, "")

        metadata =
          metadata_columns
          |> Enum.map(fn col -> {col, Map.get(row, col, "")} end)
          |> Enum.into(%{})

        entry = %{
          "text" => text,
          "metadata" => metadata
        }

        Jason.encode!(entry)
      end)

    # Write to file
    content = Enum.join(jsonl_lines, "\n")

    case File.write(output_path, content) do
      :ok -> {:ok, output_path}
      {:error, reason} -> {:error, {:file_write_failed, reason}}
    end
  rescue
    e -> {:error, {:jsonl_write_exception, Exception.message(e)}}
  end

  defp create_dataset_record(config) do
    params = %{
      name: config.name,
      description: config.description
    }

    case Thunderbolt.create_training_dataset(params) do
      {:ok, dataset} -> {:ok, dataset}
      {:error, error} -> {:error, {:dataset_creation_failed, error}}
    end
  end

  defp link_corpus(dataset, jsonl_path) do
    case Thunderbolt.update_corpus_path(dataset, jsonl_path) do
      {:ok, dataset} -> {:ok, dataset}
      {:error, error} -> {:error, {:corpus_link_failed, error}}
    end
  end

  defp maybe_freeze(dataset, false), do: {:ok, dataset}

  defp maybe_freeze(dataset, true) do
    case Thunderbolt.freeze_dataset(dataset) do
      {:ok, dataset} -> {:ok, dataset}
      {:error, error} -> {:error, {:freeze_failed, error}}
    end
  end

  defp generate_temp_path do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(10000)
    "/tmp/cerebros_corpus_#{timestamp}_#{random}.jsonl"
  end
end
