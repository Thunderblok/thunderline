defmodule Thunderline.Thundergate.Magika do
  @moduledoc """
  File classification wrapper for Google's Magika CLI.

  Provides fast, AI-powered content-type detection with automatic fallback
  to extension-based detection on low confidence or CLI failure.

  ## Configuration

  Set in `config/runtime.exs`:

      config :thunderline, Thunderline.Thundergate.Magika,
        cli_path: System.get_env("MAGIKA_CLI_PATH", "magika"),
        confidence_threshold: 0.85,
        timeout: 5_000

  ## Events Emitted

  - `system.ingest.classified` - File successfully classified
  - Telemetry: `[:thunderline, :thundergate, :magika, :classify, :start | :stop | :error]`

  ## Examples

      # Classify from file path
      {:ok, result} = Magika.classify_file("/tmp/document.pdf")
      # => %{content_type: "application/pdf", confidence: 0.98, ...}

      # Classify from bytes
      {:ok, result} = Magika.classify_bytes(file_bytes, "report.docx")

      # Low confidence falls back to extension detection
      {:ok, result} = Magika.classify_file("unknown.xyz")
      # => %{content_type: "application/octet-stream", confidence: 0.0, fallback: :extension}
  """

  require Logger
  alias Thunderline.Event

  @default_config [
    cli_path: "magika",
    confidence_threshold: 0.85,
    timeout: 5_000
  ]

  # Extension to MIME type mapping for fallback
  @extension_map %{
    ".pdf" => "application/pdf",
    ".doc" => "application/msword",
    ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls" => "application/vnd.ms-excel",
    ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".ppt" => "application/vnd.ms-powerpoint",
    ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".txt" => "text/plain",
    ".csv" => "text/csv",
    ".json" => "application/json",
    ".xml" => "application/xml",
    ".html" => "text/html",
    ".htm" => "text/html",
    ".css" => "text/css",
    ".js" => "application/javascript",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".svg" => "image/svg+xml",
    ".webp" => "image/webp",
    ".mp3" => "audio/mpeg",
    ".mp4" => "video/mp4",
    ".avi" => "video/x-msvideo",
    ".zip" => "application/zip",
    ".tar" => "application/x-tar",
    ".gz" => "application/gzip",
    ".7z" => "application/x-7z-compressed"
  }

  @doc """
  Classifies a file at the given path using Magika CLI.

  ## Options

  - `:correlation_id` - UUID for event correlation (auto-generated if not provided)
  - `:causation_id` - UUID of the causing event (defaults to correlation_id)
  - `:emit_event?` - Whether to emit `system.ingest.classified` event (default: true)

  ## Returns

  - `{:ok, result}` - Classification successful
  - `{:error, reason}` - Classification failed

  Result map contains:
  - `:content_type` - Detected MIME type
  - `:confidence` - Confidence score (0.0-1.0)
  - `:label` - Magika's label for the file type
  - `:sha256` - SHA-256 hash of the file
  - `:filename` - Base filename
  - `:fallback` - (optional) `:extension` if fallback was used
  """
  @spec classify_file(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def classify_file(path, opts \\ []) when is_binary(path) do
    correlation_id = Keyword.get_lazy(opts, :correlation_id, &Thunderline.UUID.v7/0)
    causation_id = Keyword.get(opts, :causation_id, correlation_id)
    emit_event? = Keyword.get(opts, :emit_event?, true)

    metadata = %{
      path: path,
      filename: Path.basename(path),
      correlation_id: correlation_id
    }

    :telemetry.execute(
      [:thunderline, :thundergate, :magika, :classify, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start_time = System.monotonic_time()

    result =
      with {:ok, file_bytes} <- File.read(path),
           {:ok, magika_result} <- call_magika_cli(path),
           {:ok, classification} <- parse_magika_result(magika_result, path, file_bytes) do
        # Check confidence threshold
        config = Application.get_env(:thunderline, __MODULE__, @default_config)
        threshold = Keyword.get(config, :confidence_threshold, 0.85)

        final_result =
          if classification.confidence >= threshold do
            classification
          else
            Logger.warning(
              "Magika confidence #{classification.confidence} below threshold #{threshold}, using extension fallback",
              path: path
            )

            fallback_from_extension(path, file_bytes)
          end

        if emit_event? do
          emit_classified_event(final_result, correlation_id, causation_id)
        end

        {:ok, final_result}
      else
        {:error, :enoent} ->
          error = {:file_not_found, path}
          emit_error_telemetry(error, start_time, metadata)
          {:error, error}

        {:error, reason} = _error ->
          Logger.warning("Magika CLI failed, using extension fallback",
            reason: inspect(reason),
            path: path
          )

          # Fallback to extension detection
          case File.read(path) do
            {:ok, file_bytes} ->
              result = fallback_from_extension(path, file_bytes)

              if emit_event? do
                emit_classified_event(result, correlation_id, causation_id)
              end

              emit_stop_telemetry(start_time, metadata, result)
              {:ok, result}

            {:error, file_error} ->
              final_error = {:file_read_error, file_error}
              emit_error_telemetry(final_error, start_time, metadata)
              {:error, final_error}
          end
      end

    case result do
      {:ok, classification} ->
        emit_stop_telemetry(start_time, metadata, classification)
        {:ok, classification}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Classifies bytes by writing to a temporary file and calling Magika.

  Automatically cleans up the temporary file after classification.

  ## Options

  Same as `classify_file/2`.

  ## Examples

      bytes = File.read!("document.pdf")
      {:ok, result} = Magika.classify_bytes(bytes, "document.pdf")
  """
  @spec classify_bytes(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def classify_bytes(bytes, filename, opts \\ []) when is_binary(bytes) and is_binary(filename) do
    # Create temporary file with original extension preserved
    ext = Path.extname(filename)
    tmp_path = Path.join(System.tmp_dir!(), "magika_#{Thunderline.UUID.v7()}#{ext}")

    try do
      :ok = File.write!(tmp_path, bytes)
      classify_file(tmp_path, opts)
    after
      File.rm(tmp_path)
    end
  end

  # Private functions

  defp call_magika_cli(path) do
    config = Application.get_env(:thunderline, __MODULE__, @default_config)
    cli_path = Keyword.get(config, :cli_path, "magika")
    timeout = Keyword.get(config, :timeout, 5_000)

    args = ["--json", "--output-score", path]

    case System.cmd(cli_path, args, stderr_to_stdout: true, timeout: timeout) do
      {output, 0} ->
        {:ok, output}

      {error_output, exit_code} ->
        Logger.debug("Magika CLI failed",
          exit_code: exit_code,
          output: error_output,
          path: path
        )

        {:error, {:cli_failed, exit_code, error_output}}
    end
  rescue
    e in ErlangError ->
      if e.original == :enoent do
        {:error, :magika_not_installed}
      else
        {:error, {:system_cmd_error, e}}
      end
  end

  defp parse_magika_result(json_output, path, file_bytes) do
    case Jason.decode(json_output) do
      {:ok, %{"output" => %{"label" => label, "score" => score}} = result} ->
        content_type = result["output"]["mime_type"] || magika_label_to_mime(label)
        sha256 = :crypto.hash(:sha256, file_bytes) |> Base.encode16(case: :lower)

        classification = %{
          content_type: content_type,
          confidence: score,
          label: label,
          sha256: sha256,
          filename: Path.basename(path)
        }

        {:ok, classification}

      {:ok, _other} ->
        {:error, :invalid_magika_output}

      {:error, json_error} ->
        {:error, {:json_decode_error, json_error}}
    end
  end

  defp fallback_from_extension(path, file_bytes) do
    ext = Path.extname(path) |> String.downcase()
    content_type = Map.get(@extension_map, ext, "application/octet-stream")
    sha256 = :crypto.hash(:sha256, file_bytes) |> Base.encode16(case: :lower)

    %{
      content_type: content_type,
      confidence: 0.0,
      label: "unknown",
      sha256: sha256,
      filename: Path.basename(path),
      fallback: :extension
    }
  end

  defp magika_label_to_mime(label) do
    # Common Magika labels to MIME types
    case label do
      "pdf" -> "application/pdf"
      "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "txt" -> "text/plain"
      "html" -> "text/html"
      "json" -> "application/json"
      "xml" -> "application/xml"
      "png" -> "image/png"
      "jpeg" -> "image/jpeg"
      "gif" -> "image/gif"
      "zip" -> "application/zip"
      _ -> "application/octet-stream"
    end
  end

  defp emit_classified_event(classification, correlation_id, causation_id) do
    event_attrs = %{
      type: "system.ingest.classified",
      source: "thundergate.magika",
      data: %{
        content_type: classification.content_type,
        confidence: classification.confidence,
        sha256: classification.sha256,
        filename: classification.filename,
        label: classification.label
      },
      metadata: %{
        correlation_id: correlation_id,
        causation_id: causation_id
      }
    }

    if Map.has_key?(classification, :fallback) do
      event_attrs = put_in(event_attrs.metadata.fallback, classification.fallback)
    end

    case Event.new(event_attrs) do
      {:ok, event} ->
        Thunderline.EventBus.publish_event(event)

      {:error, reason} ->
        Logger.error("Failed to create classified event", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp emit_stop_telemetry(start_time, metadata, classification) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:thunderline, :thundergate, :magika, :classify, :stop],
      %{duration: duration},
      Map.merge(metadata, %{
        content_type: classification.content_type,
        confidence: classification.confidence
      })
    )
  end

  defp emit_error_telemetry(error, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:thunderline, :thundergate, :magika, :classify, :error],
      %{duration: duration},
      Map.merge(metadata, %{error: error})
    )
  end
end
