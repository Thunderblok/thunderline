defmodule Thunderline.ML.KerasONNXTest do
  use ExUnit.Case, async: true

  alias Thunderline.ML.{KerasONNX, Input, Output}

  @moduletag :ml
  @moduletag :onnx

  # Test model path (to be created)
  @demo_model_path "test/fixtures/models/demo.onnx"

  describe "load!/2" do
    @tag :skip
    test "loads model successfully with default options" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)
      assert is_reference(session) or is_map(session)

      # Cleanup
      :ok = KerasONNX.close(session)
    end

    @tag :skip
    test "loads model with custom options" do
      opts = [
        device: :cpu,
        optimization_level: :all,
        intra_op_num_threads: 2
      ]

      {:ok, session} = KerasONNX.load!(@demo_model_path, opts)
      assert is_reference(session) or is_map(session)

      :ok = KerasONNX.close(session)
    end

    test "returns error for non-existent file" do
      {:error, {:file_not_found, _path}} = KerasONNX.load!("nonexistent.onnx")
    end

    test "returns error for invalid file extension" do
      {:error, {:invalid_extension, _path}} = KerasONNX.load!("model.txt")
    end

    @tag :skip
    test "resolves relative paths from model directory" do
      # Create temporary model directory
      model_dir = "test/tmp/models"
      File.mkdir_p!(model_dir)

      # Configure model directory
      Application.put_env(:thunderline, KerasONNX, model_dir: model_dir)

      # This should resolve to test/tmp/models/demo.onnx
      result = KerasONNX.load!("demo.onnx")
      assert match?({:error, {:file_not_found, _}}, result)

      # Cleanup
      Application.delete_env(:thunderline, KerasONNX)
      File.rm_rf!(model_dir)
    end
  end

  describe "infer/3" do
    @tag :skip
    test "runs inference on single input" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Create test input
      input = Input.new!(%{data: Nx.tensor([[1.0, 2.0, 3.0]])}, :tabular, %{})

      # Run inference
      {:ok, output} = KerasONNX.infer(session, input)

      # Validate output structure
      assert %Output{} = output
      assert output.model_name == "onnx_model"
      assert is_list(output.predictions) or is_map(output.predictions)
      assert output.inference_time_ms >= 0
      assert is_map(output.metadata)

      :ok = KerasONNX.close(session)
    end

    @tag :skip
    test "includes correlation_id in output when provided" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      input = Input.new!(%{data: Nx.tensor([[1.0]])}, :tabular, %{})
      correlation_id = "test-correlation-123"

      {:ok, output} = KerasONNX.infer(session, input, correlation_id: correlation_id)

      assert output.correlation_id == correlation_id

      :ok = KerasONNX.close(session)
    end

    @tag :skip
    test "uses input correlation_id when not overridden" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      input_correlation_id = "input-correlation-456"

      input =
        Input.new!(%{data: Nx.tensor([[1.0]])}, :tabular, %{})
        |> Map.put(:correlation_id, input_correlation_id)

      {:ok, output} = KerasONNX.infer(session, input)

      assert output.correlation_id == input_correlation_id

      :ok = KerasONNX.close(session)
    end

    test "returns error for invalid session" do
      invalid_session = make_ref()
      input = Input.new!(%{data: Nx.tensor([[1.0]])}, :tabular, %{})

      result = KerasONNX.infer(invalid_session, input)
      assert match?({:error, _}, result)
    end
  end

  describe "infer_batch/3" do
    @tag :skip
    test "runs batched inference on multiple inputs" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Create batch of inputs
      inputs = [
        Input.new!(%{data: Nx.tensor([[1.0, 2.0]])}, :tabular, %{}),
        Input.new!(%{data: Nx.tensor([[3.0, 4.0]])}, :tabular, %{}),
        Input.new!(%{data: Nx.tensor([[5.0, 6.0]])}, :tabular, %{})
      ]

      {:ok, outputs} = KerasONNX.infer_batch(session, inputs)

      # Validate batch results
      assert length(outputs) == 3

      Enum.each(outputs, fn output ->
        assert %Output{} = output
        assert output.model_name == "onnx_model"
        assert output.metadata.batch_size == 3
      end)

      :ok = KerasONNX.close(session)
    end

    test "returns empty list for empty input batch" do
      session = make_ref()
      {:ok, []} = KerasONNX.infer_batch(session, [])
    end

    @tag :skip
    test "handles batch of size 1" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      inputs = [Input.new!(%{data: Nx.tensor([[1.0]])}, :tabular, %{})]

      {:ok, outputs} = KerasONNX.infer_batch(session, inputs)

      assert length(outputs) == 1
      assert hd(outputs).metadata.batch_size == 1

      :ok = KerasONNX.close(session)
    end

    @tag :skip
    test "preserves input order in outputs" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Create inputs with unique correlation IDs
      inputs =
        1..5
        |> Enum.map(fn i ->
          Input.new!(%{data: Nx.tensor([[i * 1.0]])}, :tabular, %{})
          |> Map.put(:correlation_id, "input-#{i}")
        end)

      {:ok, outputs} = KerasONNX.infer_batch(session, inputs)

      # Verify order preserved
      Enum.zip(inputs, outputs)
      |> Enum.each(fn {input, output} ->
        assert output.correlation_id == input.correlation_id
      end)

      :ok = KerasONNX.close(session)
    end
  end

  describe "close/1" do
    @tag :skip
    test "closes session successfully" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)
      assert :ok = KerasONNX.close(session)
    end

    test "handles invalid session gracefully" do
      invalid_session = make_ref()
      # Should not crash, may return error
      result = KerasONNX.close(invalid_session)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "metadata/1" do
    @tag :skip
    test "retrieves model metadata" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      {:ok, metadata} = KerasONNX.metadata(session)

      assert is_map(metadata)
      assert Map.has_key?(metadata, :session)
      assert Map.has_key?(metadata, :provider)
      assert Map.has_key?(metadata, :runtime)

      :ok = KerasONNX.close(session)
    end

    test "handles invalid session" do
      invalid_session = make_ref()
      result = KerasONNX.metadata(invalid_session)
      assert match?({:error, _}, result)
    end
  end

  describe "telemetry" do
    setup do
      # Attach test telemetry handler
      test_pid = self()

      :telemetry.attach_many(
        "test-onnx-handler",
        [
          [:ml, :onnx, :load, :start],
          [:ml, :onnx, :load, :stop],
          [:ml, :onnx, :load, :exception],
          [:ml, :onnx, :infer, :start],
          [:ml, :onnx, :infer, :stop],
          [:ml, :onnx, :infer, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-onnx-handler")
      end)

      :ok
    end

    test "emits load events on successful load" do
      # Attempt to load (will fail for non-existent file but emit start event)
      _result = KerasONNX.load!("nonexistent.onnx")

      # Should receive start event
      assert_receive {:telemetry, [:ml, :onnx, :load, :start], measurements, metadata}
      assert is_map(measurements)
      assert metadata.model_path =~ "nonexistent.onnx"

      # Should receive exception event
      assert_receive {:telemetry, [:ml, :onnx, :load, :exception], measurements, metadata}
      assert is_map(measurements)
      assert Map.has_key?(metadata, :reason)
    end

    @tag :skip
    test "emits infer events on successful inference" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Clear load events
      :timer.sleep(10)
      flush_telemetry()

      input = Input.new!(%{data: Nx.tensor([[1.0]])}, :tabular, %{})
      _result = KerasONNX.infer(session, input)

      # Should receive start event
      assert_receive {:telemetry, [:ml, :onnx, :infer, :start], measurements, metadata}
      assert is_map(measurements)
      assert metadata.batch_size == 1

      # Should receive stop event
      assert_receive {:telemetry, [:ml, :onnx, :infer, :stop], measurements, metadata}
      assert measurements.duration > 0
      assert measurements.batch_size == 1
      assert is_map(metadata.input_shape)
      assert is_map(metadata.output_shape)

      :ok = KerasONNX.close(session)
    end

    test "emits exception events on inference failure" do
      invalid_session = make_ref()
      input = Input.new!(%{data: Nx.tensor([[1.0]])}, :tabular, %{})

      _result = KerasONNX.infer(invalid_session, input)

      # Should receive start event
      assert_receive {:telemetry, [:ml, :onnx, :infer, :start], _measurements, _metadata}

      # Should receive exception event
      assert_receive {:telemetry, [:ml, :onnx, :infer, :exception], measurements, metadata}
      assert is_map(measurements)
      assert Map.has_key?(metadata, :reason)
    end
  end

  describe "integration with ML.Input" do
    @tag :skip
    test "accepts normalized ML.Input" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Create and normalize input
      {:ok, input} = Input.new(%{data: Nx.tensor([[1.0, 2.0, 3.0]])}, :tabular, %{})
      {:ok, normalized} = Input.normalize(input)

      # Should accept normalized input
      {:ok, output} = KerasONNX.infer(session, normalized)

      assert %Output{} = output

      :ok = KerasONNX.close(session)
    end
  end

  describe "error handling" do
    @tag :skip
    test "handles tensor preparation errors gracefully" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Create input with invalid data type
      input = Input.new!(%{data: "invalid_tensor_data"}, :tabular, %{})

      result = KerasONNX.infer(session, input)
      assert match?({:error, _}, result)

      :ok = KerasONNX.close(session)
    end

    @tag :skip
    test "handles normalization failures" do
      {:ok, session} = KerasONNX.load!(@demo_model_path)

      # Create input that will fail normalization
      # (Implementation depends on ML.Normalize behavior)
      input = %Input{
        tensor: nil,
        shape: {1, 224, 224, 3},
        dtype: :f32,
        metadata: %{}
      }

      result = KerasONNX.infer(session, input)
      assert match?({:error, {:normalize_failed, _}}, result)

      :ok = KerasONNX.close(session)
    end
  end

  # Helper functions

  defp flush_telemetry do
    receive do
      {:telemetry, _, _, _} -> flush_telemetry()
    after
      0 -> :ok
    end
  end
end
