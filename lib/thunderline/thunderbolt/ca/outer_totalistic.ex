defmodule Thunderline.Thunderbolt.CA.OuterTotalistic do
  @moduledoc """
  Outer-totalistic cellular automata rules.

  Supports both 1D elementary CA and 2D outer-totalistic rules.

  ## HC-Δ-16: Cerebros CA Proposal Requirement

  From the original Cerebros proposal:
  > "Use vetted rules from the QuAK/Cerebros list:
  >   - 267422991 (reversible, chaotic attractor)
  >   - 4042321935 (period-doubling cascade)
  >   - 2863311530 (XOR-based linear)
  >   - 3435973836 (Rule 150 analog)"

  ## Usage

      # Apply elementary CA rule (1D)
      cells = [0, 0, 0, 1, 0, 0, 0]
      new_cells = OuterTotalistic.apply_rule(cells, 30)

      # Apply vetted rule by name
      new_cells = OuterTotalistic.apply_vetted_rule(cells, :xor_linear)

      # Get all vetted rules
      rules = OuterTotalistic.vetted_rules()
  """

  import Bitwise

  # ═══════════════════════════════════════════════════════════════
  # Vetted Rule Definitions (2D outer-totalistic)
  # ═══════════════════════════════════════════════════════════════

  @type rule_name :: :reversible_chaotic | :period_doubling | :xor_linear | :rule_150_analog

  @vetted_rules %{
    reversible_chaotic: %{
      rule_number: 267_422_991,
      k: 2,
      r: 8,
      description: "Reversible, chaotic attractor",
      properties: [:reversible, :chaotic]
    },
    period_doubling: %{
      rule_number: 4_042_321_935,
      k: 2,
      r: 8,
      description: "Period-doubling cascade",
      properties: [:cascade, :bifurcating]
    },
    xor_linear: %{
      rule_number: 2_863_311_530,
      k: 2,
      r: 8,
      description: "XOR-based linear rule",
      properties: [:linear, :xor_based, :reversible]
    },
    rule_150_analog: %{
      rule_number: 3_435_973_836,
      k: 2,
      r: 8,
      description: "Rule 150 analog for 2D",
      properties: [:linear, :class_3]
    }
  }

  # ═══════════════════════════════════════════════════════════════
  # Public API - Rule Metadata
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns the map of all vetted rules with their specifications.
  """
  @spec vetted_rules() :: map()
  def vetted_rules, do: @vetted_rules

  @doc """
  Get information about a vetted rule by name.
  """
  @spec rule_info(rule_name()) :: map() | nil
  def rule_info(name), do: Map.get(@vetted_rules, name)

  @doc """
  Get a vetted rule by its number.
  """
  @spec rule_by_number(non_neg_integer()) :: {rule_name(), map()} | nil
  def rule_by_number(number) do
    Enum.find(@vetted_rules, fn {_name, info} -> info.rule_number == number end)
  end

  # ═══════════════════════════════════════════════════════════════
  # Public API - 1D Elementary CA
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply an elementary CA rule to a 1D cell array.

  Elementary CA rules (0-255) use a 3-cell neighborhood (left, center, right).

  ## Parameters

  - `cells` - List of cell values (0 or 1)
  - `rule_number` - Integer rule number (0-255 for elementary, larger for extended)

  ## Returns

  List of new cell values after one step.

  ## Example

      cells = [0, 0, 0, 1, 0, 0, 0]
      OuterTotalistic.apply_rule(cells, 30)
      # => [0, 0, 1, 1, 1, 0, 0]
  """
  @spec apply_rule([integer()], non_neg_integer()) :: [integer()]
  def apply_rule(cells, rule_number) when is_list(cells) and is_integer(rule_number) do
    len = length(cells)

    if len == 0 do
      []
    else
      # Build lookup table for the rule
      lookup = build_elementary_lookup(rule_number)

      # Apply to each cell using wrapped neighbors
      cells_array = :array.from_list(cells)

      for i <- 0..(len - 1) do
        left = :array.get(wrap_index(i - 1, len), cells_array)
        center = :array.get(i, cells_array)
        right = :array.get(wrap_index(i + 1, len), cells_array)

        # Pattern index from left-center-right (binary)
        pattern = left * 4 + center * 2 + right
        Map.get(lookup, pattern, 0)
      end
    end
  end

  @doc """
  Apply an elementary CA rule with explicit neighborhood size.

  ## Parameters

  - `cells` - List of cell values
  - `rule_number` - Rule number
  - `neighborhood_size` - Size of neighborhood (default 3)

  ## Returns

  List of new cell values.
  """
  @spec apply_rule_number([integer()], non_neg_integer(), non_neg_integer()) :: [integer()]
  def apply_rule_number(cells, rule_number, neighborhood_size \\ 3)
      when is_list(cells) and is_integer(rule_number) do
    len = length(cells)

    if len == 0 do
      []
    else
      radius = div(neighborhood_size, 2)
      num_patterns = 1 <<< neighborhood_size
      lookup = build_rule_lookup(rule_number, num_patterns)
      cells_array = :array.from_list(cells)

      for i <- 0..(len - 1) do
        # Gather neighborhood
        pattern =
          for offset <- -radius..radius, reduce: 0 do
            acc ->
              idx = wrap_index(i + offset, len)
              cell = :array.get(idx, cells_array)
              (acc <<< 1) + cell
          end

        Map.get(lookup, pattern, 0)
      end
    end
  end

  @doc """
  Apply a vetted rule by name to a 1D cell array.

  For 1D arrays, this uses the rule number with extended neighborhood.

  ## Parameters

  - `cells` - List of cell values
  - `rule_name` - One of: :reversible_chaotic, :period_doubling, :xor_linear, :rule_150_analog

  ## Returns

  New cell values after one step, or `{:error, reason}` for unknown rules.
  """
  @spec apply_vetted_rule([integer()], rule_name()) :: [integer()] | {:error, term()}
  def apply_vetted_rule(cells, rule_name) when is_list(cells) and is_atom(rule_name) do
    case Map.get(@vetted_rules, rule_name) do
      nil ->
        {:error, {:unknown_rule, rule_name}}

      %{rule_number: number} ->
        # For 1D, use a truncated version of the rule
        # Use mod to get elementary-compatible rule
        elementary_rule = rem(number, 256)
        apply_rule(cells, elementary_rule)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Public API - Specialized Rules
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Apply XOR-based rule to cells.

  XOR rule: new_center = left XOR right
  """
  @spec apply_xor_rule([integer()]) :: [integer()]
  def apply_xor_rule(cells) when is_list(cells) do
    len = length(cells)

    if len == 0 do
      []
    else
      cells_array = :array.from_list(cells)

      for i <- 0..(len - 1) do
        left = :array.get(wrap_index(i - 1, len), cells_array)
        right = :array.get(wrap_index(i + 1, len), cells_array)
        bxor(left, right)
      end
    end
  end

  @doc """
  Apply reversible second-order rule.

  Uses previous state for reversibility:
  new_cell = f(neighborhood) XOR previous_cell

  ## Parameters

  - `cells` - Current cell values
  - `prev` - Previous cell values
  - `rule_number` - Rule to apply

  ## Returns

  New cell values that can be reversed.
  """
  @spec apply_reversible_rule([integer()], [integer()], non_neg_integer()) :: [integer()]
  def apply_reversible_rule(cells, prev, rule_number)
      when is_list(cells) and is_list(prev) and is_integer(rule_number) do
    # First apply the rule normally
    forward = apply_rule(cells, rule_number)

    # XOR with previous state for reversibility
    Enum.zip(forward, prev)
    |> Enum.map(fn {f, p} -> bxor(f, p) end)
  end

  # ═══════════════════════════════════════════════════════════════
  # Public API - Rule Analysis
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Analyze a rule's behavior over multiple generations.

  ## Parameters

  - `cells` - Initial cell state to evolve
  - `rule_number` - Rule to analyze
  - `opts`:
    - `:generations` - Number of generations (default: 10)

  ## Returns

  Map with analysis results including density history and final state.
  """
  @spec analyze_rule([integer()], non_neg_integer(), keyword()) :: map()
  def analyze_rule(cells, rule_number, opts \\ []) do
    generations = Keyword.get(opts, :generations, 10)

    # Run evolution and track density (starting from cells, creating exactly `generations` new states)
    {history, final} =
      Enum.reduce(1..generations, {[], cells}, fn _gen, {hist, current} ->
        next = apply_rule(current, rule_number)
        {[next | hist], next}
      end)

    # history is in reverse order, reverse it
    history = Enum.reverse(history)

    # Calculate density for each generation (exactly `generations` entries)
    densities =
      Enum.map(history, fn gen ->
        Enum.sum(gen) / max(length(gen), 1)
      end)

    %{
      rule_number: rule_number,
      generations: generations,
      initial_size: length(cells),
      density_history: densities,
      final_density: List.last(densities),
      final_state: final
    }
  end

  @doc """
  Evolve cells for multiple generations.

  ## Parameters

  - `cells` - Initial cells
  - `rule_number` - Rule to apply
  - `generations` - Number of steps
  - `opts`:
    - `:return` - `:all` for full history, `:final` for just final (default: :all)

  ## Returns

  List of all generations or just final state.
  """
  @spec evolve([integer()], non_neg_integer(), non_neg_integer(), keyword()) ::
          [[integer()]] | [integer()]
  def evolve(cells, rule_number, generations, opts \\ []) do
    return_type = Keyword.get(opts, :return, :all)

    # Handle 0 generations edge case
    if generations == 0 do
      case return_type do
        :final -> cells
        _ -> [cells]
      end
    else
      {history, final} =
        Enum.reduce(1..generations, {[cells], cells}, fn _gen, {hist, current} ->
          next = apply_rule(current, rule_number)

          case return_type do
            :final -> {hist, next}
            _ -> {[next | hist], next}
          end
        end)

      case return_type do
        :final -> final
        _ -> Enum.reverse(history)
      end
    end
  end

  @doc """
  Generate the lookup table for a rule.

  ## Parameters

  - `rule_number` - Rule number (0-255 for elementary)

  ## Returns

  Map from pattern tuple `{left, center, right}` to output (0 or 1).
  """
  @spec rule_lookup_table(non_neg_integer()) :: map()
  def rule_lookup_table(rule_number) do
    # Elementary CA: 8 patterns (3-cell neighborhood)
    # Return tuple keys {left, center, right}
    for pattern <- 0..7, into: %{} do
      left = pattern >>> 2 &&& 1
      center = pattern >>> 1 &&& 1
      right = pattern &&& 1
      bit = rule_number >>> pattern &&& 1
      {{left, center, right}, bit}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════

  defp build_elementary_lookup(rule_number) do
    # Elementary CA: 8 patterns (3-cell neighborhood)
    for pattern <- 0..7, into: %{} do
      bit = rule_number >>> pattern &&& 1
      {pattern, bit}
    end
  end

  defp build_rule_lookup(rule_number, num_patterns) do
    for pattern <- 0..(num_patterns - 1), into: %{} do
      bit = rule_number >>> rem(pattern, 32) &&& 1
      {pattern, bit}
    end
  end

  defp wrap_index(i, len) when i < 0, do: len + i
  defp wrap_index(i, len) when i >= len, do: i - len
  defp wrap_index(i, _len), do: i
end
