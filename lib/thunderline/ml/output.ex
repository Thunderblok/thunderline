defmodule Thunderline.ML.Output do
  @moduledoc """
  Normalized output structure for ML inference results.

  Provides a standardized interface for returning predictions from ML models
  with timing information and metadata.

  ## Fields

  - `tensor` - Nx tensor containing the model output
  - `shape` - Output tensor shape
  - `dtype` - Output data type
  - `inference_time_us` - Inference duration in microseconds
  - `metadata` - Optional metadata (confidence scores, class names, etc.)

  ## Examples

      # Classification output
      output = %ML.Output{
        tensor: Nx.tensor([[0.1, 0.7, 0.2]]),
        shape: {1, 3},
        dtype: :f32,
        inference_time_us: 1_250,
        metadata: %{
          class_names: ["cat", "dog", "bird"],
          predicted_class: "dog",
          confidence: 0.7
        }
      }

      # Embedding output
      output = %ML.Output{
        tensor: Nx.tensor([[0.1, -0.3, 0.5, ...]]),
        shape: {1, 768},
        dtype: :f32,
        inference_time_us: 850,
        metadata: %{
          model: "sentence-transformers/all-MiniLM-L6-v2",
          pooling: "mean"
        }
      }
  """

  defstruct [
    :tensor,
    :shape,
    :dtype,
    :inference_time_us,
    :metadata
  ]

  @type t :: %__MODULE__{
          tensor: Nx.Tensor.t(),
          shape: tuple(),
          dtype: Nx.Type.t(),
          inference_time_us: non_neg_integer(),
          metadata: map()
        }

  @doc """
  Creates a new ML output with validation.

  ## Examples

      iex> tensor = Nx.tensor([[0.1, 0.9]])
      iex> ML.Output.new(tensor, {1, 2}, :f32, 1000)
      {:ok, %ML.Output{}}
  """
  @spec new(Nx.Tensor.t(), tuple(), Nx.Type.t(), non_neg_integer(), map()) ::
          {:ok, t()} | {:error, atom()}
  def new(tensor, shape, dtype, inference_time_us, metadata \\ %{}) do
    with :ok <- validate_tensor(tensor),
         :ok <- validate_shape(tensor, shape),
         :ok <- validate_dtype(tensor, dtype),
         :ok <- validate_timing(inference_time_us) do
      {:ok,
       %__MODULE__{
         tensor: tensor,
         shape: shape,
         dtype: dtype,
         inference_time_us: inference_time_us,
         metadata: metadata
       }}
    end
  end

  @doc """
  Creates a new ML output, raising on validation errors.
  """
  @spec new!(Nx.Tensor.t(), tuple(), Nx.Type.t(), non_neg_integer(), map()) :: t()
  def new!(tensor, shape, dtype, inference_time_us, metadata \\ %{}) do
    case new(tensor, shape, dtype, inference_time_us, metadata) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "Invalid ML output: #{reason}"
    end
  end

  @doc """
  Extracts the top-k predictions from classification output.

  ## Examples

      iex> output = %ML.Output{
      ...>   tensor: Nx.tensor([[0.1, 0.7, 0.2]]),
      ...>   metadata: %{class_names: ["cat", "dog", "bird"]}
      ...> }
      iex> ML.Output.top_k(output, 2)
      [{"dog", 0.7}, {"bird", 0.2}]
  """
  @spec top_k(t(), pos_integer()) :: [{String.t(), float()}]
  def top_k(%__MODULE__{tensor: tensor, metadata: %{class_names: names}}, k) do
    # Flatten to 1D and get top k indices
    logits = Nx.flatten(tensor) |> Nx.to_flat_list()
    indexed_logits = Enum.with_index(logits)

    indexed_logits
    |> Enum.sort_by(fn {score, _idx} -> score end, :desc)
    |> Enum.take(k)
    |> Enum.map(fn {score, idx} ->
      {Enum.at(names, idx), score}
    end)
  end

  def top_k(%__MODULE__{}, _k) do
    raise ArgumentError, "Output metadata must include :class_names for top_k/2"
  end

  # Private validation functions

  defp validate_tensor(%Nx.Tensor{} = _tensor), do: :ok
  defp validate_tensor(_), do: {:error, :not_a_tensor}

  defp validate_shape(tensor, expected_shape) do
    actual_shape = Nx.shape(tensor)

    if actual_shape == expected_shape do
      :ok
    else
      {:error, :shape_mismatch}
    end
  end

  defp validate_dtype(tensor, expected_dtype) do
    actual_dtype = Nx.type(tensor)

    if actual_dtype == expected_dtype do
      :ok
    else
      {:error, :dtype_mismatch}
    end
  end

  defp validate_timing(time_us) when is_integer(time_us) and time_us >= 0, do: :ok
  defp validate_timing(_), do: {:error, :invalid_timing}
end
