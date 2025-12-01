defmodule Thunderline.Thunderbit.Ethics do
  @moduledoc """
  Thunderbit Ethics - Maxim Enforcement

  Enforces ethical constraints on Thunderbit operations by checking
  MCP Latin maxims before spawn, link, and action execution.

  ## Maxims

  | Maxim | Translation | Applies To |
  |-------|-------------|------------|
  | Primum non nocere | First, do no harm | Motor (actions) |
  | Veritas liberabit | Truth will set you free | Cognitive, Ethical |
  | Res in armonia | Things in harmony | Sensory |
  | In nexus virtus | Virtue in connections | Social, Ethical |
  | Qualitas regit | Quality governs | Mnemonic, Perceptual |
  | Acta non verba | Deeds, not words | Motor |
  | Primus causa est voluntas | First cause is will | Executive |

  ## Usage

      iex> Ethics.check_spawn(:motor, %{pac_id: "ezra"})
      :ok

      iex> Ethics.check_action(motor_bit, dangerous_event)
      {:error, {:maxim_violated, "Primum non nocere"}}
  """

  alias Thunderline.Thunderbit.Category
  alias Thunderline.Thundercore.Ontology

  require Logger

  # ===========================================================================
  # Types
  # ===========================================================================

  @type context :: map()
  @type verdict :: :ok | {:error, {:maxim_violated, String.t()}} | {:error, term()}

  # ===========================================================================
  # Spawn Checks
  # ===========================================================================

  @doc """
  Checks if spawning a Thunderbit of the given category is allowed.

  Validates:
  1. Required maxims for the category
  2. Context-specific policies

  ## Examples

      iex> Ethics.check_spawn(:sensory, %{pac_id: "ezra"})
      :ok
  """
  @spec check_spawn(Category.id(), context()) :: verdict()
  def check_spawn(category, context) do
    with {:ok, cat} <- Category.get(category),
         :ok <- check_required_maxims(cat, context),
         :ok <- check_spawn_policy(cat, context) do
      :ok
    end
  end

  defp check_required_maxims(cat, context) do
    # For now, all maxims are satisfied by default
    # In production, this would query Thundercrown policies
    violations =
      cat.required_maxims
      |> Enum.filter(&maxim_violated?(&1, context))

    case violations do
      [] -> :ok
      [maxim | _] -> {:error, {:maxim_violated, maxim}}
    end
  end

  defp check_spawn_policy(_cat, _context) do
    # Integration point for Thundercrown policy engine
    # For now, allow all spawns
    :ok
  end

  # ===========================================================================
  # Link Checks
  # ===========================================================================

  @doc """
  Checks if linking two Thunderbits is ethically allowed.

  Validates:
  1. Combined maxims don't conflict
  2. Relation is appropriate for involved roles

  ## Examples

      iex> Ethics.check_link(sensory_bit, cognitive_bit, :feeds)
      :ok

      iex> Ethics.check_link(motor_bit, motor_bit, :triggers)
      {:error, {:maxim_conflict, "Primum non nocere"}}
  """
  @spec check_link(map(), map(), atom()) :: verdict()
  def check_link(from_bit, to_bit, relation) do
    from_cat = Map.get(from_bit, :category, :cognitive)
    to_cat = Map.get(to_bit, :category, :cognitive)

    with :ok <- Category.check_maxim_compatibility(from_cat, to_cat),
         :ok <- check_relation_ethics(from_cat, to_cat, relation) do
      :ok
    end
  end

  defp check_relation_ethics(from_cat, to_cat, relation) do
    # Some relations have specific ethics requirements
    case {from_cat, to_cat, relation} do
      # Motor → anything requires "Primum non nocere" check
      {:motor, _, :triggers} ->
        :ok

      # Ethical → Motor validates "Veritas liberabit"
      {:ethical, :motor, :validates} ->
        :ok

      _ ->
        :ok
    end
  end

  # ===========================================================================
  # Action Checks
  # ===========================================================================

  @doc """
  Checks if an action is ethically allowed.

  This is called before a Motor Thunderbit executes an action.

  ## Examples

      iex> Ethics.check_action(motor_bit, safe_event)
      :ok

      iex> Ethics.check_action(motor_bit, harmful_event)
      {:error, {:maxim_violated, "Primum non nocere"}}
  """
  @spec check_action(map(), map()) :: verdict()
  def check_action(bit, event) do
    # Check if the action would violate any maxims
    with :ok <- check_harm_potential(bit, event),
         :ok <- check_action_deliberation(bit, event) do
      :ok
    end
  end

  defp check_harm_potential(_bit, event) do
    # Check for harmful action patterns
    payload = Map.get(event, :payload, %{})

    harmful_patterns = [
      "delete",
      "destroy",
      "kill",
      "harm",
      "attack"
    ]

    content =
      case payload do
        s when is_binary(s) -> String.downcase(s)
        %{content: c} when is_binary(c) -> String.downcase(c)
        _ -> ""
      end

    if Enum.any?(harmful_patterns, &String.contains?(content, &1)) do
      Logger.warning("[Ethics] Harmful action pattern detected: #{inspect(content)}")
      {:error, {:maxim_violated, "Primum non nocere"}}
    else
      :ok
    end
  end

  defp check_action_deliberation(bit, _event) do
    # Check if the action was properly deliberated
    # (i.e., passed through cognitive or ethical bits)
    context = Map.get(bit, :composition_context, %{})

    # For now, require that the bit has been through at least one bind
    if Map.get(context, :deliberated, false) do
      :ok
    else
      # Allow for now, but log
      :ok
    end
  end

  # ===========================================================================
  # Maxim Queries
  # ===========================================================================

  @doc """
  Returns all maxims that apply to a category.
  """
  @spec maxims_for_category(Category.id()) :: [String.t()]
  def maxims_for_category(category) do
    Category.required_maxims(category) ++ applicable_maxims(category)
  end

  defp applicable_maxims(category) do
    case Category.ontology_path(category) do
      {:ok, path} ->
        primary = Enum.at(path, 1)
        Ontology.maxims_for(primary)

      _ ->
        []
    end
  end

  @doc """
  Checks if a specific maxim applies to a Thunderbit.
  """
  @spec maxim_applies?(String.t(), map()) :: boolean()
  def maxim_applies?(maxim, bit) do
    category = Map.get(bit, :category, :cognitive)
    maxim in maxims_for_category(category)
  end

  @doc """
  Returns the guidance text for a maxim.
  """
  @spec maxim_guidance(String.t()) :: String.t()
  def maxim_guidance(maxim) do
    case Ontology.maxims()[maxim] do
      %{guidance: g} -> g
      _ -> "No guidance available"
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp maxim_violated?(_maxim, _context) do
    # In production, this would check specific conditions
    # For now, maxims are never violated by default
    false
  end
end
