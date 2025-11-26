defmodule Thunderline.Thunderbolt.CerebrosModel do
  @moduledoc """
  Bumblebee model loader for Cerebros checkpoints.

  Loads trained models from Cerebros checkpoints (ONNX, Keras, TF SavedModel)
  into Nx/Axon format for inference via Bumblebee.

  Supports:
  - ONNX models (via Ortex if available)
  - Keras .h5 files (via conversion)
  - TensorFlow SavedModel (via conversion)
  - Direct Nx serialization
  """

  alias Thunderline.Thunderbolt.Resources.CerebrosTrainingJob
  require Logger

  @models_registry_key {__MODULE__, :loaded_models}

  @doc """
  Load a checkpoint from a CerebrosTrainingJob into Bumblebee/Nx format.

  Returns {:ok, model_ref} or {:error, reason}.
  The model_ref can be used for inference.
  """
  def load_checkpoint(job_id) do
    with {:ok, job} <- get_job(job_id),
         {:ok, checkpoint_path} <- get_checkpoint_path(job),
         {:ok, model_format} <- detect_format(checkpoint_path),
         {:ok, serving} <- load_model(checkpoint_path, model_format),
         :ok <- register_model(job_id, serving) do
      # Mark as loaded
      CerebrosTrainingJob.mark_model_loaded!(job, model_format: Atom.to_string(model_format))

      Logger.info("Loaded Cerebros model for job #{job_id}, format: #{model_format}")
      {:ok, job_id}
    else
      {:error, reason} = error ->
        Logger.error("Failed to load checkpoint for job #{job_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Generate text embedding using a loaded Cerebros model.
  """
  def generate_embedding(job_id, text) do
    case get_serving(job_id) do
      {:ok, serving} ->
        try do
          result = Nx.Serving.batched_run(serving, text)
          {:ok, result.embedding}
        rescue
          e ->
            {:error, {:inference_failed, e}}
        end

      error ->
        error
    end
  end

  @doc """
  Generate text using a loaded Cerebros model (for generative models).
  """
  def generate_text(job_id, prompt, opts \\ []) do
    case get_serving(job_id) do
      {:ok, serving} ->
        try do
          max_length = Keyword.get(opts, :max_length, 100)
          result = Nx.Serving.batched_run(serving, %{text: prompt, max_length: max_length})
          {:ok, result.text}
        rescue
          e ->
            {:error, {:inference_failed, e}}
        end

      error ->
        error
    end
  end

  @doc """
  List all loaded models.
  """
  def list_loaded_models do
    case :persistent_term.get(@models_registry_key, nil) do
      nil -> []
      models -> Map.keys(models)
    end
  end

  @doc """
  Unload a model from memory.
  """
  def unload_model(job_id) do
    models = :persistent_term.get(@models_registry_key, %{})
    updated_models = Map.delete(models, job_id)
    :persistent_term.put(@models_registry_key, updated_models)
    :ok
  end

  # Private functions

  defp get_job(job_id) do
    case Ash.get(CerebrosTrainingJob, job_id) do
      {:ok, job} -> {:ok, job}
      {:error, _} -> {:error, :job_not_found}
    end
  end

  defp get_checkpoint_path(job) do
    if job.current_checkpoint_url do
      {:ok, job.current_checkpoint_url}
    else
      {:error, :no_checkpoint}
    end
  end

  defp detect_format(path) do
    cond do
      String.ends_with?(path, ".onnx") -> {:ok, :onnx}
      String.ends_with?(path, ".h5") -> {:ok, :keras}
      String.ends_with?(path, ".pb") || File.dir?(path) -> {:ok, :tensorflow}
      String.ends_with?(path, ".nx") -> {:ok, :nx}
      true -> {:error, :unknown_format}
    end
  end

  defp load_model(checkpoint_path, :onnx) do
    # ONNX loading delegated to Cerebros.Bridge (HC-20 boundary)
    alias Thunderline.Cerebros.Bridge

    # Generate a model name from the checkpoint path
    model_name = Path.basename(checkpoint_path, ".onnx")

    case Bridge.load_model(model_name, path: checkpoint_path) do
      {:ok, _info} ->
        # Create a serving that delegates inference to the Bridge
        serving =
          Nx.Serving.new(fn batch ->
            case Bridge.run_inference(model_name, batch) do
              {:ok, result} -> result
              {:error, reason} -> raise "Inference failed: #{inspect(reason)}"
            end
          end)

        {:ok, serving}

      error ->
        error
    end
  end

  defp load_model(_checkpoint_path, :keras) do
    # Keras loading would require conversion to ONNX first
    # For now, return error suggesting conversion
    {:error, {:requires_conversion, :keras_to_onnx}}
  end

  defp load_model(_checkpoint_path, :tensorflow) do
    # TensorFlow loading would require conversion to ONNX first
    {:error, {:requires_conversion, :tf_to_onnx}}
  end

  defp load_model(checkpoint_path, :nx) do
    # Direct Nx serialization
    case File.read(checkpoint_path) do
      {:ok, binary} ->
        model = :erlang.binary_to_term(binary)

        serving =
          Nx.Serving.new(fn batch ->
            # Assuming model is an Axon model
            Axon.predict(model, batch)
          end)

        {:ok, serving}

      error ->
        error
    end
  end

  defp register_model(job_id, serving) do
    models = :persistent_term.get(@models_registry_key, %{})
    updated_models = Map.put(models, job_id, serving)
    :persistent_term.put(@models_registry_key, updated_models)
    :ok
  end

  defp get_serving(job_id) do
    models = :persistent_term.get(@models_registry_key, %{})

    case Map.get(models, job_id) do
      nil -> {:error, :model_not_loaded}
      serving -> {:ok, serving}
    end
  end

  @doc """
  MCP Tool registration helper.

  Registers a loaded Cerebros model as an MCP tool for AI integration.
  """
  def register_as_mcp_tool(job_id, tool_name \\ nil) do
    tool_name = tool_name || "cerebros_model_#{job_id}"

    # This would integrate with your MCP tool system
    # For now, just return the tool definition
    {:ok,
     %{
       name: tool_name,
       description: "Cerebros trained model for embeddings and generation",
       schema: %{
         type: "object",
         properties: %{
           text: %{type: "string", description: "Input text"},
           mode: %{type: "string", enum: ["embed", "generate"], default: "embed"}
         },
         required: ["text"]
       },
       handler: fn params ->
         case params do
           %{"text" => text, "mode" => "generate"} ->
             generate_text(job_id, text)

           %{"text" => text} ->
             generate_embedding(job_id, text)
         end
       end
     }}
  end
end
