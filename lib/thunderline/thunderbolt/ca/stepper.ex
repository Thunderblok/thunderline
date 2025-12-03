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
  @spec step_thunderbit_grid(thunderbit_grid(), ruleset()) ::
          {:ok, [thunderbit_delta()], thunderbit_grid()}
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
          neighbors =
            get_neighbor_states(coord, bits, bounds, neighborhood_type, boundary_condition)

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
  @spec create_thunderbit_grid(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          thunderbit_grid()
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
      new_phase = :math.fmod(bit.phi_phase + new_flow * 0.1, 2 * :math.pi())

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
      new_phase = :math.fmod(bit.phi_phase + 0.05, 2 * :math.pi())
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

    new_phase = :math.fmod(bit.phi_phase + 0.1, 2 * :math.pi())
    new_lambda = if currently_alive != new_flow > 0.5, do: 0.5, else: bit.lambda_sensitivity * 0.9
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

  # ═══════════════════════════════════════════════════════════════
  # Feature Extraction (HC-Δ-3)
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Extracts feature vectors from a list of deltas.

  Returns a map containing statistical features computed from the CA state:

  - `:mean_energy` - Average sigma_flow across all deltas
  - `:energy_variance` - Variance of sigma_flow values
  - `:activation_count` - Number of bits in active/stable/chaotic states
  - `:total_count` - Total number of deltas
  - `:state_distribution` - Map of state → count
  - `:mean_chaos` - Average lambda_sensitivity
  - `:phase_coherence` - Circular variance of phi_phase (0 = coherent, 1 = random)
  - `:spatial_centroid` - Center of mass of active bits (if coords present)

  ## Examples

      iex> deltas = [%{sigma_flow: 0.8, state: :active}, %{sigma_flow: 0.3, state: :dormant}]
      iex> features = Stepper.extract_features(deltas)
      iex> features.mean_energy
      0.55
  """
  @spec extract_features([delta()]) :: map()
  def extract_features([]), do: empty_features()

  def extract_features(deltas) when is_list(deltas) do
    count = length(deltas)

    # Extract numeric values, handling both Thunderbit and legacy deltas
    energies = extract_energies(deltas)
    flows = extract_flows(deltas)
    lambdas = extract_lambdas(deltas)
    phases = extract_phases(deltas)
    states = Enum.map(deltas, &extract_state/1)

    # Compute statistics - use ENERGIES for mean_energy, FLOWS for flow stats
    mean_energy = safe_mean(energies)
    energy_variance = safe_variance(energies, mean_energy)
    mean_chaos = safe_mean(lambdas)
    mean_flow = safe_mean(flows)
    phase_coherence = compute_phase_coherence(phases)
    state_distribution = compute_state_distribution(states)
    activation_count = count_activations(states)
    spatial_centroid = compute_spatial_centroid(deltas, energies)

    %{
      mean_energy: mean_energy,
      energy_variance: energy_variance,
      mean_flow: mean_flow,
      activation_count: activation_count,
      total_count: count,
      state_distribution: state_distribution,
      mean_chaos: mean_chaos,
      phase_coherence: phase_coherence,
      spatial_centroid: spatial_centroid,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Extracts features from a grid directly (convenience wrapper).

  Computes one step and returns both deltas and their features.
  """
  @spec step_with_features(grid(), ruleset()) :: {:ok, [delta()], grid(), map()}
  def step_with_features(grid, ruleset) do
    {:ok, deltas, new_grid} = next(grid, ruleset)
    features = extract_features(deltas)
    {:ok, deltas, new_grid, features}
  end

  # ───────────────────────────────────────────────────────────────
  # Feature extraction helpers
  # ───────────────────────────────────────────────────────────────

  defp empty_features do
    %{
      mean_energy: 0.0,
      energy_variance: 0.0,
      mean_flow: 0.0,
      activation_count: 0,
      total_count: 0,
      state_distribution: %{},
      mean_chaos: 0.0,
      phase_coherence: 1.0,
      spatial_centroid: nil,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  # Extract energy values from deltas (primary energy metric)
  # Thunderbit deltas (with :id field) return raw 0-100 scale
  # Legacy deltas (no :id field) normalize integers from 0-100 to 0.0-1.0
  defp extract_energies(deltas) do
    Enum.map(deltas, fn delta ->
      cond do
        is_map_key(delta, :energy) and is_map_key(delta, :id) ->
          # Thunderbit delta - use raw value as float
          delta.energy * 1.0

        is_map_key(delta, :energy) ->
          # Legacy delta - normalize if integer
          normalize_energy(delta.energy)

        true ->
          0.0
      end
    end)
  end

  # Normalize legacy integer energies (0-100 scale to 0.0-1.0)
  defp normalize_energy(value) when is_integer(value) and value > 1 do
    value / 100.0
  end

  defp normalize_energy(value), do: value * 1.0

  # Extract sigma_flow / flow from both delta formats
  # Thunderbit deltas use :flow, legacy uses :sigma_flow
  defp extract_flows(deltas) do
    Enum.map(deltas, fn delta ->
      cond do
        is_map_key(delta, :flow) -> delta.flow
        is_map_key(delta, :sigma_flow) -> delta.sigma_flow
        true -> 0.0
      end
    end)
  end

  # Extract lambda (Thunderbit) or lambda_sensitivity, default 0 for legacy
  defp extract_lambdas(deltas) do
    Enum.map(deltas, fn delta ->
      cond do
        is_map_key(delta, :lambda) -> delta.lambda
        is_map_key(delta, :lambda_sensitivity) -> delta.lambda_sensitivity
        true -> 0.0
      end
    end)
  end

  # Extract phase (Thunderbit) or phi_phase, default 0 for legacy
  defp extract_phases(deltas) do
    Enum.map(deltas, fn delta ->
      cond do
        is_map_key(delta, :phase) -> delta.phase
        is_map_key(delta, :phi_phase) -> delta.phi_phase
        true -> 0.0
      end
    end)
  end

  # Extract state atom from delta
  defp extract_state(delta) do
    Map.get(delta, :state, :unknown)
  end

  # Safe mean that handles empty lists
  defp safe_mean([]), do: 0.0

  defp safe_mean(values) do
    Enum.sum(values) / length(values)
  end

  # Safe variance calculation
  defp safe_variance([], _mean), do: 0.0
  defp safe_variance([_single], _mean), do: 0.0

  defp safe_variance(values, mean) do
    sum_sq = Enum.reduce(values, 0.0, fn v, acc -> acc + (v - mean) ** 2 end)
    sum_sq / length(values)
  end

  # Phase coherence using circular statistics (Rayleigh test)
  # Returns 0 for perfectly coherent phases, 1 for random phases
  defp compute_phase_coherence([]), do: 1.0

  defp compute_phase_coherence(phases) do
    n = length(phases)

    sum_cos = Enum.reduce(phases, 0.0, fn p, acc -> acc + :math.cos(p) end)
    sum_sin = Enum.reduce(phases, 0.0, fn p, acc -> acc + :math.sin(p) end)

    r = :math.sqrt(sum_cos ** 2 + sum_sin ** 2) / n
    # Invert so 0 = coherent, 1 = random
    Float.round(1.0 - r, 4)
  end

  # Count states in a map
  defp compute_state_distribution(states) do
    Enum.frequencies(states)
  end

  # Count bits that are "active" - alive, active, stable, chaotic, critical, evolving
  defp count_activations(states) do
    active_states = [:alive, :active, :stable, :chaotic, :critical, :evolving]
    Enum.count(states, &(&1 in active_states))
  end

  # Compute center of mass for deltas that have coordinates
  # Uses provided energies list for weights (parallel to deltas)
  # Thunderbit deltas have :x, :y, :z fields or :coord tuple
  defp compute_spatial_centroid(deltas, energies) do
    coords_with_weight =
      deltas
      |> Enum.zip(energies)
      |> Enum.filter(fn {delta, _energy} ->
        is_map_key(delta, :coord) or (is_map_key(delta, :x) and is_map_key(delta, :y))
      end)
      |> Enum.map(fn {delta, energy} ->
        coord =
          cond do
            is_map_key(delta, :coord) -> delta.coord
            is_map_key(delta, :z) -> {delta.x, delta.y, delta.z}
            true -> {delta.x, delta.y, 0}
          end

        # Use energy as weight, default to 0.5 if energy is 0 or nil
        weight = if energy > 0, do: energy, else: 0.5

        {coord, weight}
      end)

    case coords_with_weight do
      [] ->
        nil

      list ->
        total_weight = list |> Enum.map(&elem(&1, 1)) |> Enum.sum()

        if total_weight == 0 do
          nil
        else
          {sum_x, sum_y, sum_z} =
            Enum.reduce(list, {0.0, 0.0, 0.0}, fn {{x, y, z}, w}, {ax, ay, az} ->
              {ax + x * w, ay + y * w, az + z * w}
            end)

          {
            Float.round(sum_x / total_weight, 4),
            Float.round(sum_y / total_weight, 4),
            Float.round(sum_z / total_weight, 4)
          }
        end
    end
  end
end
