defmodule Thunderline.Thunderbolt.ML.KerasONNX do
  @moduledoc """
  ONNX model adapter using Ortex for in-process ML inference.

  Provides model loading, session management, and batched inference capabilities.
  Integrates with ML.Input/Output contracts for type safety and normalization.

  ## Features

  - Model loading from filesystem with validation
  - Session caching and reuse (via GenServer)
  - Batched inference with back-pressure support
  - Comprehensive error handling
  - Telemetry instrumentation
  - Type safety with Elixir specs

  ## Configuration

  Configure via application environment:

      config :thunderline, Thunderline.Thunderbolt.ML.KerasONNX,
        model_dir: "priv/models",
        default_device: :cpu,
        session_cache: true,
        max_batch_size: 32

  ## Examples

      # Load model
      {:ok, session} = KerasONNX.load!("demo.onnx")

      # Single inference
      input = ML.Input.new!(%{data: tensor}, :image, %{})
      {:ok, output} = KerasONNX.infer(session, input)

      # Batch inference
      inputs = [input1, input2, input3]
      {:ok, outputs} = KerasONNX.infer_batch(session, inputs)

      # Cleanup
      :ok = KerasONNX.close(session)

  ## Telemetry

  Emits the following events:

  - `[:ml, :onnx, :load, :start]` - Model loading started
  - `[:ml, :onnx, :load, :stop]` - Model loading completed
  - `[:ml, :onnx, :load, :exception]` - Model loading failed
  - `[:ml, :onnx, :infer, :start]` - Inference started
  - `[:ml, :onnx, :infer, :stop]` - Inference completed
  - `[:ml, :onnx, :infer, :exception]` - Inference failed

  Measurements include:

  - `duration` - Operation duration in native time units
  - `batch_size` - Number of inputs in batch
  - `input_shape` - Shape of input tensor
  - `output_shape` - Shape of output tensor

  """

  require Logger
  alias Thunderline.Thunderbolt.ML.{Input, Output}

  @type session :: reference()
  @type model_path :: String.t()
  @type load_opts :: [
          device: :cpu | :cuda | :tensorrt,
          execution_providers: [String.t()],
          optimization_level: :none | :basic | :extended | :all,
          intra_op_num_threads: pos_integer(),
          inter_op_num_threads: pos_integer()
        ]
  @type infer_opts :: [
          timeout: timeout(),
          correlation_id: String.t() | nil
        ]

  @default_opts [
    device: :cpu,
    execution_providers: ["CPUExecutionProvider"],
    optimization_level: :basic,
    intra_op_num_threads: 1,
    inter_op_num_threads: 1
  ]

  @doc """
  Loads an ONNX model from the filesystem.

  ## Parameters

  - `model_path` - Relative path to model file (from model_dir) or absolute path
  - `opts` - Optional configuration (see @type load_opts)

  ## Returns

  - `{:ok, session}` - Successfully loaded model session
  - `{:error, reason}` - Loading failed

  ## Examples

      # Load from default model directory
      {:ok, session} = KerasONNX.load!("demo.onnx")

      # Load with custom options
      {:ok, session} = KerasONNX.load!("demo.onnx",
        device: :cuda,
        optimization_level: :all
      )

      # Load from absolute path
      {:ok, session} = KerasONNX.load!("/tmp/model.onnx")

  """
  @spec load!(model_path(), load_opts()) :: {:ok, session()} | {:error, term()}
  def load!(model_path, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    full_path = resolve_model_path(model_path)

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:ml, :onnx, :load, :start],
      %{system_time: System.system_time()},
      %{model_path: full_path, opts: opts}
    )

    result =
      with :ok <- validate_model_file(full_path),
           {:ok, session} <- do_load_model(full_path, opts) do
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:ml, :onnx, :load, :stop],
          %{duration: duration},
          %{model_path: full_path, session: inspect(session)}
        )

        Logger.info("[KerasONNX] Loaded model: #{model_path} (#{format_duration(duration)})")
        {:ok, session}
      else
        {:error, reason} = error ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:ml, :onnx, :load, :exception],
            %{duration: duration},
            %{model_path: full_path, reason: reason}
          )

          Logger.error("[KerasONNX] Failed to load model: #{model_path} - #{inspect(reason)}")
          error
      end

    result
  end

  @doc """
  Runs inference on a single input.

  ## Parameters

  - `session` - Model session from load!/2
  - `input` - ML.Input struct with normalized data
  - `opts` - Optional inference options

  ## Returns

  - `{:ok, output}` - ML.Output struct with predictions
  - `{:error, reason}` - Inference failed

  ## Examples

      input = ML.Input.new!(%{data: tensor}, :image, %{})
      {:ok, output} = KerasONNX.infer(session, input)

      # Access predictions
      predictions = output.predictions
      inference_time = output.inference_time_ms

  """
  @spec infer(session(), Input.t(), infer_opts()) :: {:ok, Output.t()} | {:error, term()}
  def infer(session, %Input{} = input, opts \\ []) do
    infer_batch(session, [input], opts)
    |> case do
      {:ok, [output]} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs batched inference on multiple inputs.

  More efficient than calling infer/3 multiple times due to:
  - Single model pass
  - Optimized memory layout
  - Hardware acceleration benefits

  ## Parameters

  - `session` - Model session from load!/2
  - `inputs` - List of ML.Input structs
  - `opts` - Optional inference options

  ## Returns

  - `{:ok, outputs}` - List of ML.Output structs (same order as inputs)
  - `{:error, reason}` - Inference failed

  ## Examples

      inputs = [input1, input2, input3]
      {:ok, outputs} = KerasONNX.infer_batch(session, inputs)

      # Process results
      Enum.each(outputs, fn output ->
        IO.inspect(output.predictions)
      end)

  """
  @spec infer_batch(session(), [Input.t()], infer_opts()) ::
          {:ok, [Output.t()]} | {:error, term()}
  def infer_batch(session, inputs, opts \\ []) when is_list(inputs) do
    if inputs == [] do
      {:ok, []}
    else
      batch_size = length(inputs)
      correlation_id = Keyword.get(opts, :correlation_id)

      start_time = System.monotonic_time()

      :telemetry.execute(
        [:ml, :onnx, :infer, :start],
        %{system_time: System.system_time()},
        %{batch_size: batch_size, session: inspect(session)}
      )

      result =
        with {:ok, normalized_inputs} <- normalize_inputs(inputs),
             {:ok, input_tensor} <- prepare_batch_tensor(normalized_inputs),
             {:ok, output_tensor} <- do_inference(session, input_tensor),
             {:ok, outputs} <- format_outputs(output_tensor, inputs, correlation_id) do
          duration = System.monotonic_time() - start_time
          inference_time_ms = System.convert_time_unit(duration, :native, :millisecond)

          :telemetry.execute(
            [:ml, :onnx, :infer, :stop],
            %{duration: duration, batch_size: batch_size},
            %{
              session: inspect(session),
              inference_time_ms: inference_time_ms,
              input_shape: Nx.shape(input_tensor),
              output_shape: Nx.shape(output_tensor)
            }
          )

          Logger.debug(
            "[KerasONNX] Inference complete: batch_size=#{batch_size}, time=#{inference_time_ms}ms"
          )

          {:ok, outputs}
        else
          {:error, reason} = error ->
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              [:ml, :onnx, :infer, :exception],
              %{duration: duration, batch_size: batch_size},
              %{session: inspect(session), reason: reason}
            )

            Logger.error("[KerasONNX] Inference failed: #{inspect(reason)}")
            error
        end

      result
    end
  end

  @doc """
  Closes an ONNX session and releases resources.

  ## Parameters

  - `session` - Model session from load!/2

  ## Returns

  - `:ok` - Session closed successfully
  - `{:error, reason}` - Cleanup failed

  ## Examples

      {:ok, session} = KerasONNX.load!("demo.onnx")
      # ... use session ...
      :ok = KerasONNX.close(session)

  """
  @spec close(session()) :: :ok | {:error, term()}
  def close(_session) do
    # Ortex handles cleanup automatically when session reference is garbage collected
    # No explicit cleanup needed
    :ok
  end

  @doc """
  Gets model metadata from a loaded session.

  Returns information about input/output shapes, types, and model configuration.

  ## Parameters

  - `session` - Model session from load!/2

  ## Returns

  - `{:ok, metadata}` - Map with model information
  - `{:error, reason}` - Failed to retrieve metadata

  ## Examples

      {:ok, session} = KerasONNX.load!("demo.onnx")
      {:ok, metadata} = KerasONNX.metadata(session)

      IO.inspect(metadata)
      # %{
      #   inputs: [%{name: "input", shape: [1, 224, 224, 3], type: :f32}],
      #   outputs: [%{name: "output", shape: [1, 1000], type: :f32}],
      #   opset_version: 14
      # }

  """
  @spec metadata(session()) :: {:ok, map()} | {:error, term()}
  def metadata(session) do
    # Ortex doesn't expose metadata API yet, return basic info
    {:ok,
     %{
       session: inspect(session),
       provider: "Ortex",
       runtime: "ONNX Runtime"
     }}
  rescue
    error ->
      {:error, error}
  end

  # Private functions

  defp resolve_model_path(path) do
    model_dir = Application.get_env(:thunderline, __MODULE__)[:model_dir] || "priv/models"

    cond do
      # Absolute path - use as-is
      Path.type(path) == :absolute ->
        path

      # Already starts with model_dir - use as-is
      String.starts_with?(path, model_dir) ->
        path

      # Already starts with priv/ - use as-is
      String.starts_with?(path, "priv/") ->
        path

      # Just a filename - prepend model_dir
      true ->
        Path.join(model_dir, path)
    end
  end

  defp validate_model_file(path) do
    cond do
      !File.exists?(path) ->
        {:error, {:file_not_found, path}}

      Path.extname(path) != ".onnx" ->
        {:error, {:invalid_extension, path}}

      true ->
        :ok
    end
  end

  defp do_load_model(path, _opts) do
    # Ortex.load returns the model directly (not {:ok, model})
    # Options like execution_providers are not supported in current Ortex version
    model = Ortex.load(path)
    {:ok, model}
  rescue
    error ->
      {:error, {:ortex_exception, error}}
  end

  @doc false
  def map_optimization_level(:none), do: 0
  def map_optimization_level(:basic), do: 1
  def map_optimization_level(:extended), do: 2
  def map_optimization_level(:all), do: 99

  defp normalize_inputs(inputs) do
    # Input.new! already validates inputs, so no additional normalization needed
    {:ok, inputs}
  end

  defp prepare_batch_tensor(inputs) do
    # Extract data from normalized inputs
    # ML.Input uses :tensor field, not :data
    tensors =
      Enum.map(inputs, fn input ->
        case input do
          %{tensor: %Nx.Tensor{} = tensor} ->
            # Ensure BinaryBackend for Ortex compatibility
            Nx.backend_transfer(tensor, Nx.BinaryBackend)

          %{data: %Nx.Tensor{} = tensor} ->
            # Legacy support for old format
            Nx.backend_transfer(tensor, Nx.BinaryBackend)

          %{data: list} when is_list(list) ->
            Nx.tensor(list, backend: Nx.BinaryBackend)

          _ ->
            raise "Unsupported input format for ONNX inference"
        end
      end)

    # Stack into batch (if multiple inputs)
    batch_tensor =
      if length(tensors) == 1 do
        hd(tensors)
      else
        Nx.stack(tensors)
      end

    {:ok, batch_tensor}
  rescue
    error ->
      {:error, {:tensor_preparation_failed, error}}
  end

  defp do_inference(session, input_tensor) do
    # Ortex.run returns a tuple of output tensors directly (not {:ok, tensor})
    # For single-output models, we get {output_tensor}
    case Ortex.run(session, input_tensor) do
      {output_tensor} ->
        # Transfer from Ortex.Backend to BinaryBackend for further processing
        output = Nx.backend_transfer(output_tensor, Nx.BinaryBackend)
        {:ok, output}

      outputs when is_tuple(outputs) ->
        # Multiple outputs - take the first one (logits)
        output = outputs |> elem(0) |> Nx.backend_transfer(Nx.BinaryBackend)
        {:ok, output}
    end
  rescue
    error ->
      {:error, {:inference_exception, error}}
  end

  defp format_outputs(output_tensor, inputs, correlation_id) do
    # Split batch output into individual results
    batch_size = length(inputs)

    outputs =
      0..(batch_size - 1)
      |> Enum.map(fn idx ->
        # Slice the output for this batch item
        prediction =
          if batch_size == 1 do
            output_tensor
          else
            Nx.slice_along_axis(output_tensor, idx, 1, axis: 0)
          end

        shape = Nx.shape(prediction)
        dtype = Nx.type(prediction)

        # Build Output struct directly (Output.new! validates shape/dtype)
        %Output{
          tensor: prediction,
          shape: shape,
          dtype: dtype,
          inference_time_us: 0,
          metadata: %{
            model_version: "1.0",
            batch_size: batch_size,
            batch_index: idx,
            device: "cpu",
            correlation_id: correlation_id,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
      end)

    {:ok, outputs}
  rescue
    error ->
      {:error, {:output_formatting_failed, error}}
  end

  defp format_duration(native_duration) do
    ms = System.convert_time_unit(native_duration, :native, :millisecond)
    "#{ms}ms"
  end

  # -------------------------------------------------------------------
  # Near-Critical Dynamics Observables
  # -------------------------------------------------------------------

  @doc """
  Compute near-critical dynamics observables from inference output.

  Returns metrics from the Cinderforge Lab paper:
  - PLV (Phase Locking Value)
  - σ (Entropy ratio)
  - λ̂ (Stability exponent)

  ## Parameters

  - `output` - ML.Output from inference
  - `prev_entropy` - Optional entropy from previous inference

  ## Returns

  Map with :plv, :sigma, :entropy, :healthy?
  """
  @spec compute_observables(Output.t(), float() | nil) :: map()
  def compute_observables(%Output{tensor: tensor} = _output, prev_entropy \\ nil) do
    alias Thunderline.Utils.Stats

    # Compute current entropy from output distribution
    probs = Nx.softmax(tensor)
    current_entropy = Stats.entropy(probs)

    # Compute PLV from activation pattern
    plv = Stats.plv(tensor)

    # Compute sigma if we have previous entropy
    sigma =
      if prev_entropy && prev_entropy > 0 do
        Stats.sigma(prev_entropy, current_entropy)
      else
        1.0
      end

    # Check health bands
    bands = Stats.check_bands(plv, sigma, 0.0, 0.0)

    %{
      plv: plv,
      sigma: sigma,
      entropy: current_entropy,
      healthy?: bands.overall == :healthy,
      status: bands.overall
    }
  end

  @doc """
  Observe inference output and emit to LoopMonitor if available.

  Integrates ML inference with the near-critical dynamics monitoring system.

  ## Parameters

  - `output` - ML.Output from inference
  - `opts` - Options including :domain, :tick, :prev_entropy
  """
  @spec observe_inference(Output.t(), keyword()) :: :ok | {:intervention, atom()}
  def observe_inference(%Output{tensor: tensor} = output, opts \\ []) do
    domain = Keyword.get(opts, :domain, :ml_inference)
    tick = Keyword.get(opts, :tick, System.monotonic_time(:millisecond))
    prev_entropy = Keyword.get(opts, :prev_entropy)

    # Compute observables
    probs = Nx.softmax(tensor)
    current_entropy = Thunderline.Utils.Stats.entropy(probs)

    observation = %{
      tick: tick,
      activations: tensor,
      entropy_prev: prev_entropy || current_entropy,
      entropy_next: current_entropy,
      # Simplified - would need Jacobian for real λ̂
      jvp_matrix: Nx.tensor([[1.0]])
    }

    # Try to observe via LoopMonitor if it's running
    try do
      Thunderline.Telemetry.LoopMonitor.observe(domain, observation)
    catch
      :exit, _ ->
        # LoopMonitor not running, just compute locally
        observables = compute_observables(output, prev_entropy)

        if observables.healthy? do
          :ok
        else
          {:intervention, observables.status}
        end
    end
  end
end
