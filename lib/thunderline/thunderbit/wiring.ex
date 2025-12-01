defmodule Thunderline.Thunderbit.Wiring do
  @moduledoc """
  Thunderbit Wiring Rules

  Validates connections between Thunderbits based on category composition rules.
  Ensures that the computational graph maintains valid data flow patterns.

  ## Wiring Rules

  ```
  VALID WIRING:
    Observer  → Transformer  (sense → think)
    Observer  → Storage      (sense → remember)
    Transformer → Router     (think → route)
    Transformer → Actuator   (think → act)
    Transformer → Critic     (think → judge)
    Router → Actuator        (route → act)
    Critic → Actuator        (judge → allow/deny act)
    Controller → *           (orchestrate anything)

  INVALID WIRING:
    Actuator → Observer      (can't un-act)
    Critic → Critic          (no infinite regress)
    Storage → Actuator       (memory doesn't act directly)
  ```

  ## Usage

      iex> Wiring.validate_link(sensory_bit, cognitive_bit)
      :ok

      iex> Wiring.validate_link(motor_bit, sensory_bit)
      {:error, {:invalid_wiring, :motor, :sensory}}
  """

  alias Thunderline.Thunderbit.Category

  # ===========================================================================
  # Types
  # ===========================================================================

  @type edge :: %{
          from_id: String.t(),
          to_id: String.t(),
          from_category: Category.id(),
          to_category: Category.id(),
          relation: atom(),
          metadata: map()
        }

  @type validation_error ::
          {:invalid_wiring, Category.id(), Category.id()}
          | {:maxim_conflict, String.t()}
          | {:capability_violation, atom()}
          | {:unknown_category, atom()}

  # ===========================================================================
  # Relation Types
  # ===========================================================================

  @relation_types %{
    feeds: %{
      description: "Data flows from source to target",
      symmetric: false,
      valid_roles: [:observer, :transformer, :analyzer, :storage]
    },
    triggers: %{
      description: "Source initiates action in target",
      symmetric: false,
      valid_roles: [:controller, :transformer]
    },
    validates: %{
      description: "Critic evaluates before target executes",
      symmetric: false,
      valid_roles: [:critic]
    },
    stores: %{
      description: "Data is persisted in storage",
      symmetric: false,
      valid_roles: [:storage]
    },
    routes_to: %{
      description: "Router selects target for message",
      symmetric: false,
      valid_roles: [:router]
    },
    controls: %{
      description: "Controller sequences target",
      symmetric: false,
      valid_roles: [:controller]
    },
    recalls: %{
      description: "Retrieves data from storage",
      symmetric: false,
      valid_roles: [:storage]
    }
  }

  @doc "Returns all valid relation types"
  def relation_types, do: Map.keys(@relation_types)

  @doc "Returns metadata for a relation type"
  def relation_type(rel) when is_map_key(@relation_types, rel) do
    {:ok, Map.get(@relation_types, rel)}
  end

  def relation_type(_), do: {:error, :unknown_relation}

  # ===========================================================================
  # Validation
  # ===========================================================================

  @doc """
  Validates that a link between two Thunderbits is allowed.

  Checks:
  1. Category wiring rules
  2. Maxim compatibility
  3. Role constraints

  ## Examples

      iex> Wiring.validate_link(sensory_bit, cognitive_bit)
      :ok

      iex> Wiring.validate_link(motor_bit, sensory_bit)
      {:error, {:invalid_wiring, :motor, :sensory}}
  """
  @spec validate_link(map(), map()) :: :ok | {:error, validation_error()}
  def validate_link(%{category: from_cat}, %{category: to_cat}) do
    validate_categories(from_cat, to_cat)
  end

  def validate_link(from_bit, to_bit) when is_struct(from_bit) and is_struct(to_bit) do
    from_cat = infer_category(from_bit)
    to_cat = infer_category(to_bit)
    validate_categories(from_cat, to_cat)
  end

  @doc """
  Validates that two categories can be connected.
  """
  @spec validate_categories(Category.id(), Category.id()) :: :ok | {:error, validation_error()}
  def validate_categories(from_cat, to_cat) do
    with {:ok, _} <- Category.get(from_cat),
         {:ok, _} <- Category.get(to_cat),
         true <- Category.wiring_valid?(from_cat, to_cat),
         :ok <- Category.check_maxim_compatibility(from_cat, to_cat) do
      :ok
    else
      false -> {:error, {:invalid_wiring, from_cat, to_cat}}
      {:error, {:maxim_conflict, _} = err} -> {:error, err}
      {:error, :unknown_category} -> {:error, {:unknown_category, from_cat}}
    end
  end

  @doc """
  Validates a specific relation between categories.
  """
  @spec validate_relation(Category.id(), Category.id(), atom()) ::
          :ok | {:error, validation_error()}
  def validate_relation(from_cat, to_cat, relation) do
    with :ok <- validate_categories(from_cat, to_cat),
         {:ok, rel_meta} <- relation_type(relation),
         {:ok, from} <- Category.get(from_cat) do
      if from.role in rel_meta.valid_roles do
        :ok
      else
        {:error, {:invalid_relation_for_role, relation, from.role}}
      end
    end
  end

  @doc """
  Creates an edge struct between two Thunderbits if valid.
  """
  @spec create_edge(map(), map(), atom(), map()) :: {:ok, edge()} | {:error, validation_error()}
  def create_edge(from_bit, to_bit, relation, metadata \\ %{}) do
    from_cat = infer_category(from_bit)
    to_cat = infer_category(to_bit)

    with :ok <- validate_relation(from_cat, to_cat, relation) do
      edge = %{
        from_id: from_bit.id,
        to_id: to_bit.id,
        from_category: from_cat,
        to_category: to_cat,
        relation: relation,
        metadata: metadata
      }

      {:ok, edge}
    end
  end

  # ===========================================================================
  # Graph Analysis
  # ===========================================================================

  @doc """
  Checks if a proposed edge would create a cycle in the graph.
  Only relevant for non-feedback compositions.
  """
  @spec would_create_cycle?(String.t(), String.t(), [edge()]) :: boolean()
  def would_create_cycle?(from_id, to_id, existing_edges) do
    # Build adjacency list
    adj = build_adjacency(existing_edges)

    # Check if there's already a path from to_id to from_id
    reachable?(to_id, from_id, adj, MapSet.new())
  end

  defp build_adjacency(edges) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      Map.update(acc, edge.from_id, [edge.to_id], &[edge.to_id | &1])
    end)
  end

  defp reachable?(from, target, adj, visited) do
    cond do
      from == target ->
        true

      MapSet.member?(visited, from) ->
        false

      true ->
        neighbors = Map.get(adj, from, [])
        new_visited = MapSet.put(visited, from)
        Enum.any?(neighbors, &reachable?(&1, target, adj, new_visited))
    end
  end

  @doc """
  Validates an entire graph of edges.
  Returns all validation errors found.
  """
  @spec validate_graph([edge()]) :: :ok | {:error, [validation_error()]}
  def validate_graph(edges) do
    errors =
      edges
      |> Enum.map(fn edge ->
        case validate_relation(edge.from_category, edge.to_category, edge.relation) do
          :ok -> nil
          {:error, err} -> {edge, err}
        end
      end)
      |> Enum.reject(&is_nil/1)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Returns all valid targets for a given Thunderbit based on its category.
  """
  @spec valid_targets_for(map()) :: [Category.id()]
  def valid_targets_for(bit) do
    Category.valid_targets(infer_category(bit))
  end

  @doc """
  Returns all valid sources for a given Thunderbit based on its category.
  """
  @spec valid_sources_for(map()) :: [Category.id()]
  def valid_sources_for(bit) do
    Category.valid_sources(infer_category(bit))
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp infer_category(%{category: cat}) when is_atom(cat), do: cat

  defp infer_category(%{kind: kind}) do
    # Map legacy Thunderbit kinds to categories
    case kind do
      :question -> :cognitive
      :command -> :motor
      :intent -> :cognitive
      :assertion -> :cognitive
      :goal -> :ethical
      :memory -> :mnemonic
      :world_update -> :sensory
      :error -> :perceptual
      :system -> :executive
      _ -> :cognitive
    end
  end

  defp infer_category(_), do: :cognitive
end
