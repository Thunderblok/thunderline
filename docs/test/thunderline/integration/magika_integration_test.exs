defmodule Thunderline.Integration.MagikaIntegrationTest do
  use ExUnit.Case, async: false

  alias Thunderline.Event
  alias Thunderline.EventBus

  @moduletag :integration
  @moduletag timeout: 30_000

  setup do
    # Start EventBus for this test
    {:ok, bus_pid} = EventBus.start_link(name: :test_integration_bus)

    # Subscribe to all events in the pipeline
    {:ok, _sub1} =
      EventBus.subscribe(:test_integration_bus, "ui.command.**",
        dispatch: {:pid, target: self()}
      )

    {:ok, _sub2} =
      EventBus.subscribe(:test_integration_bus, "system.ingest.**",
        dispatch: {:pid, target: self()}
      )

    {:ok, _sub3} =
      EventBus.subscribe(:test_integration_bus, "system.nlp.**",
        dispatch: {:pid, target: self()}
      )

    {:ok, _sub4} =
      EventBus.subscribe(:test_integration_bus, "system.ml.**",
        dispatch: {:pid, target: self()}
      )

    {:ok, _sub5} =
      EventBus.subscribe(:test_integration_bus, "dag.**", dispatch: {:pid, target: self()})

    {:ok, _sub6} =
      EventBus.subscribe(:test_integration_bus, "system.dlq.**",
        dispatch: {:pid, target: self()}
      )

    on_exit(fn ->
      if Process.alive?(bus_pid), do: Process.exit(bus_pid, :kill)
    end)

    :ok
  end

  describe "end-to-end ML pipeline" do
    @tag :skip
    test "processes PDF through complete pipeline with correlation IDs" do
      # Create a minimal PDF
      pdf_content = """
      %PDF-1.4
      1 0 obj
      <<
      /Type /Catalog
      /Pages 2 0 R
      >>
      endobj
      2 0 obj
      <<
      /Type /Pages
      /Kids [3 0 R]
      /Count 1
      >>
      endobj
      """

      tmp_path = Path.join(System.tmp_dir!(), "test_#{Thunderline.UUID.v7()}.pdf")
      File.write!(tmp_path, pdf_content)

      correlation_id = Thunderline.UUID.v7()

      # Simulate ingestion event
      {:ok, ingest_event} =
        Event.new(%{
          type: "ui.command.ingest.received",
          source: "test",
          data: %{
            path: tmp_path,
            filename: "document.pdf"
          },
          metadata: %{
            correlation_id: correlation_id
          }
        })

      # Publish to bus (would normally come from LiveView upload)
      {:ok, _} = EventBus.publish(:test_integration_bus, [ingest_event])

      # Expect classification event
      assert_receive {:event, %Event{type: "system.ingest.classified"} = classified}, 5_000

      assert classified.data.content_type in ["application/pdf", "application/octet-stream"]
      assert classified.data.filename == "document.pdf"
      assert classified.metadata.correlation_id == correlation_id
      assert classified.metadata.causation_id == ingest_event.id

      # Expect NLP analysis event (when NLP consumer is wired)
      # assert_receive {:event, %Event{type: "system.nlp.analyzed"} = nlp}, 5_000
      # assert nlp.metadata.correlation_id == correlation_id
      # assert nlp.metadata.causation_id == classified.id

      # Expect ML inference event (when ONNX consumer is wired)
      # assert_receive {:event, %Event{type: "system.ml.run.completed"} = ml}, 5_000
      # assert ml.metadata.correlation_id == correlation_id

      # Expect voxel commit event (when Voxel consumer is wired)
      # assert_receive {:event, %Event{type: "dag.commit"} = commit}, 5_000
      # assert commit.metadata.correlation_id == correlation_id

      File.rm(tmp_path)
    end

    test "routes failed classification to DLQ" do
      correlation_id = Thunderline.UUID.v7()

      # Simulate ingestion event with non-existent file
      {:ok, ingest_event} =
        Event.new(%{
          type: "ui.command.ingest.received",
          source: "test",
          data: %{
            path: "/nonexistent/file.pdf",
            filename: "missing.pdf"
          },
          metadata: %{
            correlation_id: correlation_id
          }
        })

      {:ok, _} = EventBus.publish(:test_integration_bus, [ingest_event])

      # Expect DLQ event for classification failure
      assert_receive {:event, %Event{type: "system.dlq.classification_failed"} = dlq}, 5_000

      assert dlq.data.error =~ "file_not_found"
      assert dlq.data.event_id == ingest_event.id
      assert dlq.metadata.processor == Thunderline.Thunderflow.Consumers.Classifier
    end

    test "handles low confidence with fallback" do
      # Create a file with ambiguous extension
      mystery_content = "This could be anything"
      tmp_path = Path.join(System.tmp_dir!(), "mystery_#{Thunderline.UUID.v7()}.xyz")
      File.write!(tmp_path, mystery_content)

      correlation_id = Thunderline.UUID.v7()

      {:ok, ingest_event} =
        Event.new(%{
          type: "ui.command.ingest.received",
          source: "test",
          data: %{
            path: tmp_path,
            filename: "mystery.xyz"
          },
          metadata: %{
            correlation_id: correlation_id
          }
        })

      {:ok, _} = EventBus.publish(:test_integration_bus, [ingest_event])

      assert_receive {:event, %Event{type: "system.ingest.classified"} = classified}, 5_000

      # Should use fallback to extension (unknown extension = octet-stream)
      assert classified.data.content_type == "application/octet-stream"
      assert classified.data.confidence == 0.0
      assert Map.has_key?(classified.metadata, :fallback)

      File.rm(tmp_path)
    end

    test "processes multiple files concurrently with unique correlation IDs" do
      files = [
        {"file1.txt", "text/plain", "Hello world"},
        {"file2.json", "application/json", ~s({"key": "value"})},
        {"file3.csv", "text/csv", "a,b,c\n1,2,3"}
      ]

      correlation_ids =
        Enum.map(files, fn {filename, _mime, content} ->
          tmp_path = Path.join(System.tmp_dir!(), "batch_#{Thunderline.UUID.v7()}_#{filename}")
          File.write!(tmp_path, content)

          correlation_id = Thunderline.UUID.v7()

          {:ok, event} =
            Event.new(%{
              type: "ui.command.ingest.received",
              source: "test",
              data: %{path: tmp_path, filename: filename},
              metadata: %{correlation_id: correlation_id}
            })

          {:ok, _} = EventBus.publish(:test_integration_bus, [event])

          {correlation_id, filename, tmp_path}
        end)

      # Expect 3 classification events with matching correlation IDs
      classified_events =
        for _ <- 1..3 do
          assert_receive {:event, %Event{type: "system.ingest.classified"} = event}, 5_000
          event
        end

      # Verify each correlation ID matches
      for {corr_id, filename, tmp_path} <- correlation_ids do
        matching_event =
          Enum.find(classified_events, fn e ->
            e.metadata.correlation_id == corr_id
          end)

        assert matching_event, "No classified event for #{filename}"
        assert matching_event.data.filename == Path.basename(tmp_path)

        File.rm(tmp_path)
      end
    end
  end

  describe "telemetry instrumentation" do
    test "emits telemetry events for classification" do
      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach_many(
        "magika-integration-telemetry",
        [
          [:thunderline, :thundergate, :magika, :classify, :start],
          [:thunderline, :thundergate, :magika, :classify, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      tmp_path = Path.join(System.tmp_dir!(), "telemetry_test_#{Thunderline.UUID.v7()}.txt")
      File.write!(tmp_path, "telemetry test")

      {:ok, event} =
        Event.new(%{
          type: "ui.command.ingest.received",
          source: "test",
          data: %{path: tmp_path, filename: "telemetry.txt"}
        })

      {:ok, _} = EventBus.publish(:test_integration_bus, [event])

      # Expect start telemetry
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :start], _,
                      metadata},
                     5_000

      assert metadata.path == tmp_path

      # Expect stop telemetry
      assert_receive {:telemetry, [:thunderline, :thundergate, :magika, :classify, :stop],
                      %{duration: duration}, metadata},
                     5_000

      assert is_integer(duration)
      assert metadata.content_type in ["text/plain", "application/octet-stream"]

      :telemetry.detach("magika-integration-telemetry")
      File.rm(tmp_path)
    end
  end
end
