defmodule Thunderline.Thunderprism.Domain do
  @moduledoc """
  ThunderPrism Domain - DEPRECATED, consolidated into Thundergrid.Prism

  This module is kept for backward compatibility.
  All Prism functionality has been moved to `Thunderline.Thundergrid.Prism`.

  ## Migration Guide

  Old:
      alias Thunderline.Thunderprism.{Domain, PrismNode, PrismEdge, MLTap}
      Domain.create_prism_node!(...)

  New:
      alias Thunderline.Thundergrid.Prism
      alias Thunderline.Thundergrid.Prism.{PrismNode, PrismEdge, MLTap}
      Prism.log_decision(...)

  Resources are now part of Thundergrid.Domain and exposed via GraphQL.
  """

  # Delegate to new Prism module
  defdelegate log_decision(attrs), to: Thunderline.Thundergrid.Prism
  defdelegate log_edge(attrs), to: Thunderline.Thundergrid.Prism
  defdelegate log_with_edge(attrs, prev_node_id \\ nil), to: Thunderline.Thundergrid.Prism

  # Legacy code interface shims (deprecated)
  def create_prism_node!(pac_id, iteration, chosen_model, probs, distances, meta, timestamp) do
    attrs = %{
      pac_id: pac_id,
      iteration: iteration,
      chosen_model: to_string(chosen_model),
      model_probabilities: probs || %{},
      model_distances: distances || %{},
      meta: meta || %{},
      timestamp: timestamp
    }

    task = Thunderline.Thundergrid.Prism.log_decision(attrs)
    case Task.await(task, 5000) do
      {:ok, node} -> node
      {:error, reason} -> raise "PrismNode creation failed: #{inspect(reason)}"
    end
  end

  def create_prism_edge!(from_id, to_id, relation_type, meta) do
    attrs = %{
      from_id: from_id,
      to_id: to_id,
      relation_type: relation_type || "sequential",
      meta: meta || %{}
    }

    task = Thunderline.Thundergrid.Prism.log_edge(attrs)
    case Task.await(task, 5000) do
      {:ok, edge} -> edge
      {:error, reason} -> raise "PrismEdge creation failed: #{inspect(reason)}"
    end
  end
end
