defmodule Thunderline.Thunderbolt.UPM.SGD do
  @moduledoc """
  Real SGD (Stochastic Gradient Descent) implementation for UPM using Nx.

  This module implements online learning for the Unified Persistent Model:
  - Forward pass through a simple MLP
  - MSE loss computation
  - Gradient computation via numerical differentiation
  - Parameter updates with learning rate

  ## Architecture

  A simple 2-layer MLP suitable for online learning:
  - Input: feature_dim → hidden_dim (with ReLU)
  - Hidden: hidden_dim → output_dim (linear)

  ## Usage

      params = SGD.initialize_params(feature_dim: 64, hidden_dim: 128, output_dim: 32)
      {loss, new_params} = SGD.update(features, labels, params, learning_rate: 0.01)
  """

  require Logger

  @default_feature_dim 64
  @default_hidden_dim 128
  @default_output_dim 32
  # Numerical stability constant (reserved for future gradient clipping)
  @_epsilon 1.0e-7

  @doc """
  Initialize model parameters with Xavier/Glorot initialization.

  ## Options
    - `:feature_dim` - Input dimension (default: 64)
    - `:hidden_dim` - Hidden layer dimension (default: 128)
    - `:output_dim` - Output dimension (default: 32)
    - `:seed` - Random seed for reproducibility
  """
  @spec initialize_params(keyword()) :: map()
  def initialize_params(opts \\ []) do
    feature_dim = Keyword.get(opts, :feature_dim, @default_feature_dim)
    hidden_dim = Keyword.get(opts, :hidden_dim, @default_hidden_dim)
    output_dim = Keyword.get(opts, :output_dim, @default_output_dim)
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))

    key = Nx.Random.key(seed)

    # Xavier initialization scale
    scale_w1 = :math.sqrt(2.0 / (feature_dim + hidden_dim))
    scale_w2 = :math.sqrt(2.0 / (hidden_dim + output_dim))

    {w1, key} = Nx.Random.normal(key, 0.0, scale_w1, shape: {feature_dim, hidden_dim})
    {b1, key} = Nx.Random.normal(key, 0.0, 0.01, shape: {hidden_dim})
    {w2, key} = Nx.Random.normal(key, 0.0, scale_w2, shape: {hidden_dim, output_dim})
    {b2, _key} = Nx.Random.normal(key, 0.0, 0.01, shape: {output_dim})

    %{
      w1: w1,
      b1: b1,
      w2: w2,
      b2: b2,
      version: 1,
      feature_dim: feature_dim,
      hidden_dim: hidden_dim,
      output_dim: output_dim,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Perform a single SGD update step.

  Returns `{loss, updated_params}` tuple.

  ## Options
    - `:learning_rate` - Step size (default: 0.001)
    - `:momentum` - Momentum coefficient (default: 0.0)
    - `:weight_decay` - L2 regularization (default: 0.0)
  """
  @spec update(Nx.Tensor.t(), Nx.Tensor.t(), map(), keyword()) :: {float(), map()}
  def update(features, labels, params, opts \\ []) do
    learning_rate = Keyword.get(opts, :learning_rate, 0.001)
    weight_decay = Keyword.get(opts, :weight_decay, 0.0)

    # Ensure tensors
    features = ensure_tensor(features, params.feature_dim)
    labels = ensure_tensor(labels, params.output_dim)

    # Forward pass
    {predictions, hidden_activations} = forward(features, params)

    # Compute loss (MSE)
    loss = mse_loss(predictions, labels)

    # Compute gradients via backprop
    gradients = backward(features, labels, predictions, hidden_activations, params)

    # Apply updates with optional weight decay
    updated_params =
      params
      |> update_param(:w1, gradients.dw1, learning_rate, weight_decay)
      |> update_param(:b1, gradients.db1, learning_rate, 0.0)
      |> update_param(:w2, gradients.dw2, learning_rate, weight_decay)
      |> update_param(:b2, gradients.db2, learning_rate, 0.0)
      |> Map.put(:version, params.version + 1)
      |> Map.put(:updated_at, DateTime.utc_now())

    loss_value = Nx.to_number(loss)
    {loss_value, updated_params}
  end

  @doc """
  Forward pass through the network.

  Returns `{output, hidden_activations}` for use in backprop.
  """
  @spec forward(Nx.Tensor.t(), map()) :: {Nx.Tensor.t(), Nx.Tensor.t()}
  def forward(features, params) do
    # Layer 1: features @ W1 + b1, then ReLU
    z1 = Nx.add(Nx.dot(features, params.w1), params.b1)
    h1 = relu(z1)

    # Layer 2: h1 @ W2 + b2 (linear output)
    z2 = Nx.add(Nx.dot(h1, params.w2), params.b2)

    {z2, h1}
  end

  @doc """
  Inference-only forward pass (returns just predictions).
  """
  @spec predict(Nx.Tensor.t(), map()) :: Nx.Tensor.t()
  def predict(features, params) do
    {predictions, _hidden} = forward(features, params)
    predictions
  end

  @doc """
  Compute MSE loss between predictions and labels.
  """
  @spec mse_loss(Nx.Tensor.t(), Nx.Tensor.t()) :: Nx.Tensor.t()
  def mse_loss(predictions, labels) do
    diff = Nx.subtract(predictions, labels)
    Nx.mean(Nx.pow(diff, 2))
  end

  # ═══════════════════════════════════════════════════════════════
  # BACKPROPAGATION
  # ═══════════════════════════════════════════════════════════════

  defp backward(features, labels, predictions, hidden, params) do
    batch_size = elem(Nx.shape(features), 0)
    scale = Nx.tensor(1.0 / batch_size)

    # Output layer gradient: d(MSE)/d(z2) = 2 * (pred - label) / batch_size
    d_z2 = Nx.multiply(Nx.subtract(predictions, labels), Nx.tensor(2.0))
    d_z2 = Nx.multiply(d_z2, scale)

    # Gradients for W2 and b2
    dw2 = Nx.dot(Nx.transpose(hidden), d_z2)
    db2 = Nx.sum(d_z2, axes: [0])

    # Backprop through hidden layer
    d_h1 = Nx.dot(d_z2, Nx.transpose(params.w2))

    # ReLU gradient: 1 if h > 0, else 0
    d_z1 = Nx.multiply(d_h1, relu_grad(hidden))

    # Gradients for W1 and b1
    dw1 = Nx.dot(Nx.transpose(features), d_z1)
    db1 = Nx.sum(d_z1, axes: [0])

    %{dw1: dw1, db1: db1, dw2: dw2, db2: db2}
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIVATION FUNCTIONS
  # ═══════════════════════════════════════════════════════════════

  defp relu(x), do: Nx.max(x, 0)

  defp relu_grad(x) do
    # 1 where x > 0, 0 elsewhere
    Nx.greater(x, 0)
    |> Nx.select(Nx.tensor(1.0), Nx.tensor(0.0))
  end

  # ═══════════════════════════════════════════════════════════════
  # PARAMETER UPDATES
  # ═══════════════════════════════════════════════════════════════

  defp update_param(params, key, gradient, lr, weight_decay) do
    param = Map.fetch!(params, key)

    # Apply weight decay (L2 regularization)
    decay_term =
      if weight_decay > 0.0 do
        Nx.multiply(param, weight_decay)
      else
        Nx.tensor(0.0)
      end

    # SGD update: param = param - lr * (gradient + weight_decay * param)
    update = Nx.add(gradient, decay_term)
    new_param = Nx.subtract(param, Nx.multiply(update, lr))

    Map.put(params, key, new_param)
  end

  # ═══════════════════════════════════════════════════════════════
  # TENSOR UTILITIES
  # ═══════════════════════════════════════════════════════════════

  defp ensure_tensor(data, expected_dim) when is_list(data) do
    tensor = Nx.tensor(data)
    ensure_shape(tensor, expected_dim)
  end

  defp ensure_tensor(%Nx.Tensor{} = tensor, expected_dim) do
    ensure_shape(tensor, expected_dim)
  end

  defp ensure_tensor(data, expected_dim) when is_map(data) do
    # Convert map to list of values, pad/truncate to expected_dim
    values =
      data
      |> Map.values()
      |> Enum.flat_map(&extract_numeric/1)
      |> pad_or_truncate(expected_dim)

    Nx.tensor([values])
  end

  defp ensure_tensor(data, expected_dim) when is_number(data) do
    Nx.tensor([[data | List.duplicate(0.0, expected_dim - 1)]])
  end

  defp ensure_shape(tensor, expected_dim) do
    case Nx.shape(tensor) do
      {^expected_dim} ->
        # Single sample, add batch dimension
        Nx.reshape(tensor, {1, expected_dim})

      {_batch, ^expected_dim} ->
        tensor

      {batch, actual_dim} when actual_dim < expected_dim ->
        # Pad with zeros
        padding = Nx.broadcast(0.0, {batch, expected_dim - actual_dim})
        Nx.concatenate([tensor, padding], axis: 1)

      {batch, actual_dim} when actual_dim > expected_dim ->
        # Truncate
        Nx.slice(tensor, [0, 0], [batch, expected_dim])

      other ->
        Logger.warning("[UPM.SGD] Unexpected tensor shape: #{inspect(other)}, reshaping")
        Nx.reshape(tensor, {1, expected_dim})
    end
  end

  defp extract_numeric(value) when is_number(value), do: [value * 1.0]
  defp extract_numeric(value) when is_list(value), do: Enum.flat_map(value, &extract_numeric/1)
  defp extract_numeric(_), do: []

  defp pad_or_truncate(list, target_len) when length(list) >= target_len do
    Enum.take(list, target_len)
  end

  defp pad_or_truncate(list, target_len) do
    list ++ List.duplicate(0.0, target_len - length(list))
  end

  # ═══════════════════════════════════════════════════════════════
  # SERIALIZATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Serialize parameters to binary for snapshot storage.
  """
  @spec serialize(map()) :: binary()
  def serialize(params) do
    serializable =
      params
      |> Map.update(:w1, nil, &Nx.to_binary/1)
      |> Map.update(:b1, nil, &Nx.to_binary/1)
      |> Map.update(:w2, nil, &Nx.to_binary/1)
      |> Map.update(:b2, nil, &Nx.to_binary/1)

    :erlang.term_to_binary(serializable)
  end

  @doc """
  Deserialize parameters from binary.
  """
  @spec deserialize(binary()) :: map()
  def deserialize(binary) do
    params = :erlang.binary_to_term(binary)

    %{
      params
      | w1:
          Nx.from_binary(params.w1, :f32) |> Nx.reshape({params.feature_dim, params.hidden_dim}),
        b1: Nx.from_binary(params.b1, :f32) |> Nx.reshape({params.hidden_dim}),
        w2: Nx.from_binary(params.w2, :f32) |> Nx.reshape({params.hidden_dim, params.output_dim}),
        b2: Nx.from_binary(params.b2, :f32) |> Nx.reshape({params.output_dim})
    }
  end
end
