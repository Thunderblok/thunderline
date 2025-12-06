defmodule Thunderline.Thunderbolt.Rules.NCA do
  @moduledoc """
  Neural Cellular Automata (NCA) rule backend.

  Wraps attention-based NCA update rules (ViTCA) to implement the Rule behaviour.
  NCA rules operate on entire grids rather than individual cells.

  ## Features

  - Attention-based perception (replaces fixed Sobel kernels)
  - Learnable update rules (MLP-based)
  - Stochastic cell firing for robustness
  - Side-quest metric emission

  ## Configuration

      params = NCA.init_params(
        hidden_channels: 16,
        update_prob: 0.5,
        variant: :vit_ca
      )

  ## Grid-Based Operation

  NCA rules use `step_grid/3` for efficient batch processing.
  The `update/3` callback is available but less efficient.

  ## Variants

  - `:vit_ca` - Vision Transformer CA (attention-based)
  - `:vit_ca_v2` - Enhanced ViT CA with improved attention

  ## Reference

  - Mordvintsev et al. "Growing Neural Cellular Automata" (2020)
  - HC Orders: Operation TIGER LATTICE
  """

  @behaviour Thunderline.Thunderbolt.Rule

  alias Thunderline.Thunderbolt.NCA.ViTCAUpdateRule
  alias Thunderline.Thunderbolt.NCA.ViTCAUpdateRuleV2

  # ═══════════════════════════════════════════════════════════════
  # Behaviour Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def backend_type, do: :nca

  @impl true
  def init_params(opts \\ []) do
    variant = Keyword.get(opts, :variant, :vit_ca)
    seed = Keyword.get(opts, :seed, System.system_time(:millisecond))

    # Initialize neural network parameters based on variant
    nn_params =
      case variant do
        :vit_ca -> ViTCAUpdateRule.initialize_params(seed: seed)
        :vit_ca_v2 -> ViTCAUpdateRuleV2.initialize_params(seed: seed)
        _ -> ViTCAUpdateRule.initialize_params(seed: seed)
      end

    Map.merge(nn_params, %{
      variant: variant,
      update_prob: Keyword.get(opts, :update_prob, 0.5),
      compute_metrics: Keyword.get(opts, :compute_metrics, true)
    })
  end

  @impl true
  def update(cell, neighbors, params) do
    # NCA operates on grids, not individual cells
    # This is a fallback that simulates a single-cell update
    # For proper NCA behavior, use step_grid/3

    # Convert cell and neighbors to a mini-grid
    # This is inefficient but maintains the interface contract

    new_cell =
      cell
      |> apply_neighbor_influence(neighbors, params)

    metrics = compute_cell_metrics(cell, new_cell, neighbors)

    {:ok, new_cell, metrics}
  end

  @impl true
  def step_grid(grid, params, opts \\ []) do
    variant = Map.get(params, :variant, :vit_ca)
    update_prob = Keyword.get(opts, :update_prob, Map.get(params, :update_prob, 0.5))

    # Dispatch to appropriate NCA variant
    new_grid =
      case variant do
        :vit_ca ->
          ViTCAUpdateRule.step(grid, params, update_prob: update_prob)

        :vit_ca_v2 ->
          ViTCAUpdateRuleV2.step(grid, params, update_prob: update_prob)

        _ ->
          ViTCAUpdateRule.step(grid, params, update_prob: update_prob)
      end

    # Compute grid-level side-quest metrics
    metrics =
      if Map.get(params, :compute_metrics, true) do
        compute_grid_metrics(grid, new_grid)
      else
        %{}
      end

    {:ok, new_grid, metrics}
  end

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  # Simplified single-cell update (fallback)
  defp apply_neighbor_influence(cell, neighbors, _params) do
    # Average neighbor states for a simple diffusion-like update
    if Enum.empty?(neighbors) do
      cell
    else
      avg_influence =
        neighbors
        |> Enum.map(&extract_influence/1)
        |> then(&(Enum.sum(&1) / length(&1)))

      update_cell_with_influence(cell, avg_influence)
    end
  end

  defp extract_influence({_coord, %{sigma_flow: flow}}), do: flow
  defp extract_influence(%{sigma_flow: flow}), do: flow
  defp extract_influence(_), do: 0.5

  defp update_cell_with_influence(cell, influence) when is_map(cell) do
    current_flow = Map.get(cell, :sigma_flow, 0.5)
    new_flow = current_flow * 0.7 + influence * 0.3
    Map.put(cell, :sigma_flow, new_flow)
  end

  defp update_cell_with_influence(cell, _influence), do: cell

  defp compute_cell_metrics(_old_cell, _new_cell, neighbors) do
    if Enum.empty?(neighbors) do
      %{}
    else
      # Compute local divergence
      flows = Enum.map(neighbors, &extract_influence/1)
      mean_flow = Enum.sum(flows) / length(flows)

      variance =
        flows
        |> Enum.map(&((&1 - mean_flow) ** 2))
        |> then(&(Enum.sum(&1) / length(&1)))

      %{
        divergence: Float.round(:math.sqrt(variance), 4)
      }
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Grid-Level Metrics
  # ═══════════════════════════════════════════════════════════════

  defp compute_grid_metrics(old_grid, new_grid) do
    try do
      # Compute metrics using Nx operations
      old_tensor = ensure_tensor(old_grid)
      new_tensor = ensure_tensor(new_grid)

      # Activity ratio (alive cells)
      activity = compute_activity(new_tensor)

      # Change magnitude (L2 distance)
      change_magnitude = compute_change_magnitude(old_tensor, new_tensor)

      # Spatial entropy (simplified)
      spatial_entropy = compute_spatial_entropy(new_tensor)

      # Clustering (connected components proxy)
      clustering = estimate_clustering(new_tensor)

      %{
        activity: Float.round(activity, 4),
        change_magnitude: Float.round(change_magnitude, 4),
        spatial_entropy: Float.round(spatial_entropy, 4),
        clustering: Float.round(clustering, 4)
      }
    rescue
      _ -> %{}
    end
  end

  defp ensure_tensor(grid) when is_struct(grid, Nx.Tensor), do: grid

  defp ensure_tensor(grid) when is_map(grid) do
    # Convert map-based grid to tensor (simplified)
    case grid do
      %{bits: bits} when is_map(bits) ->
        # Thunderbit grid - extract flows
        bits
        |> Map.values()
        |> Enum.map(&Map.get(&1, :sigma_flow, 0.5))
        |> Nx.tensor()

      _ ->
        Nx.tensor([0.0])
    end
  end

  defp ensure_tensor(_), do: Nx.tensor([0.0])

  defp compute_activity(tensor) do
    # Fraction of cells with activity > 0.1 (first channel usually represents "aliveness")
    tensor
    |> Nx.slice_along_axis(0, 1, axis: -1)
    |> Nx.greater(0.1)
    |> Nx.mean()
    |> Nx.to_number()
  rescue
    _ -> 0.5
  end

  defp compute_change_magnitude(old_tensor, new_tensor) do
    old_tensor
    |> Nx.subtract(new_tensor)
    |> Nx.pow(2)
    |> Nx.mean()
    |> Nx.sqrt()
    |> Nx.to_number()
  rescue
    _ -> 0.0
  end

  defp compute_spatial_entropy(tensor) do
    # Simplified: variance as entropy proxy
    mean = Nx.mean(tensor)
    variance = tensor |> Nx.subtract(mean) |> Nx.pow(2) |> Nx.mean() |> Nx.to_number()
    # Normalize to [0, 1] range approximately
    min(1.0, :math.sqrt(variance) * 2)
  rescue
    _ -> 0.5
  end

  defp estimate_clustering(tensor) do
    # Simplified clustering estimate using local variance
    # Lower local variance = higher clustering
    try do
      flat = Nx.flatten(tensor)
      n = Nx.size(flat) |> Nx.to_number()

      if n > 1 do
        mean = Nx.mean(flat) |> Nx.to_number()
        std = flat |> Nx.subtract(mean) |> Nx.pow(2) |> Nx.mean() |> Nx.sqrt() |> Nx.to_number()
        # Invert: low std = high clustering
        1.0 - min(1.0, std)
      else
        0.5
      end
    rescue
      _ -> 0.5
    end
  end
end
