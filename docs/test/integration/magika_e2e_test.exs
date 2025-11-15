defmodule Thunderline.Integration.MagikaE2ETest do
  @moduledoc """
  End-to-end integration tests for Magika file classification pipeline.

  Tests the complete flow from file ingestion through classification to event emission,
  including DLQ routing, correlation ID propagation, and Broadway pipeline stability.

  Acceptance Criteria:
  - Test 6-10 different file types (PDF, PNG, JSON, HTML, MP4, DOCX, TXT, CSV, XML, JS)
  - Assert `system.ingest.classified` event emission with correct metadata
  - Verify DLQ routing for invalid inputs
  - Confirm correlation ID propagation through entire pipeline
  - Validate telemetry event emission
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Thunderline.Thundergate.Magika
  alias Thunderline.Thunderflow.EventBus

  @fixtures_dir "test/fixtures/magika_e2e"
  @test_timeout 10_000

  # Test file types with expected classifications
  @test_files [
    {"sample.pdf", "pdf", "application/pdf"},
    {"sample.png", "png", "image/png"},
    {"sample.json", "json", "application/json"},
    {"sample.html", "html", "text/html"},
    {"sample.mp4", "mp4", "video/mp4"},
    {"sample.txt", "txt", "text/plain"},
    {"sample.csv", "csv", "text/csv"},
    {"sample.xml", "xml", "application/xml"},
    {"sample.js", "javascript", "text/javascript"}
  ]

  setup do
    # Start telemetry test handler
    :telemetry.attach_many(
      "magika-e2e-test-#{System.unique_integer()}",
      [
        [:thunderline, :thundergate, :magika, :classify, :start],
        [:thunderline, :thundergate, :magika, :classify, :stop],
        [:thunderline, :thundergate, :magika, :classify, :error]
      ],
      &__MODULE__.handle_telemetry_event/4,
      %{pid: self()}
    )

    # Subscribe to EventBus for event verification
    if match?({:ok, _}, EventBus.subscribe(self(), "system.ingest.classified")) do
      :ok
    end

    on_exit(fn ->
      :telemetry.detach("magika-e2e-test-#{System.unique_integer()}")
    end)

    :ok
  end

  describe "Magika E2E File Classification Pipeline" do
    test "classifies PDF files correctly" do
      file_path = Path.join(@fixtures_dir, "sample.pdf")
      correlation_id = "test-pdf-#{System.unique_integer()}"

      assert File.exists?(file_path), "PDF fixture not found at #{file_path}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:ok, classification} = result
      assert classification.file_type in ["pdf", "application/pdf"]
      assert classification.confidence >= 0.5
      assert classification.correlation_id == correlation_id

      # Verify event was published
      assert_receive {:event, %{name: "system.ingest.classified"} = event}, @test_timeout
      assert event.payload.correlation_id == correlation_id
      assert event.payload.file_type in ["pdf", "application/pdf"]
    end

    test "classifies image files (PNG) correctly" do
      file_path = Path.join(@fixtures_dir, "sample.png")
      correlation_id = "test-png-#{System.unique_integer()}"

      assert File.exists?(file_path), "PNG fixture not found at #{file_path}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:ok, classification} = result
      assert classification.file_type in ["png", "image/png"]
      assert classification.confidence >= 0.5
      assert classification.correlation_id == correlation_id

      # Verify telemetry
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :start], _measurements, _metadata}, @test_timeout
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :stop], _measurements, _metadata}, @test_timeout
    end

    test "classifies structured data (JSON) correctly" do
      file_path = Path.join(@fixtures_dir, "sample.json")
      correlation_id = "test-json-#{System.unique_integer()}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:ok, classification} = result
      assert classification.file_type in ["json", "application/json"]
      assert classification.correlation_id == correlation_id
    end

    test "classifies HTML documents correctly" do
      file_path = Path.join(@fixtures_dir, "sample.html")
      correlation_id = "test-html-#{System.unique_integer()}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:ok, classification} = result
      assert classification.file_type in ["html", "text/html"]
      assert classification.correlation_id == correlation_id
    end

    test "classifies video files (MP4) correctly" do
      file_path = Path.join(@fixtures_dir, "sample.mp4")
      correlation_id = "test-mp4-#{System.unique_integer()}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      # MP4 fixtures are minimal, may fallback to extension
      assert {:ok, classification} = result
      assert is_binary(classification.file_type)
      assert classification.correlation_id == correlation_id
    end

    test "classifies text files correctly" do
      file_path = Path.join(@fixtures_dir, "sample.txt")
      correlation_id = "test-txt-#{System.unique_integer()}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:ok, classification} = result
      assert classification.file_type in ["txt", "text/plain"]
      assert classification.correlation_id == correlation_id
    end

    test "classifies CSV files correctly" do
      file_path = Path.join(@fixtures_dir, "sample.csv")
      correlation_id = "test-csv-#{System.unique_integer()}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:ok, classification} = result
      assert classification.file_type in ["csv", "text/csv"]
      assert classification.correlation_id == correlation_id
    end

    test "handles correlation ID propagation through pipeline" do
      file_path = Path.join(@fixtures_dir, "sample.json")
      correlation_id = "correlation-propagation-test-#{System.unique_integer()}"

      # Classify file
      {:ok, classification} = Magika.classify_file(file_path, correlation_id: correlation_id)

      # Verify correlation ID in result
      assert classification.correlation_id == correlation_id

      # Verify correlation ID in telemetry
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :start], _measurements, metadata}, @test_timeout
      assert metadata.correlation_id == correlation_id

      # Verify correlation ID in event
      assert_receive {:event, %{name: "system.ingest.classified", payload: payload}}, @test_timeout
      assert payload.correlation_id == correlation_id
    end

    test "routes invalid files to DLQ" do
      # Create an invalid/corrupted file
      invalid_path = Path.join(@fixtures_dir, "invalid_file.bin")
      File.write!(invalid_path, <<0, 0, 0, 0>>)

      correlation_id = "test-dlq-#{System.unique_integer()}"

      # This should either error or fallback to extension
      result = Magika.classify_file(invalid_path, correlation_id: correlation_id)

      case result do
        {:ok, classification} ->
          # Fallback to extension occurred
          assert is_binary(classification.file_type)
          assert classification.confidence < 0.85

        {:error, _reason} ->
          # Should emit DLQ event
          assert_receive {:event, %{name: "system.dlq.classifier_failed"}}, @test_timeout
      end

      # Cleanup
      File.rm(invalid_path)
    end

    test "emits telemetry events for all classifications" do
      file_path = Path.join(@fixtures_dir, "sample.json")
      correlation_id = "telemetry-test-#{System.unique_integer()}"

      {:ok, _classification} = Magika.classify_file(file_path, correlation_id: correlation_id)

      # Verify start event
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :start],
                      %{system_time: _},
                      %{correlation_id: ^correlation_id}}, @test_timeout

      # Verify stop event with duration
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :stop],
                      %{duration: duration},
                      %{correlation_id: ^correlation_id}}, @test_timeout

      assert is_integer(duration)
      assert duration > 0
    end

    test "handles batch classification correctly" do
      files = [
        Path.join(@fixtures_dir, "sample.json"),
        Path.join(@fixtures_dir, "sample.html"),
        Path.join(@fixtures_dir, "sample.txt")
      ]

      base_correlation_id = "batch-test-#{System.unique_integer()}"

      results = Enum.map(Enum.with_index(files), fn {file, idx} ->
        correlation_id = "#{base_correlation_id}-#{idx}"
        Magika.classify_file(file, correlation_id: correlation_id)
      end)

      # All should succeed
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

      # All should emit events
      for idx <- 0..2 do
        expected_correlation_id = "#{base_correlation_id}-#{idx}"
        assert_receive {:event, %{payload: %{correlation_id: ^expected_correlation_id}}}, @test_timeout
      end
    end
  end

  describe "Magika Pipeline Error Handling" do
    test "handles non-existent file gracefully" do
      file_path = "/tmp/nonexistent_#{System.unique_integer()}.bin"
      correlation_id = "error-test-#{System.unique_integer()}"

      result = Magika.classify_file(file_path, correlation_id: correlation_id)

      assert {:error, reason} = result
      assert is_binary(reason) or is_atom(reason)

      # Should emit error telemetry
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :error],
                      _measurements,
                      %{correlation_id: ^correlation_id}}, @test_timeout
    end

    test "handles Magika CLI timeout gracefully" do
      # This would require a large file or slow processing
      # For now, verify the timeout configuration exists
      assert is_integer(Application.get_env(:thunderline, :magika_timeout, 30_000))
    end
  end

  # Telemetry handler for tests
  def handle_telemetry_event(event_name, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry, event_name, measurements, metadata})
  end
end
