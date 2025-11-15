defmodule Thunderline.Thundergate.MagikaTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thundergate.Magika

  @moduletag :capture_log

  setup do
    # Subscribe to telemetry events
    :telemetry.attach_many(
      "magika-test",
      [
        [:thunderline, :thundergate, :magika, :classify, :start],
        [:thunderline, :thundergate, :magika, :classify, :stop],
        [:thunderline, :thundergate, :magika, :classify, :error]
      ],
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("magika-test")
    end)

    :ok
  end

  describe "classify_file/2" do
    test "successfully classifies a PDF file with high confidence" do
      # Create a temporary PDF file (just minimal PDF signature)
      pdf_content = "%PDF-1.4\n"
      tmp_path = create_temp_file(pdf_content, ".pdf")

      # Mock Magika CLI to return high confidence
      with_mocked_magika(
        fn _args ->
          {
            Jason.encode!(%{
              "output" => %{
                "label" => "pdf",
                "score" => 0.98,
                "mime_type" => "application/pdf"
              }
            }),
            0
          }
        end,
        fn ->
          assert {:ok, result} = Magika.classify_file(tmp_path, emit_event?: false)

          assert result.content_type == "application/pdf"
          assert result.confidence == 0.98
          assert result.label == "pdf"
          assert String.match?(result.sha256, ~r/^[a-f0-9]{64}$/)
          assert result.filename == Path.basename(tmp_path)
          refute Map.has_key?(result, :fallback)

          # Verify telemetry
          assert_received {:telemetry, [:thunderline, :thundergate, :magika, :classify, :start],
                           _, _}

          assert_received {:telemetry, [:thunderline, :thundergate, :magika, :classify, :stop],
                           %{duration: _}, metadata}

          assert metadata.content_type == "application/pdf"
          assert metadata.confidence == 0.98
        end
      )

      File.rm(tmp_path)
    end

    test "falls back to extension detection on low confidence" do
      tmp_path = create_temp_file("some content", ".txt")

      with_mocked_magika(
        fn _args ->
          {
            Jason.encode!(%{
              "output" => %{
                "label" => "unknown",
                "score" => 0.45,
                "mime_type" => "application/octet-stream"
              }
            }),
            0
          }
        end,
        fn ->
          # Override confidence threshold for test
          original_config = Application.get_env(:thunderline, Magika, [])

          Application.put_env(:thunderline, Magika,
            confidence_threshold: 0.85,
            cli_path: "magika"
          )

          assert {:ok, result} = Magika.classify_file(tmp_path, emit_event?: false)

          # Should fall back to extension-based detection
          assert result.content_type == "text/plain"
          assert result.confidence == 0.0
          assert result.fallback == :extension

          Application.put_env(:thunderline, Magika, original_config)
        end
      )

      File.rm(tmp_path)
    end

    test "falls back to extension detection when CLI fails" do
      tmp_path = create_temp_file("test content", ".json")

      with_mocked_magika(
        fn _args ->
          {"Error: CLI crashed\n", 1}
        end,
        fn ->
          assert {:ok, result} = Magika.classify_file(tmp_path, emit_event?: false)

          assert result.content_type == "application/json"
          assert result.confidence == 0.0
          assert result.fallback == :extension
          assert result.label == "unknown"
        end
      )

      File.rm(tmp_path)
    end

    test "handles unknown extensions gracefully" do
      tmp_path = create_temp_file("mystery data", ".xyz")

      with_mocked_magika(
        fn _args -> {"Error\n", 1} end,
        fn ->
          assert {:ok, result} = Magika.classify_file(tmp_path, emit_event?: false)

          assert result.content_type == "application/octet-stream"
          assert result.confidence == 0.0
          assert result.fallback == :extension
        end
      )

      File.rm(tmp_path)
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_not_found, _}} = Magika.classify_file("/nonexistent/file.pdf")

      assert_received {:telemetry, [:thunderline, :thundergate, :magika, :classify, :error], _,
                       _}
    end

    test "handles malformed JSON from CLI" do
      tmp_path = create_temp_file("test", ".txt")

      with_mocked_magika(
        fn _args -> {"not valid json", 0} end,
        fn ->
          # Should fall back to extension
          assert {:ok, result} = Magika.classify_file(tmp_path, emit_event?: false)
          assert result.fallback == :extension
        end
      )

      File.rm(tmp_path)
    end

    test "emits system.ingest.classified event by default" do
      tmp_path = create_temp_file("test", ".txt")

      with_mocked_magika(
        fn _args ->
          {
            Jason.encode!(%{
              "output" => %{"label" => "txt", "score" => 0.95, "mime_type" => "text/plain"}
            }),
            0
          }
        end,
        fn ->
          # Subscribe to event bus
          {:ok, _} = Thunderline.EventBus.start_link(name: :test_bus)
          correlation_id = Thunderline.UUID.v7()

          {:ok, _sub} =
            Thunderline.EventBus.subscribe(:test_bus, "system.ingest.classified",
              dispatch: {:pid, target: self()}
            )

          assert {:ok, result} = Magika.classify_file(tmp_path, correlation_id: correlation_id)

          # Wait for event
          assert_receive {:event, event}, 1000

          assert event.type == "system.ingest.classified"
          assert event.source == "thundergate.magika"
          assert event.data.content_type == "text/plain"
          assert event.data.sha256 == result.sha256
          assert event.metadata.correlation_id == correlation_id

          Process.exit(Process.whereis(:test_bus), :kill)
        end
      )

      File.rm(tmp_path)
    end

    test "uses provided correlation_id and causation_id" do
      tmp_path = create_temp_file("test", ".txt")
      correlation_id = Thunderline.UUID.v7()
      causation_id = Thunderline.UUID.v7()

      with_mocked_magika(
        fn _args ->
          {Jason.encode!(%{"output" => %{"label" => "txt", "score" => 0.9}}), 0}
        end,
        fn ->
          {:ok, _} = Thunderline.EventBus.start_link(name: :test_bus2)

          {:ok, _sub} =
            Thunderline.EventBus.subscribe(:test_bus2, "system.**",
              dispatch: {:pid, target: self()}
            )

          Magika.classify_file(tmp_path,
            correlation_id: correlation_id,
            causation_id: causation_id
          )

          assert_receive {:event, event}, 1000
          assert event.metadata.correlation_id == correlation_id
          assert event.metadata.causation_id == causation_id

          Process.exit(Process.whereis(:test_bus2), :kill)
        end
      )

      File.rm(tmp_path)
    end
  end

  describe "classify_bytes/3" do
    test "classifies bytes by writing to temp file" do
      bytes = "test content for bytes"
      filename = "document.txt"

      with_mocked_magika(
        fn _args ->
          {Jason.encode!(%{"output" => %{"label" => "txt", "score" => 0.92}}), 0}
        end,
        fn ->
          assert {:ok, result} = Magika.classify_bytes(bytes, filename, emit_event?: false)

          assert result.confidence == 0.92
          assert result.filename =~ ~r/^magika_.*\.txt$/
          # SHA256 should match the input bytes
          expected_sha = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
          assert result.sha256 == expected_sha
        end
      )
    end

    test "preserves file extension in temp file" do
      bytes = "PDF content"
      filename = "report.pdf"

      with_mocked_magika(
        fn [_, _, path] ->
          # Verify temp file has .pdf extension
          assert String.ends_with?(path, ".pdf")

          {Jason.encode!(%{"output" => %{"label" => "pdf", "score" => 0.99}}), 0}
        end,
        fn ->
          assert {:ok, _result} = Magika.classify_bytes(bytes, filename, emit_event?: false)
        end
      )
    end

    test "cleans up temp file after classification" do
      bytes = "cleanup test"
      filename = "test.txt"

      tmp_file_path = nil

      with_mocked_magika(
        fn [_, _, path] ->
          # Capture the temp file path
          send(self(), {:tmp_path, path})
          {Jason.encode!(%{"output" => %{"label" => "txt", "score" => 0.8}}), 0}
        end,
        fn ->
          Magika.classify_bytes(bytes, filename, emit_event?: false)

          assert_receive {:tmp_path, path}
          tmp_file_path = path

          # Temp file should be cleaned up
          refute File.exists?(tmp_file_path)
        end
      )
    end
  end

  # Helper functions

  defp create_temp_file(content, extension) do
    tmp_path = Path.join(System.tmp_dir!(), "magika_test_#{Thunderline.UUID.v7()}#{extension}")
    File.write!(tmp_path, content)
    tmp_path
  end

  defp with_mocked_magika(mock_fn, test_fn) do
    # Store original System.cmd/3
    original_cmd = :erlang.fun_info(System, :cmd)

    # Create a mock that intercepts calls to magika
    mock_system_cmd = fn
      "magika", args, _opts ->
        mock_fn.(args)

      cmd, args, opts ->
        # Pass through to real System.cmd for other commands
        apply(Kernel, :apply, [System, :cmd, [cmd, args, opts]])
    end

    # Temporarily replace System.cmd behavior via configuration
    # In practice, we'd use Mox or similar, but for this example we'll
    # use Application config to pass the mock
    Application.put_env(:thunderline, :system_cmd_mock, mock_system_cmd)

    try do
      test_fn.()
    after
      Application.delete_env(:thunderline, :system_cmd_mock)
    end
  end
end
