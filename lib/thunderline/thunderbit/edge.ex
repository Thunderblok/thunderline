defmodule Thunderline.Thunderbit.Edge do
  @moduledoc """
  Thunderedge - A directed connection between Thunderbits

  Represents a typed relationship between two Thunderbits in the computational graph.
  Edges have semantic meaning through their relation type and enforce the wiring matrix.

  ## Relation Types

  - `:feeds` — data flows from source to target
  - `:inhibits` — source suppresses target
  - `:modulates` — source influences target parameters
  - `:contains` — hierarchical containment
  - `:references` — soft pointer / weak link
  - `:stores_in` — write to memory
  - `:retrieves` — read from memory
  - `:constrains` — ethical filtering
  - `:commands` — action trigger
  - `:orchestrates` — controller sequencing

  ## Usage

      {:ok, edge} = Edge.new(sensory_bit.id, cognitive_bit.id, :feeds)
      Edge.strength(edge)  # => 1.0
  """

  @type relation ::
          :feeds
          | :inhibits
          | :modulates
          | :contains
          | :references
          | :stores_in
          | :retrieves
          | :constrains
          | :commands
          | :orchestrates
          | :consolidates
          | :contextualizes
          | :expresses
          | :filters

  @type t :: %__MODULE__{
          id: String.t(),
          from_id: String.t(),
          to_id: String.t(),
          from_category: atom(),
          to_category: atom(),
          relation: relation(),
          strength: float(),
          metadata: map(),
          created_at: DateTime.t()
        }

  defstruct [
    :id,
    :from_id,
    :to_id,
    :from_category,
    :to_category,
    :relation,
    :strength,
    :metadata,
    :created_at
  ]

  # ===========================================================================
  # Relation Semantics
  # ===========================================================================

  @relation_semantics %{
    feeds: %{
      description: "Data flows from source to target",
      symmetric: false,
      strength_default: 1.0
    },
    inhibits: %{
      description: "Source suppresses target activation",
      symmetric: false,
      strength_default: 0.5
    },
    modulates: %{
      description: "Source influences target parameters",
      symmetric: false,
      strength_default: 0.3
    },
    contains: %{
      description: "Source hierarchically contains target",
      symmetric: false,
      strength_default: 1.0
    },
    references: %{
      description: "Soft pointer / weak link",
      symmetric: false,
      strength_default: 0.2
    },
    stores_in: %{
      description: "Source writes to memory target",
      symmetric: false,
      strength_default: 1.0
    },
    retrieves: %{
      description: "Source reads from memory target",
      symmetric: false,
      strength_default: 0.8
    },
    constrains: %{
      description: "Ethical filtering from critic",
      symmetric: false,
      strength_default: 1.0
    },
    commands: %{
      description: "Decision triggers action",
      symmetric: false,
      strength_default: 1.0
    },
    orchestrates: %{
      description: "Controller sequences target",
      symmetric: false,
      strength_default: 0.9
    },
    consolidates: %{
      description: "Thought consolidates to memory",
      symmetric: false,
      strength_default: 0.7
    },
    contextualizes: %{
      description: "Social context informs reasoning",
      symmetric: false,
      strength_default: 0.5
    },
    expresses: %{
      description: "Reasoning expresses to social",
      symmetric: false,
      strength_default: 0.8
    },
    filters: %{
      description: "Ethics filters actions",
      symmetric: false,
      strength_default: 1.0
    }
  }

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new edge between two Thunderbits.

  ## Parameters

  - `from_id` - Source Thunderbit ID
  - `to_id` - Target Thunderbit ID
  - `relation` - The relation type
  - `opts` - Optional parameters

  ## Options

  - `:from_category` - Category of source bit
  - `:to_category` - Category of target bit
  - `:strength` - Edge strength (0.0-1.0)
  - `:metadata` - Additional data

  ## Examples

      iex> Edge.new("bit-1", "bit-2", :feeds)
      {:ok, %Edge{from_id: "bit-1", to_id: "bit-2", relation: :feeds}}
  """
  def new(from_id, to_id, relation, opts \\ []) do
    if valid_relation?(relation) do
      edge = %__MODULE__{
        id: generate_id(),
        from_id: from_id,
        to_id: to_id,
        from_category: Keyword.get(opts, :from_category),
        to_category: Keyword.get(opts, :to_category),
        relation: relation,
        strength: Keyword.get(opts, :strength, default_strength(relation)),
        metadata: Keyword.get(opts, :metadata, %{}),
        created_at: DateTime.utc_now()
      }

      {:ok, edge}
    else
      {:error, {:invalid_relation, relation}}
    end
  end

  @doc """
  Creates a new edge, raising on error.
  """
  def new!(from_id, to_id, relation, opts \\ []) do
    case new(from_id, to_id, relation, opts) do
      {:ok, edge} -> edge
      {:error, reason} -> raise ArgumentError, "Failed to create edge: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Returns all valid relation types.
  """
  def relation_types do
    Map.keys(@relation_semantics)
  end

  @doc """
  Checks if a relation type is valid.
  """
  def valid_relation?(relation) do
    Map.has_key?(@relation_semantics, relation)
  end

  @doc """
  Returns the default strength for a relation type.
  """
  def default_strength(relation) do
    case Map.get(@relation_semantics, relation) do
      %{strength_default: s} -> s
      _ -> 1.0
    end
  end

  @doc """
  Returns the description for a relation type.
  """
  def relation_description(relation) do
    case Map.get(@relation_semantics, relation) do
      %{description: d} -> d
      _ -> "Unknown relation"
    end
  end

  # ===========================================================================
  # Transformations
  # ===========================================================================

  @doc """
  Updates the strength of an edge.
  """
  def set_strength(%__MODULE__{} = edge, strength) when strength >= 0 and strength <= 1 do
    %{edge | strength: strength}
  end

  @doc """
  Adds metadata to an edge.
  """
  def put_metadata(%__MODULE__{} = edge, key, value) do
    %{edge | metadata: Map.put(edge.metadata, key, value)}
  end

  # ===========================================================================
  # Serialization
  # ===========================================================================

  @doc """
  Converts edge to a map for serialization.
  """
  def to_map(%__MODULE__{} = edge) do
    %{
      id: edge.id,
      from_id: edge.from_id,
      to_id: edge.to_id,
      from_category: edge.from_category && Atom.to_string(edge.from_category),
      to_category: edge.to_category && Atom.to_string(edge.to_category),
      relation: Atom.to_string(edge.relation),
      strength: edge.strength,
      metadata: edge.metadata,
      created_at: DateTime.to_iso8601(edge.created_at)
    }
  end

  @doc """
  Creates edge from a map.
  """
  def from_map(map) do
    new(
      map["from_id"] || map[:from_id],
      map["to_id"] || map[:to_id],
      parse_relation(map["relation"] || map[:relation]),
      from_category: parse_category(map["from_category"] || map[:from_category]),
      to_category: parse_category(map["to_category"] || map[:to_category]),
      strength: map["strength"] || map[:strength] || 1.0,
      metadata: map["metadata"] || map[:metadata] || %{}
    )
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp generate_id do
    "edge-" <> Thunderline.UUID.v7()
  end

  defp parse_relation(r) when is_atom(r), do: r
  defp parse_relation(r) when is_binary(r), do: String.to_existing_atom(r)
  defp parse_relation(_), do: :references

  defp parse_category(nil), do: nil
  defp parse_category(c) when is_atom(c), do: c
  defp parse_category(c) when is_binary(c), do: String.to_existing_atom(c)
end
