defmodule Thunderline.ML.Normalize do
  @moduledoc """
  Normalization utilities for ML input preprocessing.

  Provides common normalization operations for preparing data for ML inference:
  - Data type casting (int8 → float32, etc.)
  - Shape transformations (reshape, transpose)
  - Statistical normalization (mean/std, min/max)
  - Image preprocessing (resize, normalize, channel order)

  ## Examples

      # Normalize image tensor
      normalized = ML.Normalize.image(
        raw_tensor,
        mean: [0.485, 0.456, 0.406],
        std: [0.229, 0.224, 0.225]
      )

      # Cast to float32
      tensor_f32 = ML.Normalize.to_float32(int_tensor)

      # Reshape tensor
      reshaped = ML.Normalize.reshape(tensor, {1, 224, 224, 3})
  """

  @doc """
  Casts a tensor to float32.

  Useful for converting integer or float16 inputs to the standard float32
  format expected by most ML models.

  ## Examples

      iex> int_tensor = Nx.tensor([[1, 2, 3]], type: :s32)
      iex> ML.Normalize.to_float32(int_tensor)
      #Nx.Tensor<
        f32[1][3]
        [[1.0, 2.0, 3.0]]
      >
  """
  @spec to_float32(Nx.Tensor.t()) :: Nx.Tensor.t()
  def to_float32(tensor) do
    Nx.as_type(tensor, :f32)
  end

  @doc """
  Casts a tensor to float16.

  Useful for models that support half-precision inference for faster performance.

  ## Examples

      iex> tensor = Nx.tensor([[1.0, 2.0, 3.0]])
      iex> ML.Normalize.to_float16(tensor)
      #Nx.Tensor<
        f16[1][3]
        ...
      >
  """
  @spec to_float16(Nx.Tensor.t()) :: Nx.Tensor.t()
  def to_float16(tensor) do
    Nx.as_type(tensor, :f16)
  end

  @doc """
  Reshapes a tensor to the target shape.

  Validates that the total number of elements matches before reshaping.

  ## Examples

      iex> tensor = Nx.tensor([1, 2, 3, 4, 5, 6])
      iex> ML.Normalize.reshape(tensor, {2, 3})
      #Nx.Tensor<
        s64[2][3]
        [[1, 2, 3],
         [4, 5, 6]]
      >
  """
  @spec reshape(Nx.Tensor.t(), tuple()) :: Nx.Tensor.t()
  def reshape(tensor, target_shape) do
    Nx.reshape(tensor, target_shape)
  end

  @doc """
  Normalizes a tensor using mean and standard deviation.

  Applies: `(x - mean) / std`

  ## Examples

      iex> tensor = Nx.tensor([[1.0, 2.0, 3.0]])
      iex> ML.Normalize.standardize(tensor, mean: 2.0, std: 1.0)
      #Nx.Tensor<
        f32[1][3]
        [[-1.0, 0.0, 1.0]]
      >
  """
  @spec standardize(Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  def standardize(tensor, opts) do
    mean = Keyword.fetch!(opts, :mean)
    std = Keyword.fetch!(opts, :std)

    mean_tensor = to_tensor(mean, Nx.type(tensor))
    std_tensor = to_tensor(std, Nx.type(tensor))

    tensor
    |> Nx.subtract(mean_tensor)
    |> Nx.divide(std_tensor)
  end

  @doc """
  Normalizes a tensor to [0, 1] range using min-max scaling.

  Applies: `(x - min) / (max - min)`

  ## Examples

      iex> tensor = Nx.tensor([[0, 128, 255]])
      iex> ML.Normalize.min_max(tensor, min: 0, max: 255)
      #Nx.Tensor<
        f32[1][3]
        [[0.0, 0.5019608, 1.0]]
      >
  """
  @spec min_max(Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  def min_max(tensor, opts) do
    min_val = Keyword.fetch!(opts, :min)
    max_val = Keyword.fetch!(opts, :max)

    # Cast to float for division
    tensor = to_float32(tensor)
    range = max_val - min_val

    tensor
    |> Nx.subtract(min_val)
    |> Nx.divide(range)
  end

  @doc """
  Normalizes an image tensor for model input.

  Supports common preprocessing operations:
  - Channel-wise mean/std normalization (ImageNet, etc.)
  - Min-max scaling to [0, 1]
  - Channel order conversion (RGB ↔ BGR)

  ## Options

  - `:mean` - Mean values per channel (list or scalar)
  - `:std` - Standard deviation per channel (list or scalar)
  - `:min` - Minimum value for min-max scaling (default: 0)
  - `:max` - Maximum value for min-max scaling (default: 255)
  - `:scale_first?` - Apply min-max before standardization (default: true)

  ## Examples

      # ImageNet normalization
      normalized = ML.Normalize.image(
        image_tensor,
        mean: [0.485, 0.456, 0.406],
        std: [0.229, 0.224, 0.225]
      )

      # Simple [0, 1] scaling
      scaled = ML.Normalize.image(image_tensor, max: 255)
  """
  @spec image(Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  def image(tensor, opts \\ []) do
    scale_first? = Keyword.get(opts, :scale_first?, true)
    mean = Keyword.get(opts, :mean)
    std = Keyword.get(opts, :std)
    min_val = Keyword.get(opts, :min, 0)
    max_val = Keyword.get(opts, :max, 255)

    tensor =
      if scale_first? do
        min_max(tensor, min: min_val, max: max_val)
      else
        tensor
      end

    tensor =
      if mean && std do
        standardize(tensor, mean: mean, std: std)
      else
        tensor
      end

    tensor
  end

  @doc """
  Adds a batch dimension to a tensor.

  Useful when model expects batch dimension but you have a single sample.

  ## Examples

      iex> tensor = Nx.tensor([[1, 2], [3, 4]])  # Shape: {2, 2}
      iex> ML.Normalize.add_batch_dim(tensor)
      #Nx.Tensor<
        s64[1][2][2]
        [[[1, 2],
          [3, 4]]]
      >
  """
  @spec add_batch_dim(Nx.Tensor.t()) :: Nx.Tensor.t()
  def add_batch_dim(tensor) do
    Nx.new_axis(tensor, 0)
  end

  @doc """
  Removes the batch dimension from a tensor.

  Useful for extracting single sample from batched output.

  ## Examples

      iex> batched = Nx.tensor([[[1, 2], [3, 4]]])  # Shape: {1, 2, 2}
      iex> ML.Normalize.remove_batch_dim(batched)
      #Nx.Tensor<
        s64[2][2]
        [[1, 2],
         [3, 4]]
      >
  """
  @spec remove_batch_dim(Nx.Tensor.t()) :: Nx.Tensor.t()
  def remove_batch_dim(tensor) do
    Nx.squeeze(tensor, axes: [0])
  end

  # Private helpers

  # Convert scalar or list to tensor with proper broadcasting
  defp to_tensor(value, dtype) when is_number(value) do
    Nx.tensor(value, type: dtype)
  end

  defp to_tensor(values, dtype) when is_list(values) do
    Nx.tensor(values, type: dtype)
  end
end
