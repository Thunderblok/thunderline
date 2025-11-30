defmodule Thunderline.Thunderbolt.DiffLogic.Network do
  @moduledoc """
  Deep Differentiable Logic Gate Network.

  A multi-layer network of learned logic gates that can be trained with gradient
  descent and executed extremely fast (1M+ MNIST/sec on single CPU).

  ## Architecture

  ```
  Input Layer (binary/continuous features)
       │
       ▼
  ┌─────────────────┐
  │  Gate Layer 1   │  n_gates pairs → n_gates outputs
  └─────────────────┘
       │
       ▼
  ┌─────────────────┐
  │  Gate Layer 2   │
  └─────────────────┘
       │
       ▼
      ...
       │
       ▼
  ┌─────────────────┐
  │  Output Layer   │  Aggregation to final output
  └─────────────────┘
  ```

  ## Training

  Uses straight-through estimator for differentiable discrete gate selection.
  The network learns which gate to use at each position.

  ## Inference

  After training, discretize the gate selections for blazing fast inference
  using pure boolean operations.

  ## Reference

  Petersen et al., "Deep Differentiable Logic Gate Networks", NeurIPS 2022
  """

  alias Thunderline.Thunderbolt.DiffLogic.Gates

  @doc """
  Create a new DiffLogic network.

  ## Options

  - `:input_dim` - Number of input features (default: 64)
  - `:hidden_dims` - List of hidden layer sizes (default: [32, 16])
  - `:output_dim` - Number of outputs (default: 1)
  - `:seed` - Random seed
  """
  def new(opts \\ []) do
    input_dim = Keyword.get(opts, :input_dim, 64)
    hidden_dims = Keyword.get(opts, :hidden_dims, [32, 16])
    output_dim = Keyword.get(opts, :output_dim, 1)
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))

    # Build layer configurations
    all_dims = [input_dim | hidden_dims] ++ [output_dim]
    
    layers =
      all_dims
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.map(fn {[in_dim, out_dim], idx} ->
        # Each layer needs in_dim inputs to produce out_dim outputs
        # We need ceil(in_dim / 2) gates that each take 2 inputs
        n_gates = max(out_dim, div(in_dim, 2))
        
        %{
          name: "layer_#{idx}",
          input_dim: in_dim,
          output_dim: out_dim,
          n_gates: n_gates,
          gate_logits: Gates.initialize_gate_logits(
            n_gates: n_gates,
            init: :uniform,
            seed: seed + idx
          )
        }
      end)

    %{
      input_dim: input_dim,
      output_dim: output_dim,
      hidden_dims: hidden_dims,
      layers: layers,
      version: 1,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Forward pass through the network (differentiable, for training).
  """
  def forward(inputs, params) do
    # Normalize inputs to [0, 1]
    x = Nx.sigmoid(inputs)
    
    # Apply each layer
    Enum.reduce(params.layers, x, fn layer, acc ->
      apply_layer(acc, layer)
    end)
  end

  defp apply_layer(inputs, layer) do
    gate_logits = layer.gate_logits
    output_dim = layer.output_dim
    
    # Ensure we have enough inputs by padding/repeating
    input_shape = Nx.shape(inputs)
    
    padded_inputs = 
      case Nx.rank(inputs) do
        1 ->
          current_size = elem(input_shape, 0)
          needed = layer.n_gates * 2
          
          if current_size >= needed do
            Nx.slice(inputs, [0], [needed])
          else
            # Repeat inputs to fill
            repeats = div(needed, current_size) + 1
            tiled = Nx.tile(inputs, [repeats])
            Nx.slice(tiled, [0], [needed])
          end
          
        2 ->
          {batch_size, current_size} = input_shape
          needed = layer.n_gates * 2
          
          if current_size >= needed do
            Nx.slice(inputs, [0, 0], [batch_size, needed])
          else
            repeats = div(needed, current_size) + 1
            tiled = Nx.tile(inputs, [1, repeats])
            Nx.slice(tiled, [0, 0], [batch_size, needed])
          end
      end
    
    # Split into a and b for gate layer
    half = layer.n_gates
    {a_inputs, b_inputs} = 
      case Nx.rank(padded_inputs) do
        1 ->
          {Nx.slice(padded_inputs, [0], [half]),
           Nx.slice(padded_inputs, [half], [half])}
        2 ->
          {batch_size, _} = Nx.shape(padded_inputs)
          {Nx.slice(padded_inputs, [0, 0], [batch_size, half]),
           Nx.slice(padded_inputs, [0, half], [batch_size, half])}
      end
    
    # Apply gate layer
    output = Gates.gate_layer({a_inputs, b_inputs}, gate_logits)
    
    # Reduce to output_dim if needed
    case Nx.rank(output) do
      1 ->
        current = elem(Nx.shape(output), 0)
        if current > output_dim do
          Nx.slice(output, [0], [output_dim])
        else
          output
        end
        
      2 ->
        {batch, current} = Nx.shape(output)
        if current > output_dim do
          Nx.slice(output, [0, 0], [batch, output_dim])
        else
          output
        end
    end
  end

  @doc """
  Fast discrete inference (after training).
  
  Uses discretized gates for maximum speed.
  """
  def infer_discrete(inputs, params) do
    # Discretize all gate selections
    discrete_layers =
      Enum.map(params.layers, fn layer ->
        %{layer | gate_indices: Gates.discretize(layer.gate_logits)}
      end)

    # Apply with boolean operations
    x = binarize(inputs)
    
    Enum.reduce(discrete_layers, x, fn layer, acc ->
      apply_discrete_layer(acc, layer)
    end)
  end

  defp binarize(tensor) do
    tensor
    |> Nx.greater(0.5)
    |> Nx.as_type(:u8)
  end

  defp apply_discrete_layer(inputs, layer) do
    inputs_list = Nx.to_flat_list(inputs)
    n_gates = layer.n_gates
    
    # Pad inputs
    needed = n_gates * 2
    padded = 
      if length(inputs_list) >= needed do
        Enum.take(inputs_list, needed)
      else
        inputs_list ++ List.duplicate(0, needed - length(inputs_list))
      end
    
    # Split into pairs and apply discrete gates
    {a_list, b_list} = Enum.split(padded, n_gates)
    
    outputs =
      [a_list, b_list, layer.gate_indices]
      |> Enum.zip()
      |> Enum.map(fn {a, b, gate_idx} ->
        apply_discrete_gate(a, b, gate_idx)
      end)
    
    Nx.tensor(Enum.take(outputs, layer.output_dim))
  end

  # Discrete boolean gate operations (blazing fast)
  defp apply_discrete_gate(a, b, 0), do: 0
  defp apply_discrete_gate(a, b, 1), do: band(a, b)
  defp apply_discrete_gate(a, b, 2), do: band(a, bnot(b))
  defp apply_discrete_gate(a, _b, 3), do: a
  defp apply_discrete_gate(a, b, 4), do: band(bnot(a), b)
  defp apply_discrete_gate(_a, b, 5), do: b
  defp apply_discrete_gate(a, b, 6), do: bxor(a, b)
  defp apply_discrete_gate(a, b, 7), do: bor(a, b)
  defp apply_discrete_gate(a, b, 8), do: bnot(bor(a, b))
  defp apply_discrete_gate(a, b, 9), do: bnot(bxor(a, b))
  defp apply_discrete_gate(_a, b, 10), do: bnot(b)
  defp apply_discrete_gate(a, b, 11), do: bor(bnot(a), b)
  defp apply_discrete_gate(a, _b, 12), do: bnot(a)
  defp apply_discrete_gate(a, b, 13), do: bor(a, bnot(b))
  defp apply_discrete_gate(a, b, 14), do: bnot(band(a, b))
  defp apply_discrete_gate(_a, _b, 15), do: 1
  defp apply_discrete_gate(_a, _b, _), do: 0

  defp band(a, b), do: if(a == 1 and b == 1, do: 1, else: 0)
  defp bor(a, b), do: if(a == 1 or b == 1, do: 1, else: 0)
  defp bxor(a, b), do: if(a != b, do: 1, else: 0)
  defp bnot(a), do: if(a == 1, do: 0, else: 1)

  # ═══════════════════════════════════════════════════════════════
  # TRAINING
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Train the network for one step.
  
  Returns `{loss, updated_params}`.
  """
  def train_step(inputs, targets, params, opts \\ []) do
    learning_rate = Keyword.get(opts, :learning_rate, 0.01)
    
    # Compute loss and gradients via numerical differentiation
    # (Simplified - real impl would use Nx.Defn.grad properly)
    loss = compute_loss(inputs, targets, params)
    
    # Gradient approximation using finite differences per layer
    epsilon = 1.0e-4
    
    updated_layers =
      Enum.map(params.layers, fn layer ->
        # Approximate gradient for each gate logit
        grad = approximate_gradient(inputs, targets, params, layer, epsilon)
        new_logits = Nx.subtract(
          layer.gate_logits,
          Nx.multiply(grad, learning_rate)
        )
        %{layer | gate_logits: new_logits}
      end)
    
    updated_params = %{params | layers: updated_layers, version: params.version + 1}
    
    {Nx.to_number(loss), updated_params}
  end

  defp compute_loss(inputs, targets, params) do
    predictions = forward(inputs, params)
    binary_cross_entropy(predictions, targets)
  end

  defp approximate_gradient(inputs, targets, params, layer, epsilon) do
    # Finite difference approximation
    {n_gates, 16} = Nx.shape(layer.gate_logits)
    base_loss = Nx.to_number(compute_loss(inputs, targets, params))
    
    # Create gradient tensor
    grads = 
      for i <- 0..(n_gates - 1) do
        for j <- 0..15 do
          # Perturb single logit
          perturbed_logits = perturb_at(layer.gate_logits, i, j, epsilon)
          perturbed_layer = %{layer | gate_logits: perturbed_logits}
          perturbed_params = update_layer_in_params(params, layer.name, perturbed_layer)
          
          perturbed_loss = Nx.to_number(compute_loss(inputs, targets, perturbed_params))
          (perturbed_loss - base_loss) / epsilon
        end
      end
    
    Nx.tensor(grads)
  end

  defp perturb_at(tensor, i, j, delta) do
    current = Nx.to_number(Nx.slice(tensor, [i, j], [1, 1]))
    indices = Nx.tensor([[i, j]])
    updates = Nx.tensor([[current + delta]])
    Nx.indexed_put(tensor, indices, updates)
  end

  defp update_layer_in_params(params, layer_name, new_layer) do
    updated_layers = Enum.map(params.layers, fn l ->
      if l.name == layer_name, do: new_layer, else: l
    end)
    %{params | layers: updated_layers}
  end

  defp binary_cross_entropy(predictions, targets) do
    eps = 1.0e-7
    clipped = Nx.clip(predictions, eps, 1.0 - eps)
    
    loss = Nx.negate(
      Nx.add(
        Nx.multiply(targets, Nx.log(clipped)),
        Nx.multiply(Nx.subtract(1.0, targets), Nx.log(Nx.subtract(1.0, clipped)))
      )
    )
    
    Nx.mean(loss)
  end

  # ═══════════════════════════════════════════════════════════════
  # SERIALIZATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Serialize network to binary.
  """
  def serialize(params) do
    serializable = %{
      params
      | layers: Enum.map(params.layers, fn layer ->
          %{layer | gate_logits: Nx.to_binary(layer.gate_logits)}
        end)
    }
    :erlang.term_to_binary(serializable)
  end

  @doc """
  Deserialize network from binary.
  """
  def deserialize(binary) do
    params = :erlang.binary_to_term(binary)
    
    %{
      params
      | layers: Enum.map(params.layers, fn layer ->
          %{
            layer
            | gate_logits:
                Nx.from_binary(layer.gate_logits, :f32)
                |> Nx.reshape({layer.n_gates, 16})
          }
        end)
    }
  end
end
