defmodule Thunderline.Thunderbolt.Criticality.Propagation do
  @moduledoc """
  Propagation coefficient (σ) estimator for layer-to-layer activation flow.

  The propagation coefficient measures how information cascades through
  processing layers. At σ = 1.0, the system operates at the "edge of chaos"
  where complexity is maximized without runaway instability.

  ## Mathematical Foundation

  For layer activations a_l and a_{l+1}:

      σ = E[||a_{l+1}|| / ||a_l||]

  Where:
  - σ < 1.0: Activations decay (stagnant, ideas don't propagate)
  - σ = 1.0: Critical regime (edge of chaos)
  - σ > 1.0: Activations amplify (runaway, hallucinations)

  ## Interpretation for PAC Agents

  - σ < 0.8: Stagnant - boost excitation
  - σ 0.8-1.2: Healthy - maintain
  - σ > 1.2: Runaway - dampen excitation

  ## Usage

      {:ok, sigma} = Propagation.estimate(layer_activations)
  """

  @type layer_activation :: list(float()) | %{values: list(float()), norm: float()}
  @type result :: {:ok, float()} | {:error, atom()}

  @doc """
  Estimates σ from a sequence of layer activations.

  ## Parameters

  - `activations` - List of layer activation vectors (outermost to innermost)
  - `opts` - Options:
    - `:method` - `:ratio` (default), `:jacobian`, `:gradient`
    - `:norm` - Norm type: `:l2` (default), `:l1`, `:inf`

  ## Returns

  `{:ok, sigma}` or `{:error, reason}`.
  """
  @spec estimate(list(layer_activation()), keyword()) :: result()
  def estimate(activations, opts \\ []) when is_list(activations) do
    method = Keyword.get(opts, :method, :ratio)
    norm_type = Keyword.get(opts, :norm, :l2)

    case method do
      :ratio -> estimate_ratio(activations, norm_type)
      :jacobian -> estimate_jacobian(activations, opts)
      :gradient -> estimate_gradient(activations, norm_type)
      _ -> {:error, :unknown_method}
    end
  end

  @doc """
  Estimates σ from consecutive layer pairs.
  Returns individual ratios for each transition.
  """
  @spec layer_ratios(list(layer_activation()), keyword()) ::
          {:ok, list(float())} | {:error, atom()}
  def layer_ratios(activations, opts \\ []) do
    norm_type = Keyword.get(opts, :norm, :l2)

    if length(activations) < 2 do
      {:error, :insufficient_layers}
    else
      norms = Enum.map(activations, &compute_norm(&1, norm_type))

      ratios =
        norms
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] ->
          if prev > 1.0e-10, do: curr / prev, else: 1.0
        end)

      {:ok, ratios}
    end
  end

  @doc """
  Computes the spectral radius approximation (largest eigenvalue magnitude).
  More accurate but computationally expensive.
  """
  @spec spectral_radius(list(layer_activation())) :: result()
  def spectral_radius(activations) when is_list(activations) do
    if length(activations) < 3 do
      {:error, :insufficient_samples}
    else
      # Power iteration approximation
      # For production: use proper eigenvalue solver or Nx
      estimate_power_iteration(activations)
    end
  end

  # ===========================================================================
  # Private: Estimation Methods
  # ===========================================================================

  defp estimate_ratio(activations, norm_type) do
    case layer_ratios(activations, norm: norm_type) do
      {:ok, [_ | _] = ratios} ->
        # Geometric mean of ratios
        product = Enum.reduce(ratios, 1.0, &(&1 * &2))
        sigma = :math.pow(product, 1.0 / length(ratios))
        {:ok, sigma}

      {:ok, []} ->
        {:error, :insufficient_layers}

      error ->
        error
    end
  end

  defp estimate_jacobian(activations, opts) do
    # Jacobian-based estimation using finite differences
    epsilon = Keyword.get(opts, :epsilon, 1.0e-5)

    if length(activations) < 2 do
      {:error, :insufficient_layers}
    else
      # Approximate Jacobian spectral norm
      jacobian_norms =
        activations
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] ->
          approximate_jacobian_norm(prev, curr, epsilon)
        end)

      if length(jacobian_norms) > 0 do
        sigma = Enum.sum(jacobian_norms) / length(jacobian_norms)
        {:ok, sigma}
      else
        {:error, :computation_failed}
      end
    end
  end

  defp estimate_gradient(activations, norm_type) do
    # Gradient-based estimation (norm of activation differences)
    if length(activations) < 2 do
      {:error, :insufficient_layers}
    else
      gradients =
        activations
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] ->
          diff = activation_difference(prev, curr)
          prev_norm = compute_norm(prev, norm_type)

          if prev_norm > 1.0e-10 do
            compute_norm(diff, norm_type) / prev_norm
          else
            0.0
          end
        end)

      sigma = 1.0 + Enum.sum(gradients) / max(1, length(gradients))
      {:ok, sigma}
    end
  end

  # ===========================================================================
  # Private: Norm Computation
  # ===========================================================================

  defp compute_norm(%{norm: norm}, _type), do: norm

  defp compute_norm(%{values: values}, type), do: compute_norm(values, type)

  defp compute_norm(values, type) when is_list(values) do
    case type do
      :l2 -> l2_norm(values)
      :l1 -> l1_norm(values)
      :inf -> inf_norm(values)
      _ -> l2_norm(values)
    end
  end

  defp l2_norm(values) do
    values
    |> Enum.reduce(0.0, fn v, acc -> acc + v * v end)
    |> :math.sqrt()
  end

  defp l1_norm(values) do
    Enum.reduce(values, 0.0, fn v, acc -> acc + abs(v) end)
  end

  defp inf_norm(values) do
    values
    |> Enum.map(&abs/1)
    |> Enum.max(fn -> 0.0 end)
  end

  # ===========================================================================
  # Private: Jacobian Approximation
  # ===========================================================================

  defp approximate_jacobian_norm(prev, curr, _epsilon) do
    prev_values = extract_values(prev)
    curr_values = extract_values(curr)

    prev_norm = l2_norm(prev_values)
    curr_norm = l2_norm(curr_values)

    if prev_norm > 1.0e-10 do
      curr_norm / prev_norm
    else
      1.0
    end
  end

  defp extract_values(%{values: v}), do: v
  defp extract_values(v) when is_list(v), do: v

  defp activation_difference(prev, curr) do
    prev_values = extract_values(prev)
    curr_values = extract_values(curr)

    # Pad shorter list with zeros
    max_len = max(length(prev_values), length(curr_values))
    prev_padded = pad_list(prev_values, max_len)
    curr_padded = pad_list(curr_values, max_len)

    Enum.zip(prev_padded, curr_padded)
    |> Enum.map(fn {p, c} -> c - p end)
  end

  defp pad_list(list, target_len) do
    current_len = length(list)

    if current_len >= target_len do
      list
    else
      list ++ List.duplicate(0.0, target_len - current_len)
    end
  end

  # ===========================================================================
  # Private: Power Iteration
  # ===========================================================================

  defp estimate_power_iteration(activations) do
    # Simplified power iteration for spectral radius
    # Treats activation sequence as implicit linear operator

    norms = Enum.map(activations, &compute_norm(&1, :l2))

    # Look at growth rate over sequence
    if length(norms) < 3 or Enum.all?(norms, &(&1 < 1.0e-10)) do
      {:ok, 1.0}
    else
      # Fit exponential growth: ||a_k|| ≈ ||a_0|| * σ^k
      # Take log and do linear regression for slope
      log_norms =
        norms
        |> Enum.filter(&(&1 > 1.0e-10))
        |> Enum.map(&:math.log/1)

      if length(log_norms) < 2 do
        {:ok, 1.0}
      else
        # Simple slope estimation
        n = length(log_norms)
        first = hd(log_norms)
        last = List.last(log_norms)
        slope = (last - first) / max(1, n - 1)
        sigma = :math.exp(slope)

        {:ok, max(0.1, min(10.0, sigma))}
      end
    end
  end

  # ===========================================================================
  # Streaming API
  # ===========================================================================

  @doc """
  Creates a streaming propagation estimator state.
  """
  @spec stream_init(keyword()) :: map()
  def stream_init(opts \\ []) do
    window_size = Keyword.get(opts, :window_size, 10)
    ema_alpha = Keyword.get(opts, :ema_alpha, 0.3)

    %{
      recent_ratios: :queue.new(),
      window_size: window_size,
      ema_alpha: ema_alpha,
      current_sigma: 1.0,
      prev_activation: nil
    }
  end

  @doc """
  Updates streaming σ with a new layer activation.
  """
  @spec stream_update(map(), layer_activation()) :: {float(), map()}
  def stream_update(state, activation) do
    case state.prev_activation do
      nil ->
        {state.current_sigma, %{state | prev_activation: activation}}

      prev ->
        prev_norm = compute_norm(prev, :l2)
        curr_norm = compute_norm(activation, :l2)

        ratio =
          if prev_norm > 1.0e-10 do
            curr_norm / prev_norm
          else
            1.0
          end

        # Update queue
        ratios = :queue.in(ratio, state.recent_ratios)

        ratios =
          if :queue.len(ratios) > state.window_size do
            {_, new_q} = :queue.out(ratios)
            new_q
          else
            ratios
          end

        # EMA update
        new_sigma =
          state.ema_alpha * ratio +
            (1 - state.ema_alpha) * state.current_sigma

        new_state = %{
          state
          | recent_ratios: ratios,
            current_sigma: new_sigma,
            prev_activation: activation
        }

        {new_sigma, new_state}
    end
  end
end
