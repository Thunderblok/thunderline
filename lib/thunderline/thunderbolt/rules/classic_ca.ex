defmodule Thunderline.Thunderbolt.Rules.ClassicCA do
  @moduledoc """
  Classic Cellular Automata rule backend.

  Implements outer-totalistic rules in B/S notation (e.g., B3/S23 for Game of Life).

  ## Features

  - Standard B/S rules for 2D/3D grids
  - Moore and von Neumann neighborhoods
  - Side-quest metric emission (clustering, local entropy)

  ## Configuration

      params = ClassicCA.init_params(
        born: [3],
        survive: [2, 3],
        neighborhood: :moore
      )

  ## Reference

  - Wolfram, S. "A New Kind of Science" (2002)
  - HC Orders: Operation TIGER LATTICE
  """

  @behaviour Thunderline.Thunderbolt.Rule

  alias Thunderline.Thunderbolt.Thunderbit

  # ═══════════════════════════════════════════════════════════════
  # Behaviour Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def backend_type, do: :classic_ca

  @impl true
  def init_params(opts \\ []) do
    %{
      born: Keyword.get(opts, :born, [3]),
      survive: Keyword.get(opts, :survive, [2, 3]),
      neighborhood: Keyword.get(opts, :neighborhood, :moore),
      wrap: Keyword.get(opts, :wrap, false),
      version: 1
    }
  end

  @impl true
  def update(cell, neighbors, params) do
    born = Map.get(params, :born, [3])
    survive = Map.get(params, :survive, [2, 3])

    # Count alive neighbors
    alive_count = count_alive(neighbors)

    # Current state
    currently_alive = is_alive?(cell)

    # Apply B/S rule
    new_alive =
      cond do
        not currently_alive and alive_count in born -> true
        currently_alive and alive_count in survive -> true
        true -> false
      end

    # Compute new cell state
    new_cell = update_cell_state(cell, new_alive)

    # Compute side-quest metrics
    metrics = compute_local_metrics(cell, neighbors, new_alive, alive_count)

    {:ok, new_cell, metrics}
  end

  # ═══════════════════════════════════════════════════════════════
  # State Helpers
  # ═══════════════════════════════════════════════════════════════

  defp count_alive(neighbors) do
    Enum.count(neighbors, &neighbor_alive?/1)
  end

  defp neighbor_alive?({_coord, %Thunderbit{} = bit}) do
    bit.sigma_flow > 0.5 or bit.state in [:active, :stable, :alive]
  end

  defp neighbor_alive?(%Thunderbit{} = bit) do
    bit.sigma_flow > 0.5 or bit.state in [:active, :stable, :alive]
  end

  defp neighbor_alive?(%{state: state}) when state in [:active, :stable, :alive], do: true
  defp neighbor_alive?(%{sigma_flow: flow}) when flow > 0.5, do: true
  defp neighbor_alive?(%{alive: true}), do: true
  defp neighbor_alive?(1), do: true
  defp neighbor_alive?(true), do: true
  defp neighbor_alive?(_), do: false

  defp is_alive?(%Thunderbit{} = bit) do
    bit.sigma_flow > 0.5 or bit.state in [:active, :stable, :alive]
  end

  defp is_alive?(%{state: state}) when state in [:active, :stable, :alive], do: true
  defp is_alive?(%{sigma_flow: flow}) when flow > 0.5, do: true
  defp is_alive?(%{alive: true}), do: true
  defp is_alive?(1), do: true
  defp is_alive?(true), do: true
  defp is_alive?(_), do: false

  defp update_cell_state(%Thunderbit{} = bit, alive) do
    new_flow = if alive, do: min(1.0, bit.sigma_flow + 0.3), else: max(0.0, bit.sigma_flow - 0.3)
    new_state = if alive, do: :active, else: :inactive

    %{bit | sigma_flow: new_flow, state: new_state}
  end

  defp update_cell_state(cell, alive) when is_map(cell) do
    Map.merge(cell, %{alive: alive, state: if(alive, do: :active, else: :inactive)})
  end

  defp update_cell_state(_cell, alive), do: %{alive: alive}

  # ═══════════════════════════════════════════════════════════════
  # Side-Quest Metrics
  # ═══════════════════════════════════════════════════════════════

  defp compute_local_metrics(_cell, neighbors, new_alive, alive_count) do
    neighbor_count = length(neighbors)

    if neighbor_count == 0 do
      %{}
    else
      # Local clustering: how connected are the alive neighbors to each other?
      # Simplified: ratio of alive neighbors (proxy for clustering)
      clustering = alive_count / max(1, neighbor_count)

      # Local entropy: how mixed is the neighborhood?
      # Maximum entropy at 50% alive
      p_alive = alive_count / max(1, neighbor_count)
      p_dead = 1.0 - p_alive

      local_entropy =
        if p_alive > 0 and p_dead > 0 do
          -(p_alive * :math.log2(p_alive) + p_dead * :math.log2(p_dead))
        else
          0.0
        end

      # State change detection (for healing rate approximation)
      _state_changed = new_alive != (alive_count > 0)

      %{
        clustering: Float.round(clustering, 4),
        entropy: Float.round(local_entropy, 4)
      }
    end
  end
end
