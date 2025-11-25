defmodule Thunderline.Thunderbolt.Resources.OnnxInference do
  @moduledoc """
  Ash resource for ONNX model inference via MCP tools.

  Exposes loaded ONNX models (UPM snapshots, Cerebros checkpoints, etc.) as callable
  MCP tools through Ash.AI integration.

  ## Usage

  ### Via Ash.AI MCP Tool
  ```json
  {
    "tool": "onnx_infer",
    "params": {
      "model_path": "priv/models/upm_snapshot_v1.onnx",
      "input": {"data": [[1.0, 2.0, 3.0]]},
      "metadata": {"correlation_id": "abc123"}
    }
  }
  ```

  ### Direct Elixir
  ```elixir
  {:ok, result} = Thunderline.Thunderbolt.Resources.OnnxInference.infer(%{
    model_path: "priv/models/demo.onnx",
    input: %{data: [[1.0, 2.0, 3.0]]},
    metadata: %{correlation_id: "abc123"}
  })
  ```

  ## Integration Points
  - Uses `Thunderline.Thunderbolt.ML.KerasONNX` for actual inference
  - Telemetry: `[:thunderbolt, :onnx, :inference, :*]`
  - Exposed via Thundercrown MCP: `tool :onnx_infer`
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded

  require Logger

  # No persistence - pure compute resource for inference
  attributes do
    # Input
    attribute :model_path, :string do
      allow_nil? false
      description "Path to ONNX model file (absolute or relative to priv/models)"
    end

    attribute :input, :map do
      allow_nil? false
      description "Input tensor data as map with 'data' key containing nested lists"
    end

    attribute :metadata, :map do
      default %{}
      description "Optional metadata (correlation_id, tenant_id, etc.)"
    end

    # Output
    attribute :predictions, :map do
      description "Model predictions as map"
    end

    attribute :duration_ms, :integer do
      description "Inference duration in milliseconds"
    end

    attribute :status, :atom do
      constraints one_of: [:success, :error]
      description "Inference status"
    end

    attribute :error, :string do
      description "Error message if status=:error"
    end
  end

  code_interface do
    define :infer, action: :infer, args: [:model_path, :input, :metadata]
  end

  actions do
    # Primary inference action
    create :infer do
      description "Run ONNX inference on input tensor"

      accept [:model_path, :input, :metadata]

      # Custom change to run inference
      change fn changeset, _context ->
        model_path = Ash.Changeset.get_attribute(changeset, :model_path)
        input = Ash.Changeset.get_attribute(changeset, :input)
        metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

        Logger.info("[OnnxInference] Running inference: model=#{model_path}")

        start_time = System.monotonic_time(:millisecond)

        result =
          with {:ok, session} <-
                 Thunderline.Thunderbolt.ML.KerasONNX.load!(model_path),
               {:ok, ml_input} <- build_ml_input(input),
               {:ok, ml_output} <-
                 Thunderline.Thunderbolt.ML.KerasONNX.infer(
                   session,
                   ml_input,
                   correlation_id: metadata[:correlation_id]
                 ) do
            duration_ms = System.monotonic_time(:millisecond) - start_time

            # Emit telemetry
            :telemetry.execute(
              [:thunderbolt, :onnx, :inference, :success],
              %{duration_ms: duration_ms},
              %{model_path: model_path, correlation_id: metadata[:correlation_id]}
            )

            Logger.info(
              "[OnnxInference] Success: model=#{model_path}, duration=#{duration_ms}ms"
            )

            # Close session after use
            _ = Thunderline.Thunderbolt.ML.KerasONNX.close(session)

            {:ok, ml_output}
          else
            {:error, reason} = error ->
              duration_ms = System.monotonic_time(:millisecond) - start_time

              :telemetry.execute(
                [:thunderbolt, :onnx, :inference, :error],
                %{duration_ms: duration_ms},
                %{
                  model_path: model_path,
                  reason: reason,
                  correlation_id: metadata[:correlation_id]
                }
              )

              Logger.error(
                "[OnnxInference] Failed: model=#{model_path}, reason=#{inspect(reason)}"
              )

              error
          end

        case result do
          {:ok, ml_output} ->
            changeset
            |> Ash.Changeset.change_attribute(:predictions, extract_predictions(ml_output))
            |> Ash.Changeset.change_attribute(
              :duration_ms,
              System.monotonic_time(:millisecond) - start_time
            )
            |> Ash.Changeset.change_attribute(:status, :success)

          {:error, reason} ->
            changeset
            |> Ash.Changeset.change_attribute(:status, :error)
            |> Ash.Changeset.change_attribute(:error, inspect(reason))
            |> Ash.Changeset.change_attribute(
              :duration_ms,
              System.monotonic_time(:millisecond) - start_time
            )
        end
      end
    end

    # Read action (required by Ash)
    read :read do
      description "No-op read (inference is stateless)"
    end
  end

  # Private helpers

  # Build ML.Input struct from raw input map
  defp build_ml_input(%{data: data}) when is_list(data) do
    try do
      # Convert to Nx tensor - ensure we have batch dimension
      # If data is 1D (e.g., [1, 2, 3]), wrap in batch: [[1, 2, 3]]
      data_for_tensor = ensure_batch_dimension(data)

      # Use s64 (int64) for token-based models
      tensor = Nx.tensor(data_for_tensor, type: :s64, backend: Nx.BinaryBackend)

      input = %Thunderline.Thunderbolt.ML.Input{
        tensor: tensor,
        dtype: Nx.type(tensor),
        shape: Nx.shape(tensor),
        metadata: %{}
      }

      {:ok, input}
    rescue
      error ->
        {:error, {:tensor_conversion_failed, error}}
    end
  end

  # Ensure data has batch dimension (2D for sequence models)
  defp ensure_batch_dimension([first | _] = data) when is_list(first) do
    # Already has batch dimension (e.g., [[1,2,3], [4,5,6]])
    data
  end

  defp ensure_batch_dimension(data) when is_list(data) do
    # Single sequence - wrap in batch: [1,2,3] -> [[1,2,3]]
    [data]
  end

  defp build_ml_input(%{data: data, dtype: dtype}) when is_list(data) do
    try do
      # Use specified dtype
      tensor = Nx.tensor(data, type: dtype, backend: Nx.BinaryBackend)

      input = %Thunderline.Thunderbolt.ML.Input{
        tensor: tensor,
        dtype: Nx.type(tensor),
        shape: Nx.shape(tensor),
        metadata: %{}
      }

      {:ok, input}
    rescue
      error ->
        {:error, {:tensor_conversion_failed, error}}
    end
  end

  defp build_ml_input(_invalid) do
    {:error, :invalid_input_format}
  end

  # Extract predictions from ML.Output
  defp extract_predictions(%Thunderline.Thunderbolt.ML.Output{} = output) do
    %{
      tensor: Nx.to_list(output.tensor),
      shape: output.shape,
      dtype: output.dtype,
      inference_time_us: output.inference_time_us,
      metadata: output.metadata
    }
  end

  defp extract_predictions(_invalid) do
    %{}
  end
end
