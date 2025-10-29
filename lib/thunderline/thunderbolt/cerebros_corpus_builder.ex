defmodule Thunderline.Thunderbolt.CerebrosCorpusBuilder do
  @moduledoc """
  Builds training corpus CSVs from document uploads.

  Pipeline:
  1. Chunk documents into 512-char sequences
  2. Apply labels based on stage
  3. Generate 4 stage CSVs
  4. Merge into 11 final CSVs for training
  5. Output to /data/corpus_rack/<dataset_id>/
  """

  alias Thunderline.Thunderbolt.Resources.{TrainingDataset, DocumentUpload}
  require Logger

  @chunk_size 512
  @corpus_root_path "/data/corpus_rack"

  @doc """
  Build complete corpus from a frozen dataset.
  Returns {:ok, corpus_path} or {:error, reason}
  """
  def build_corpus(dataset_id) do
    with {:ok, dataset} <- get_dataset(dataset_id),
         {:ok, uploads} <- get_uploads(dataset_id),
         {:ok, corpus_path} <- ensure_corpus_directory(dataset_id),
         {:ok, _stage_files} <- generate_stage_csvs(uploads, corpus_path),
         {:ok, _merged_files} <- merge_corpus(corpus_path) do

      # Update dataset with corpus path
      TrainingDataset.set_corpus_path!(dataset, corpus_path)

      Logger.info("Corpus built successfully for dataset #{dataset_id}: #{corpus_path}")
      {:ok, corpus_path}
    else
      {:error, reason} = error ->
        Logger.error("Failed to build corpus for dataset #{dataset_id}: #{inspect(reason)}")
        error
    end
  end

  defp get_dataset(dataset_id) do
    case Ash.get(TrainingDataset, dataset_id) do
      {:ok, dataset} -> {:ok, dataset}
      {:error, _} -> {:error, :dataset_not_found}
    end
  end

  defp get_uploads(dataset_id) do
    case Ash.read(DocumentUpload, query: [filter: [training_dataset_id: dataset_id]]) do
      {:ok, uploads} -> {:ok, uploads}
      {:error, _} -> {:error, :failed_to_load_uploads}
    end
  end

  defp ensure_corpus_directory(dataset_id) do
    corpus_path = Path.join(@corpus_root_path, dataset_id)

    case File.mkdir_p(corpus_path) do
      :ok -> {:ok, corpus_path}
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp generate_stage_csvs(uploads, corpus_path) do
    stages = Enum.group_by(uploads, & &1.stage)

    stage_files =
      for stage <- 1..4 do
        stage_uploads = Map.get(stages, stage, [])
        filename = Path.join(corpus_path, "stage_#{stage}.csv")

        case write_stage_csv(stage, stage_uploads, filename) do
          :ok -> {stage, filename}
          {:error, reason} -> throw({:csv_write_error, stage, reason})
        end
      end

    {:ok, stage_files}
  catch
    {:csv_write_error, stage, reason} ->
      {:error, {:stage_csv_failed, stage, reason}}
  end

  defp write_stage_csv(stage, uploads, filename) do
    headers = ["input", "output", "label", "stage", "chunk_id", "source"]

    rows =
      uploads
      |> Enum.flat_map(fn upload ->
        chunk_document(upload, stage)
      end)

    csv_data = [headers | rows]
    |> CSV.encode()
    |> Enum.to_list()
    |> IO.iodata_to_binary()

    File.write(filename, csv_data)
  end

  defp chunk_document(upload, stage) do
    content = upload.content || ""
    labels = upload.labels || []

    content
    |> chunk_text(@chunk_size)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      [
        chunk,                           # input
        get_output_for_stage(stage),     # output (empty or template)
        Enum.join(labels, "|"),          # label
        Integer.to_string(stage),        # stage
        "#{upload.id}_#{idx}",           # chunk_id
        upload.filename                  # source
      ]
    end)
  end

  defp chunk_text(text, chunk_size) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&Enum.join/1)
  end

  defp get_output_for_stage(1), do: ""  # Reference docs - no output expected
  defp get_output_for_stage(2), do: ""  # Communication samples - responses stored separately
  defp get_output_for_stage(3), do: ""  # Instructions - examples stored separately
  defp get_output_for_stage(4), do: ""  # Test cases - eval data

  defp merge_corpus(corpus_path) do
    # Load all 4 stage CSVs
    stage_files = for stage <- 1..4, do: Path.join(corpus_path, "stage_#{stage}.csv")

    # Generate 11 merged CSVs as per spec:
    # - 4 original stage files (already written)
    # - 4 training corpus files (filtered/processed versions)
    # - 2 merge phase files (relevance filtered)
    # - 1 user upsampled file (augmented)

    merged_files = [
      write_training_corpus(corpus_path, stage_files),
      write_merge_phase(corpus_path, stage_files),
      write_upsampled(corpus_path, stage_files)
    ]
    |> List.flatten()

    {:ok, stage_files ++ merged_files}
  end

  defp write_training_corpus(corpus_path, stage_files) do
    # Training corpus: filtered versions of stage files
    for {stage_file, idx} <- Enum.with_index(stage_files, 1) do
      output_file = Path.join(corpus_path, "training_corpus_#{idx}.csv")

      # Simple copy for now - add filtering logic as needed
      File.cp!(stage_file, output_file)

      output_file
    end
  end

  defp write_merge_phase(corpus_path, _stage_files) do
    # Merge phase: combine and filter for relevance
    merge_files = [
      Path.join(corpus_path, "merge_phase_1.csv"),
      Path.join(corpus_path, "merge_phase_2.csv")
    ]

    for file <- merge_files do
      # Write empty CSVs with headers for now
      File.write!(file, "input,output,label,stage,chunk_id,source\n")
    end

    merge_files
  end

  defp write_upsampled(corpus_path, _stage_files) do
    # User upsampled: augmented dataset
    upsampled_file = Path.join(corpus_path, "user_upsampled.csv")
    File.write!(upsampled_file, "input,output,label,stage,chunk_id,source\n")

    [upsampled_file]
  end

  @doc """
  Get statistics about a corpus directory.
  """
  def corpus_stats(corpus_path) do
    csv_files = Path.wildcard(Path.join(corpus_path, "*.csv"))

    stats =
      csv_files
      |> Enum.map(fn file ->
        lines = file |> File.stream!() |> Enum.count()
        {Path.basename(file), lines - 1}  # Subtract header
      end)
      |> Map.new()

    {:ok, stats}
  end
end
