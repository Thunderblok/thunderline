defmodule Thunderline.ML.Input do
  @moduledoc """
  Normalized input structure for ML inference.

  Provides a standardized interface for passing data to ML models (ONNX, TensorFlow, PyTorch, etc.)
  with automatic validation and normalization.

  ## Fields

  - `tensor` - Nx tensor containing the input data
  - `shape` - Expected tensor shape (e.g., `{1, 224, 224, 3}`)
  - `dtype` - Data type (`:f32`, `:f16`, `:s32`, etc.)
  - `metadata` - Optional metadata (preprocessing params, normalization constants, etc.)

  ## Examples

      # Image classification input
      input = %ML.Input{
        tensor: Nx.tensor([[[...]]]),  # Preprocessed image
        shape: {1, 224, 224, 3},
        dtype: :f32,
        metadata: %{
          mean: [0.485, 0.456, 0.406],
          std: [0.229, 0.224, 0.225],
          format: :hwc
        }
      }

      # Text embedding input (token IDs)
      input = %ML.Input{
        tensor: Nx.tensor([[101, 2054, 2003, ...]]),
        shape: {1, 512},
        dtype: :s32,
        metadata: %{
          tokenizer: "bert-base-uncased",
          max_length: 512
        }
      }
  """

  defstruct [
    :tensor,
    :shape,
    :dtype,
    :metadata
  ]

  @type t :: %__MODULE__{
          tensor: Nx.Tensor.t(),
          shape: tuple(),
          dtype: Nx.Type.t(),
          metadata: map()
        }

  @doc """
  Creates a new ML input with validation.

  ## Examples

      iex> ML.Input.new(Nx.tensor([[1.0, 2.0]]), {1, 2}, :f32)
      {:ok, %ML.Input{}}

      iex> ML.Input.new(Nx.tensor([[1]]), {1, 2}, :f32)
      {:error, :shape_mismatch}
  """
  @spec new(Nx.Tensor.t(), tuple(), Nx.Type.t(), map()) ::
          {:ok, t()} | {:error, atom()}
  def new(tensor, shape, dtype, metadata \\ %{}) do
    with :ok <- validate_tensor(tensor),
         :ok <- validate_shape(tensor, shape),
         :ok <- validate_dtype(tensor, dtype) do
      {:ok,
       %__MODULE__{
         tensor: tensor,
         shape: shape,
         dtype: dtype,
         metadata: metadata
       }}
    end
  end

  @doc """
  Creates a new ML input, raising on validation errors.
  """
  @spec new!(Nx.Tensor.t(), tuple(), Nx.Type.t(), map()) :: t()
  def new!(tensor, shape, dtype, metadata \\ %{}) do
    case new(tensor, shape, dtype, metadata) do
      {:ok, input} -> input
      {:error, reason} -> raise ArgumentError, "Invalid ML input: #{reason}"
    end
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
end
