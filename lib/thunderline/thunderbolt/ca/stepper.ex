defmodule Thunderline.Thunderbolt.CA.Stepper do
  @moduledoc """
  Pure stepping logic for CA grid.

  Provides both legacy 2D grid stepping (for backward compatibility) and
  new 3D Thunderbit-based stepping for the lattice architecture.

  ## Legacy Mode

  Grid representation: `%{size: n}` where size is the square grid dimension.
  Ruleset: map or atom describing rule parameters.
  Returns `{:ok, deltas, new_grid}` with 2D cell deltas.

  ## Thunderbit Mode

  Grid representation: `%{bounds: {x, y, z}, bits: %{coord => Thunderbit}}`.
  Ruleset: map with `:rule_id`, `:neighborhood_type`, `:boundary_condition`.
  Returns `{:ok, deltas, new_grid}` with Thunderbit deltas.

  Later we can swap in accelerated implementations (EAGL, NIF, GPU)
  by redefining the step functions.

  ## Reference

  See `docs/HC_ARCHITECTURE_SYNTHESIS.md` for the 3D CA lattice specification.
  """

  alias Thunderline.Thunderbolt.Thunderbit
  alias Thunderline.Thunderbolt.CA.Neighborhood

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  # Legacy 2D grid
  @type legacy_grid :: %{size: pos_integer()}

  # 3D Thunderbit grid
  @type thunderbit_grid :: %{
          bounds: {pos_integer(), pos_integer(), pos_integer()},
          bits: %{Thunderbit.coord() => Thunderbit.t()},
          tick: non_neg_integer()
        }

  @type grid :: legacy_grid() | thunderbit_grid()
  @type ruleset :: map() | atom()

  # Legacy delta format
  @type legacy_delta :: %{
          id: String.t(),
          state: atom(),
          hex: integer(),
          energy: non_neg_integer()
        }

  # Thunderbit delta format
  @type thunderbit_delta :: map()

  @type delta :: legacy_delta() | thunderbit_delta()

  # ═══════════════════════════════════════════════════════════════
  # Main Entry Point
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute next step deltas returning `{:ok, deltas, new_grid}`.

  Dispatches to legacy or Thunderbit mode based on grid structure.
  """
  @spec next(grid(), ruleset()) :: {:ok, [delta()], grid()}
  def next(%{bits: _} = grid, ruleset) do
    step_thunderbit_grid(grid, ruleset)
  end

  def next(%{size: _} = grid, ruleset) do
    step_legacy_grid(grid, ruleset)
  end

  # ═══════════════════════════════════════════════════════════════
  # Thunderbit Grid Stepping
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Steps a Thunderbit grid forward by one tick.

  The ruleset should contain:
  - `:rule_id` - The CA rule to apply (default: `:demo`)
  - `:neighborhood_type` - Type of neighborhood (default: `:von_neumann`)
  - `:boundary_condition` - How to handle edges (default: `:clip`)
  """
  @spec step_thunderbit_grid(thunderbit_grid(), ruleset()) :: {:ok, [thunderbit_delta()], thunderbit_grid()}
  def step_thunderbit_grid(%{bounds: bounds, bits: bits, tick: tick} = grid, ruleset) do
    rule_id = get_rule(ruleset)
    neighborhood_type = Map.get(ruleset, :neighborhood_type, :von_neumann)
    boundary_condition = Map.get(ruleset, :boundary_condition, :clip)
    new_tick = tick + 1

    # Compute new states for all bits in parallel
    {updated_bits, deltas} =
      bits
      |> Task.async_stream(
        fn {coord, bit} ->
          neighbors = get_neighbor_states(coord, bits, bounds, neighborhood_type, boundary_condition)
          new_bit = apply_rule(bit, neighbors, rule_id, new_tick)
          {coord, new_bit}
        end,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce({%{}, []}, fn {:ok, {coord, new_bit}}, {bits_acc, deltas_acc} ->
        delta = Thunderbit.to_delta(new_bit)
        {Map.put(bits_acc, coord, new_bit), [delta | deltas_acc]}
      end)

    new_grid = %{grid | bits: updated_bits, tick: new_tick}
    {:ok, deltas, new_grid}
  end

  @doc """
  Creates a new Thunderbit grid of the given dimensions.

  ## Options

  - `:rule_id` - Initial CA rule (default: `:demo`)
  - `:neighborhood_type` - Neighborhood type (default: `:von_neumann`)
  - `:sparse` - If true, only create bits at specified coords (default: false)
  - `:coords` - List of coords to populate when sparse (default: [])
  """
  @spec create_thunderbit_grid(pos_integer(), pos_integer(), pos_integer(), keyword()) :: thunderbit_grid()
  def create_thunderbit_grid(x, y, z, opts \\ []) do
    bounds = {x, y, z}
    rule_id = Keyword.get(opts, :rule_id, :demo)
    sparse = Keyword.get(opts, :sparse, false)
    coords = Keyword.get(opts, :coords, [])

    bits =
      if sparse do
        coords
        |> Enum.map(fn coord -> {coord, Thunderbit.new(coord, rule_id: rule_id)} end)
        |> Map.new()
      else
        for xi <- 0..(x - 1),
            yi <- 0..(y - 1),
            zi <- 0..(z - 1),
            into: %{} do
          coord = {xi, yi, zi}
          {coord, Thunderbit.new(coord, rule_id: rule_id)}
        end
      end

    %{bounds: bounds, bits: bits, tick: 0}
  end

  # Get neighbor bit states for a coordinate
  defp get_neighbor_states(coord, bits, bounds, neighborhood_type, boundary_condition) do
    coord
    |> Neighborhood.compute(bounds, neighborhood_type, boundary_condition)
    |> Enum.map(fn neighbor_coord ->
      case Map.get(bits, neighbor_coord) do
        nil -> nil
        bit -> {neighbor_coord, bit}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Apply CA rule to compute new bit state
  defp apply_rule(bit, neighbors, rule_id, tick) do
    # Compute new dynamics based on neighborhood
    {new_state, new_flow, new_phase, new_lambda} =
      compute_dynamics(bit, neighbors, rule_id)

    Thunderbit.update_state(bit,
      state: new_state,
      sigma_flow: new_flow,
      phi_phase: new_phase,
      lambda_sensitivity: new_lambda,
      tick: tick
    )
  end

  # Compute new dynamics metrics from neighborhood
  defp compute_dynamics(bit, neighbors, rule_id) do
    case rule_id do
      :demo -> demo_dynamics(bit, neighbors)
      :diffusion -> diffusion_dynamics(bit, neighbors)
      :game_of_life_3d -> life_3d_dynamics(bit, neighbors)
      _ -> demo_dynamics(bit, neighbors)
    end
  end

  # Demo rule: simple diffusion-like behavior
  defp demo_dynamics(bit, neighbors) do
    neighbor_count = length(neighbors)

    if neighbor_count == 0 do
      # Isolated bit - slow decay
      {bit.state, bit.sigma_flow * 0.99, bit.phi_phase, bit.lambda_sensitivity}
    else
      # Average neighbor flow influences our flow
      avg_neighbor_flow =
        neighbors
        |> Enum.map(fn {_coord, n} -> n.sigma_flow end)
        |> Enum.sum()
        |> Kernel./(neighbor_count)

      # Flow converges toward neighborhood average with some noise
      noise = :rand.uniform() * 0.1 - 0.05
      new_flow = bit.sigma_flow * 0.7 + avg_neighbor_flow * 0.3 + noise
      new_flow = max(0.0, min(1.0, new_flow))

      # Phase advances based on flow
      new_phase = Float.mod(bit.phi_phase + new_flow * 0.1, 2 * :math.pi())

      # Lambda (chaos) increases with flow variance
      flow_variance =
        neighbors
        |> Enum.map(fn {_coord, n} -> (n.sigma_flow - avg_neighbor_flow) ** 2 end)
        |> Enum.sum()
        |> Kernel./(neighbor_count)

      new_lambda = bit.lambda_sensitivity * 0.9 + flow_variance * 0.5
      new_lambda = max(0.0, min(1.0, new_lambda))

      # State is derived from dynamics
      new_state = derive_state(new_flow, new_lambda)

      {new_state, new_flow, new_phase, new_lambda}
    end
  end

  # Diffusion rule: spread presence/trust through grid
  defp diffusion_dynamics(bit, neighbors) do
    neighbor_count = length(neighbors)

    if neighbor_count == 0 do
      {bit.state, bit.sigma_flow * 0.95, bit.phi_phase, bit.lambda_sensitivity}
    else
      # Pure diffusion - average all neighbor values
      avg_flow =
        neighbors
        |> Enum.map(fn {_coord, n} -> n.sigma_flow end)
        |> Enum.sum()
        |> Kernel./(neighbor_count)

      # Weighted update toward average
      new_flow = bit.sigma_flow * 0.5 + avg_flow * 0.5
      new_phase = Float.mod(bit.phi_phase + 0.05, 2 * :math.pi())
      new_lambda = bit.lambda_sensitivity * 0.95
      new_state = derive_state(new_flow, new_lambda)

      {new_state, new_flow, new_phase, new_lambda}
    end
  end

  # 3D Game of Life variant
  defp life_3d_dynamics(bit, neighbors) do
    # Count "alive" neighbors (flow > 0.5)
    alive_count =
      neighbors
      |> Enum.count(fn {_coord, n} -> n.sigma_flow > 0.5 end)

    currently_alive = bit.sigma_flow > 0.5

    # 3D Life rules (adjusted for 6-connected neighborhoods)
    # Alive: survives with 2-4 alive neighbors
    # Dead: becomes alive with exactly 3 alive neighbors
    new_flow =
      cond do
        currently_alive and alive_count in 2..4 -> min(1.0, bit.sigma_flow + 0.1)
        not currently_alive and alive_count == 3 -> 0.6
        currently_alive -> max(0.0, bit.sigma_flow - 0.3)
        true -> max(0.0, bit.sigma_flow - 0.1)
      end

    new_phase = Float.mod(bit.phi_phase + 0.1, 2 * :math.pi())
    new_lambda = if currently_alive != (new_flow > 0.5), do: 0.5, else: bit.lambda_sensitivity * 0.9
    new_state = derive_state(new_flow, new_lambda)

    {new_state, new_flow, new_phase, new_lambda}
  end

  defp derive_state(_flow, lambda) when lambda > 0.8, do: :chaotic
  defp derive_state(flow, _lambda) when flow > 0.8, do: :active
  defp derive_state(flow, _lambda) when flow > 0.5, do: :stable
  defp derive_state(flow, _lambda) when flow > 0.2, do: :dormant
  defp derive_state(_flow, _lambda), do: :inactive

  defp get_rule(ruleset) when is_atom(ruleset), do: ruleset
  defp get_rule(ruleset) when is_map(ruleset), do: Map.get(ruleset, :rule_id, :demo)
  defp get_rule(%{rule: rule}), do: rule

  # ═══════════════════════════════════════════════════════════════
  # Legacy Grid Stepping (Backward Compatibility)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Steps a legacy 2D grid forward by one tick.

  Maintains backward compatibility with existing CA visualization.
  """
  @spec step_legacy_grid(legacy_grid(), ruleset()) :: {:ok, [legacy_delta()], legacy_grid()}
  def step_legacy_grid(%{size: size} = grid, _ruleset) do
    # Produce a small random sample of changed cells to keep payload tight.
    changes = Enum.random(5..18)

    deltas =
      for _ <- 1..changes do
        row = :rand.uniform(size) - 1
        col = :rand.uniform(size) - 1
        id = "#{row}-#{col}"
        energy = :rand.uniform(100) - 1
        state = pick_state(energy)
        %{id: id, state: state, energy: energy, hex: state_color(state)}
      end

    {:ok, deltas, grid}
  end

  defp pick_state(e) when e > 85, do: :critical
  defp pick_state(e) when e > 60, do: :active
  defp pick_state(e) when e > 30, do: :evolving
  defp pick_state(_), do: :inactive

  defp state_color(:critical), do: 0xFF0000
  defp state_color(:active), do: 0x00FF00
  defp state_color(:evolving), do: 0xFFFF00
  defp state_color(:inactive), do: 0x333333
end
