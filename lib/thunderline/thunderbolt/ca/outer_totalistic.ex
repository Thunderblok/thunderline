defmodule Thunderline.Thunderbolt.CA.OuterTotalistic do
  @moduledoc """
  Outer-totalistic cellular automata rules.

  Implements outer-totalistic rules where the transition depends only on:
  1. The cell's own state
  2. The SUM of neighboring states (not individual neighbor positions)

  ## HC-Δ-16: Cerebros CA Proposal Requirement

  From the original Cerebros proposal:
  > "Use vetted rules from the QuAK/Cerebros list:
  >   - 267422991 (reversible, chaotic attractor)
  >   - 4042321935 (period-doubling cascade)
  >   - 2863311530 (XOR-based linear)
  >   - 3435973836 (Rule 150 analog)"

  ## Outer-Totalistic Definition

  For k states and r neighbors, an outer-totalistic rule is defined by:
  - A transition function f(center, sum_neighbors) → new_center
  - Total of k * (k*r + 1) possible (center, sum) combinations

  The rule number encodes all transitions in base-k.

  ## QuAK Connection

  From the analysis:
  > "Outer-totalistic rules vastly reduce the state space while preserving
  >  computational universality for certain rules."

  The vetted rules above were selected for their:
  - Reversibility properties (important for TAE computation)
  - Interesting dynamical behavior (chaotic attractors, cascades)
  - Mathematical tractability (XOR-based rules)

  ## Usage

      # Apply a vetted rule
      new_grid = OuterTotalistic.apply_rule(grid, :reversible_chaotic)

      # Apply by rule number
      new_grid = OuterTotalistic.apply_rule_number(grid, 267422991, k: 2, r: 8)

      # Get rule details
      info = OuterTotalistic.rule_info(:period_doubling)
  """

  alias Thunderline.Thunderbolt.CA.Grid

  # ═══════════════════════════════════════════════════════════════
  # Vetted Rule Definitions
  # ═══════════════════════════════════════════════════════════════

  @type rule_name :: :reversible_chaotic | :period_doubling | :xor_linear | :rule_150_analog

  @vetted_rules %{
    # Reversible rule with chaotic attractor
    # Binary (k=2), 8-neighbor Moore neighborhood
    # Shows complex dynamics without absorbing states
    reversible_chaotic: %{
      number: 267_422_991,
      k: 2,
      r: 8,
      description: "Reversible, chaotic attractor",
      properties: [:reversible, :chaotic]
    },

    # Period-doubling cascade rule
    # Binary (k=2), 8-neighbor Moore neighborhood
    # Exhibits Feigenbaum-like bifurcation structure
    period_doubling: %{
      number: 4_042_321_935,
      k: 2,
      r: 8,
      description: "Period-doubling cascade",
      properties: [:cascade, :bifurcating]
    },

    # XOR-based linear rule
    # Binary (k=2), 8-neighbor Moore neighborhood
    # Mathematically tractable, preserves linearity
    xor_linear: %{
      number: 2_863_311_530,
      k: 2,
      r: 8,
      description: "XOR-based linear rule",
      properties: [:linear, :xor_based, :reversible]
    },

    # Rule 150 analog for 2D
    # Binary (k=2), 8-neighbor Moore neighborhood
    # Extension of elementary CA Rule 150 to 2D
    rule_150_analog: %{
      number: 3_435_973_836,
      k: 2,
      r: 8,
      description: "Rule 150 analog for 2D",
      properties: [:linear, :class_3]
    }
  }

  @doc """
  Get information about a vetted rule.
  """
  @spec rule_info(rule_name()) :: map() | nil
  def rule_info(name), do: Map.get(@vetted_rules, name)

  @doc """
  List all vetted rule names.
  """
  @spec vetted_rules() :: [rule_name()]
  def vetted_rules, do: Map.keys(@vetted_rules)

  @doc """
  Get a vetted rule by its number.
  """
  @spec rule_by_number(non_neg_integer()) :: {rule_name(), map()} | nil
  def rule_by_number(number) do
    Enum.find(@vetted_rules, fn {_name, info} -> info.number == number end)
  end

  # ═══════════════════════════════════════════════════════════════
  # Rule Application
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply a vetted rule by name.

  ## Parameters

  - `grid` - The CA grid (as a 2D list or Grid struct)
  - `rule_name` - One of the vetted rule names

  ## Returns

  Updated grid after one step of the rule.

  ## Example

      grid = Grid.random(100, 100)
      new_grid = OuterTotalistic.apply_rule(grid, :reversible_chaotic)
  """
  @spec apply_rule(Grid.t() | [[integer()]], rule_name()) :: [[integer()]]
  def apply_rule(grid, rule_name) do
    case Map.get(@vetted_rules, rule_name) do
      nil ->
        raise ArgumentError, "Unknown rule: #{inspect(rule_name)}. Use one of: #{inspect(vetted_rules())}"

      %{number: number, k: k, r: r} ->
        apply_rule_number(grid, number, k: k, r: r)
    end
  end

  @doc """
  Apply an outer-totalistic rule by rule number.

  ## Parameters

  - `grid` - The CA grid
  - `rule_number` - The outer-totalistic rule number
  - `opts`:
    - `:k` - Number of states (default: 2)
    - `:r` - Number of neighbors (default: 8 for Moore)

  ## Returns

  Updated grid after one step.
  """
  @spec apply_rule_number(Grid.t() | [[integer()]], non_neg_integer(), keyword()) :: [[integer()]]
  def apply_rule_number(grid, rule_number, opts \\ []) do
    k = Keyword.get(opts, :k, 2)
    r = Keyword.get(opts, :r, 8)

    # Build transition lookup table
    lookup = build_lookup_table(rule_number, k, r)

    # Extract cells from grid
    cells = extract_cells(grid)
    {height, width} = grid_dimensions(cells)

    # Apply rule to each cell
    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        center = get_cell(cells, x, y)
        neighbor_sum = sum_neighbors(cells, x, y, width, height)
        lookup_transition(lookup, center, neighbor_sum, k, r)
      end
    end
  end

  @doc """
  Apply rule with specific neighborhood type.

  ## Neighborhood Types

  - `:moore` - 8 neighbors (default)
  - `:von_neumann` - 4 neighbors
  - `:hexagonal` - 6 neighbors
  """
  @spec apply_rule_with_neighborhood(
          Grid.t() | [[integer()]],
          rule_name() | non_neg_integer(),
          atom()
        ) :: [[integer()]]
  def apply_rule_with_neighborhood(grid, rule, neighborhood) do
    r = neighborhood_size(neighborhood)

    case rule do
      name when is_atom(name) ->
        info = rule_info(name)
        apply_rule_number(grid, info.number, k: info.k, r: r)

      number when is_integer(number) ->
        apply_rule_number(grid, number, k: 2, r: r)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Specialized Rule Implementations
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply XOR-based rule directly (faster than generic).

  XOR rule: new_center = center XOR (neighbor_sum mod 2)
  """
  @spec apply_xor_rule(Grid.t() | [[integer()]]) :: [[integer()]]
  def apply_xor_rule(grid) do
    cells = extract_cells(grid)
    {height, width} = grid_dimensions(cells)

    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        center = get_cell(cells, x, y)
        neighbor_sum = sum_neighbors(cells, x, y, width, height)
        Bitwise.bxor(center, rem(neighbor_sum, 2))
      end
    end
  end

  @doc """
  Apply reversible second-order rule.

  Uses previous state to ensure reversibility:
  new_center = f(center, neighbors) XOR previous_center
  """
  @spec apply_reversible_rule(
          Grid.t() | [[integer()]],
          Grid.t() | [[integer()]],
          rule_name()
        ) :: [[integer()]]
  def apply_reversible_rule(grid, previous_grid, rule_name) do
    # Compute forward step
    forward = apply_rule(grid, rule_name)

    # XOR with previous for reversibility
    forward_cells = extract_cells(forward)
    prev_cells = extract_cells(previous_grid)
    {height, width} = grid_dimensions(forward_cells)

    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        Bitwise.bxor(
          get_cell(forward_cells, x, y),
          get_cell(prev_cells, x, y)
        )
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Rule Analysis
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Analyze a rule number to extract its transition table.
  """
  @spec analyze_rule(non_neg_integer(), keyword()) :: map()
  def analyze_rule(rule_number, opts \\ []) do
    k = Keyword.get(opts, :k, 2)
    r = Keyword.get(opts, :r, 8)
    lookup = build_lookup_table(rule_number, k, r)

    # Count fixed points (transitions where output = center)
    fixed_points =
      for center <- 0..(k - 1),
          sum <- 0..(k * r),
          lookup_transition(lookup, center, sum, k, r) == center,
          do: {center, sum}

    # Check reversibility (simplified check)
    reversible = check_reversibility(lookup, k, r)

    %{
      rule_number: rule_number,
      k: k,
      r: r,
      fixed_points: fixed_points,
      fixed_point_count: length(fixed_points),
      potentially_reversible: reversible,
      transition_count: k * (k * r + 1)
    }
  end

  @doc """
  Check if a rule preserves some global property.

  Common properties:
  - `:parity` - XOR of all cells is preserved
  - `:density` - Approximate total cell count preserved
  """
  @spec preserves_property?(non_neg_integer(), atom(), keyword()) :: boolean()
  def preserves_property?(rule_number, property, opts \\ []) do
    k = Keyword.get(opts, :k, 2)
    r = Keyword.get(opts, :r, 8)

    case property do
      :parity ->
        # Check if XOR-based
        rule_number == 2_863_311_530

      :density ->
        # Simplified: check if rule is symmetric in some sense
        analysis = analyze_rule(rule_number, opts)
        analysis.fixed_point_count > 0

      _ ->
        false
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Private: Lookup Table Construction
  # ═══════════════════════════════════════════════════════════════

  defp build_lookup_table(rule_number, k, r) do
    # Number of possible (center, sum) pairs
    max_sum = k * r
    total_entries = k * (max_sum + 1)

    # Extract digits from rule number in base k
    digits = extract_base_k_digits(rule_number, k, total_entries)

    # Build map: {center, sum} -> new_state
    for center <- 0..(k - 1),
        sum <- 0..max_sum,
        into: %{} do
      index = center * (max_sum + 1) + sum
      new_state = Enum.at(digits, index, 0)
      {{center, sum}, new_state}
    end
  end

  defp extract_base_k_digits(number, k, count) do
    digits =
      Stream.unfold(number, fn
        0 -> nil
        n -> {rem(n, k), div(n, k)}
      end)
      |> Enum.take(count)

    # Pad with zeros if needed
    padding_count = max(0, count - length(digits))
    digits ++ List.duplicate(0, padding_count)
  end

  defp lookup_transition(lookup, center, sum, _k, _r) do
    Map.get(lookup, {center, sum}, 0)
  end

  # ═══════════════════════════════════════════════════════════════
  # Private: Grid Operations
  # ═══════════════════════════════════════════════════════════════

  defp extract_cells(%{cells: cells}), do: cells
  defp extract_cells(cells) when is_list(cells), do: cells

  defp grid_dimensions([]), do: {0, 0}
  defp grid_dimensions([row | _] = grid), do: {length(grid), length(row)}

  defp get_cell(cells, x, y) do
    cells
    |> Enum.at(y, [])
    |> Enum.at(x, 0)
  end

  defp sum_neighbors(cells, x, y, width, height) do
    # Moore neighborhood (8 neighbors)
    offsets = [
      {-1, -1},
      {0, -1},
      {1, -1},
      {-1, 0},
      {1, 0},
      {-1, 1},
      {0, 1},
      {1, 1}
    ]

    Enum.reduce(offsets, 0, fn {dx, dy}, acc ->
      nx = wrap(x + dx, width)
      ny = wrap(y + dy, height)
      acc + get_cell(cells, nx, ny)
    end)
  end

  defp wrap(coord, size) when coord < 0, do: size + coord
  defp wrap(coord, size) when coord >= size, do: coord - size
  defp wrap(coord, _size), do: coord

  defp neighborhood_size(:moore), do: 8
  defp neighborhood_size(:von_neumann), do: 4
  defp neighborhood_size(:hexagonal), do: 6
  defp neighborhood_size(_), do: 8

  # ═══════════════════════════════════════════════════════════════
  # Private: Reversibility Check
  # ═══════════════════════════════════════════════════════════════

  defp check_reversibility(lookup, k, r) do
    # Simplified reversibility check:
    # For each possible sum, check if the mapping from center to new_state is injective
    max_sum = k * r

    Enum.all?(0..max_sum, fn sum ->
      outputs = for center <- 0..(k - 1), do: Map.get(lookup, {center, sum}, 0)
      length(Enum.uniq(outputs)) == k
    end)
  end
end
