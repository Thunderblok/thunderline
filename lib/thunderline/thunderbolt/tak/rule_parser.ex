defmodule Thunderline.Thunderbolt.TAK.RuleParser do
  @moduledoc """
  Parser for Life-like cellular automaton rule strings.

  Supports standard notation like "B3/S23" (Conway's Game of Life):
  - B = Birth: number of neighbors needed for dead cell to become alive
  - S = Survival: number of neighbors needed for live cell to stay alive

  ## Examples

      iex> RuleParser.parse("B3/S23")
      {:ok, %{birth: [3], survival: [2, 3], notation: "B3/S23"}}

      iex> RuleParser.parse("B36/S23")
      {:ok, %{birth: [3, 6], survival: [2, 3], notation: "B36/S23"}}

      iex> RuleParser.parse("invalid")
      {:error, :invalid_format}

  ## Supported Rules

  Common Life-like rules:
  - B3/S23: Conway's Game of Life
  - B36/S23: HighLife (has replicators)
  - B3/S012345678: Life without death
  - B1357/S1357: Replicator
  - B2/S: Seeds (all cells die)
  """

  @type ruleset :: %{
          birth: [integer()],
          survival: [integer()],
          notation: String.t()
        }

  @doc """
  Parse a Life-like rule string into birth and survival conditions.

  ## Parameters
  - `rule_string`: String in "B<digits>/S<digits>" format

  ## Returns
  - `{:ok, ruleset}` on success
  - `{:error, reason}` on parse failure
  """
  @spec parse(String.t()) :: {:ok, ruleset()} | {:error, atom()}
  def parse(rule_string) when is_binary(rule_string) do
    case String.split(rule_string, "/", parts: 2) do
      [birth_part, survival_part] ->
        with {:ok, birth} <- parse_condition(birth_part, "B"),
             {:ok, survival} <- parse_condition(survival_part, "S") do
          {:ok, %{birth: birth, survival: survival, notation: rule_string}}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  def parse(_), do: {:error, :invalid_input}

  @doc """
  Parse a rule string, raising on error.

  ## Examples

      iex> RuleParser.parse!("B3/S23")
      %{birth: [3], survival: [2, 3], notation: "B3/S23"}
  """
  @spec parse!(String.t()) :: ruleset()
  def parse!(rule_string) do
    case parse(rule_string) do
      {:ok, ruleset} -> ruleset
      {:error, reason} -> raise ArgumentError, "Invalid rule: #{inspect(reason)}"
    end
  end

  @doc """
  Convert ruleset back to standard notation string.

  ## Examples

      iex> ruleset = %{birth: [3], survival: [2, 3], notation: "B3/S23"}
      iex> RuleParser.to_string(ruleset)
      "B3/S23"
  """
  @spec to_string(ruleset()) :: String.t()
  def to_string(%{birth: birth, survival: survival}) do
    birth_str = Enum.join(Enum.sort(birth), "")
    survival_str = Enum.join(Enum.sort(survival), "")
    "B#{birth_str}/S#{survival_str}"
  end

  @doc """
  Check if a cell should be alive in the next generation.

  ## Parameters
  - `ruleset`: Parsed ruleset
  - `current_state`: Current cell state (0 = dead, 1 = alive)
  - `neighbor_count`: Number of living neighbors

  ## Returns
  - `1` if cell should be alive
  - `0` if cell should be dead
  """
  @spec apply_rule(ruleset(), integer(), integer()) :: integer()
  def apply_rule(%{birth: birth, survival: survival}, current_state, neighbor_count) do
    cond do
      current_state == 0 and neighbor_count in birth -> 1
      current_state == 1 and neighbor_count in survival -> 1
      true -> 0
    end
  end

  @doc """
  Get common pre-defined rulesets.

  ## Examples

      iex> RuleParser.preset(:game_of_life)
      {:ok, %{birth: [3], survival: [2, 3], notation: "B3/S23"}}

      iex> RuleParser.preset(:highlife)
      {:ok, %{birth: [3, 6], survival: [2, 3], notation: "B36/S23"}}
  """
  @spec preset(atom()) :: {:ok, ruleset()} | {:error, :unknown_preset}
  def preset(name) do
    case name do
      :game_of_life -> {:ok, parse!("B3/S23")}
      :conway -> {:ok, parse!("B3/S23")}
      :highlife -> {:ok, parse!("B36/S23")}
      :replicator -> {:ok, parse!("B1357/S1357")}
      :seeds -> {:ok, parse!("B2/S")}
      :life_without_death -> {:ok, parse!("B3/S012345678")}
      :day_and_night -> {:ok, parse!("B3678/S34678")}
      :maze -> {:ok, parse!("B3/S12345")}
      _ -> {:error, :unknown_preset}
    end
  end

  @doc """
  List all available preset names.
  """
  @spec list_presets() :: [atom()]
  def list_presets do
    [
      :game_of_life,
      :conway,
      :highlife,
      :replicator,
      :seeds,
      :life_without_death,
      :day_and_night,
      :maze
    ]
  end

  # Private Helpers

  defp parse_condition(part, prefix) do
    case String.starts_with?(part, prefix) do
      true ->
        digits = String.trim_leading(part, prefix)
        parse_digits(digits)

      false ->
        {:error, :invalid_prefix}
    end
  end

  defp parse_digits(""), do: {:ok, []}

  defp parse_digits(digits) do
    result =
      digits
      |> String.graphemes()
      |> Enum.map(&parse_digit/1)

    if Enum.all?(result, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(result, fn {:ok, n} -> n end)}
    else
      {:error, :invalid_digits}
    end
  end

  defp parse_digit(char) do
    case Integer.parse(char) do
      {n, ""} when n >= 0 and n <= 8 -> {:ok, n}
      _ -> {:error, :invalid_digit}
    end
  end
end
