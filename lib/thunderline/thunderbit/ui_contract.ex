defmodule Thunderline.Thunderbit.UIContract do
  @moduledoc """
  Thunderbit UI Contract - Slim DTOs for Front-End Rendering

  Converts Thunderbits to minimal, UI-ready DTOs following the
  ThunderbitDTO and ThunderedgeDTO schemas. These are intentionally
  slim to prevent front-end from accessing internal protocol state.

  ## Design Principle: Slim DTOs

  The front-end should ONLY receive:
  - What it needs to render (geometry, visual state)
  - What it needs for interaction (id, links)
  - NO internal protocol state (maxims, policies, ethics verdicts)

  ## ThunderbitDTO Schema

  ```typescript
  interface ThunderbitDTO {
    id: string;
    category: string;
    role: string;
    label: string;
    tooltip: string;
    energy: number;      // 0.0 - 1.0
    salience: number;    // 0.0 - 1.0
    status: string;      // "spawning" | "active" | "fading"
    geometry: {
      type: string;      // "node" | "edge" | "region"
      shape: string;     // "circle" | "hex" | "diamond" | "square"
      base_color: string;
      position: { x: number; y: number; z: number };
    };
    links: ThunderedgeDTO[];
  }

  interface ThunderedgeDTO {
    id: string;
    from_id: string;
    to_id: string;
    relation: string;    // "feeds" | "inhibits" | "modulates" | etc.
    strength: number;    // 0.0 - 1.0
  }
  ```

  ## Usage

      # Single bit to DTO
      dto = UIContract.to_dto(bit)

      # Multiple bits with edges
      dtos = UIContract.to_dtos(bits, edges)

      # Broadcast to front-end
      :ok = UIContract.broadcast(bits, edges)
  """

  alias Thunderline.Thunderbit.{Category, Edge}
  alias Thunderline.Thundercore.Thunderbit, as: CoreBit

  # ===========================================================================
  # Types
  # ===========================================================================

  @type thunderbit_dto :: %{
          id: String.t(),
          category: String.t(),
          role: String.t(),
          label: String.t(),
          tooltip: String.t(),
          energy: float(),
          salience: float(),
          status: String.t(),
          geometry: geometry_dto(),
          links: [thunderedge_dto()]
        }

  @type geometry_dto :: %{
          type: String.t(),
          shape: String.t(),
          base_color: String.t(),
          position: %{x: float(), y: float(), z: float()}
        }

  @type thunderedge_dto :: %{
          id: String.t(),
          from_id: String.t(),
          to_id: String.t(),
          relation: String.t(),
          strength: float()
        }

  # ===========================================================================
  # Main API - Slim DTOs
  # ===========================================================================

  @doc """
  Converts a Thunderbit to a slim DTO for front-end consumption.

  Only includes fields necessary for rendering. Internal protocol
  state (maxims, policies, ethics_verdict) is NOT included.

  ## Examples

      dto = UIContract.to_dto(bit)
      # => %{id: "abc", category: "cognitive", label: "Is it safe?", ...}
  """
  @spec to_dto(map()) :: thunderbit_dto()
  def to_dto(bit) do
    to_dto(bit, [])
  end

  @doc """
  Converts a Thunderbit to a slim DTO with related edges.
  """
  @spec to_dto(map(), [Edge.t()] | [map()]) :: thunderbit_dto()
  def to_dto(bit, edges) do
    category = Map.get(bit, :category, infer_category(bit))
    {:ok, cat} = Category.get(category)
    
    # Find edges involving this bit
    bit_edges = find_bit_edges(bit.id, edges)

    %{
      id: bit.id,
      category: Atom.to_string(category),
      role: Atom.to_string(cat.role),
      label: build_label(bit),
      tooltip: build_tooltip(bit),
      energy: Map.get(bit, :energy, 0.5),
      salience: Map.get(bit, :salience, 0.5),
      status: status_to_string(Map.get(bit, :status, :active)),
      geometry: build_geometry_dto(bit, cat),
      links: Enum.map(bit_edges, &edge_to_dto/1)
    }
  end

  @doc """
  Converts multiple Thunderbits to slim DTOs.
  """
  @spec to_dtos([map()]) :: [thunderbit_dto()]
  def to_dtos(bits) when is_list(bits) do
    to_dtos(bits, [])
  end

  @doc """
  Converts multiple Thunderbits to slim DTOs with edges.
  """
  @spec to_dtos([map()], [Edge.t()] | [map()]) :: [thunderbit_dto()]
  def to_dtos(bits, edges) when is_list(bits) do
    Enum.map(bits, fn bit -> to_dto(bit, edges) end)
  end

  @doc """
  Converts an Edge to a slim DTO.
  """
  @spec edge_to_dto(Edge.t() | map()) :: thunderedge_dto()
  def edge_to_dto(%Edge{} = edge) do
    %{
      id: edge.id,
      from_id: edge.from_id,
      to_id: edge.to_id,
      relation: Atom.to_string(edge.relation),
      strength: edge.strength
    }
  end

  def edge_to_dto(%{from_id: from_id, to_id: to_id, relation: relation} = edge) do
    %{
      id: Map.get(edge, :id, "edge-#{from_id}-#{to_id}"),
      from_id: from_id,
      to_id: to_id,
      relation: to_string(relation),
      strength: Map.get(edge, :strength, 0.5)
    }
  end

  # ===========================================================================
  # Broadcasting
  # ===========================================================================

  @doc """
  Broadcasts bits and edges as slim DTOs to the Thunderfield topic.

  ## Parameters
  - `bits` - List of Thunderbits to broadcast
  - `edges` - List of edges (optional, defaults to [])

  ## Returns
  - `:ok`
  """
  @spec broadcast([map()], [Edge.t()] | [map()]) :: :ok
  def broadcast(bits, edges \\ []) when is_list(bits) do
    dtos = to_dtos(bits, edges)
    edge_dtos = Enum.map(edges, &edge_to_dto/1)
    
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_spawn, %{bits: dtos, edges: edge_dtos}}
    )
  end

  @doc """
  Broadcasts a single bit as slim DTO.
  """
  @spec broadcast_one(map(), [Edge.t()] | [map()]) :: :ok
  def broadcast_one(bit, edges \\ []) do
    broadcast([bit], edges)
  end

  @doc """
  Broadcasts a position update for a Thunderbit.
  """
  @spec broadcast_position(String.t(), map()) :: :ok
  def broadcast_position(bit_id, position) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_move, %{id: bit_id, position: position}}
    )
  end

  @doc """
  Broadcasts a state change for a Thunderbit.
  """
  @spec broadcast_state(String.t(), String.t()) :: :ok
  def broadcast_state(bit_id, state) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_state, %{id: bit_id, state: state}}
    )
  end

  @doc """
  Broadcasts a new edge connection.
  """
  @spec broadcast_edge(Edge.t() | map()) :: :ok
  def broadcast_edge(edge) do
    dto = edge_to_dto(edge)
    
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_link, dto}
    )
  end

  # ===========================================================================
  # Legacy API (for backward compatibility)
  # ===========================================================================

  @doc """
  Converts a Thunderbit to the legacy UI specification format.

  ## Deprecated
  Use `to_dto/1` instead for slim DTOs.
  """
  @spec to_spec(map()) :: map()
  def to_spec(bit) do
    category = Map.get(bit, :category, infer_category(bit))
    {:ok, cat} = Category.get(category)

    %{
      id: bit.id,
      canonical_name: get_canonical_name(bit),
      geometry: build_geometry(bit, cat),
      visual: build_visual(bit, cat),
      links: build_links(bit),
      label: build_label(bit),
      tooltip: build_tooltip(bit),
      category: Atom.to_string(category),
      role: Atom.to_string(cat.role)
    }
  end

  @doc """
  Converts multiple Thunderbits to legacy UI specifications.

  ## Deprecated
  Use `to_dtos/1` instead for slim DTOs.
  """
  @spec render_all([map()]) :: [map()]
  def render_all(bits) when is_list(bits) do
    Enum.map(bits, &to_spec/1)
  end

  # ===========================================================================
  # Geometry Building
  # ===========================================================================

  defp build_geometry_dto(bit, cat) do
    %{
      type: Atom.to_string(cat.geometry.type),
      shape: Atom.to_string(cat.geometry.shape),
      base_color: cat.geometry.base_color,
      position: get_position(bit)
    }
  end

  defp build_geometry(bit, cat) do
    %{
      type: Atom.to_string(cat.geometry.type),
      shape: Atom.to_string(cat.geometry.shape),
      position: get_position(bit)
    }
  end

  defp get_position(bit) do
    case Map.get(bit, :position) do
      %{x: x, y: y, z: z} -> %{x: x, y: y, z: z}
      nil -> spawn_position()
    end
  end

  defp spawn_position do
    jitter = :rand.uniform() * 0.1
    angle = :rand.uniform() * 2 * :math.pi()

    %{
      x: 0.5 + jitter * :math.cos(angle),
      y: 0.5 + jitter * :math.sin(angle),
      z: 0.0
    }
  end

  # ===========================================================================
  # Visual Building (legacy)
  # ===========================================================================

  defp build_visual(bit, cat) do
    %{
      base_color: cat.geometry.base_color,
      energy: Map.get(bit, :energy, 0.5),
      salience: Map.get(bit, :salience, 0.5),
      state: status_to_string(Map.get(bit, :status, :active)),
      animation: Atom.to_string(cat.geometry.animation)
    }
  end

  defp status_to_string(:spawning), do: "spawning"
  defp status_to_string(:active), do: "active"
  defp status_to_string(:fading), do: "fading"
  defp status_to_string(:archived), do: "archived"
  defp status_to_string(_), do: "active"

  # ===========================================================================
  # Links Building (legacy)
  # ===========================================================================

  defp build_links(bit) do
    links = Map.get(bit, :links, [])

    Enum.map(links, fn link ->
      case link do
        %{target_id: id, relation: rel, strength: s} ->
          %{target_id: id, relation_type: Atom.to_string(rel), strength: s}

        id when is_binary(id) ->
          %{target_id: id, relation_type: "related", strength: 0.5}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp find_bit_edges(bit_id, edges) do
    Enum.filter(edges, fn edge ->
      from_id = Map.get(edge, :from_id)
      to_id = Map.get(edge, :to_id)
      from_id == bit_id || to_id == bit_id
    end)
  end

  # ===========================================================================
  # Label/Tooltip Building
  # ===========================================================================

  defp build_label(bit) do
    content = Map.get(bit, :content, "")

    content
    |> String.slice(0, 30)
    |> then(fn s -> if String.length(content) > 30, do: s <> "...", else: s end)
  end

  defp build_tooltip(bit) do
    content = Map.get(bit, :content, "")
    category = Map.get(bit, :category, :unknown)
    energy = Map.get(bit, :energy, 0.5)

    """
    #{content}
    ---
    Category: #{category}
    Energy: #{Float.round(energy * 100, 0)}%
    """
    |> String.trim()
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp get_canonical_name(bit) do
    if Map.has_key?(bit, :__struct__) and bit.__struct__ == CoreBit do
      CoreBit.canonical_name(bit)
    else
      # Build a simple canonical name
      category = Map.get(bit, :category, :cognitive)
      content = Map.get(bit, :content, "") |> String.slice(0, 20)
      "#{category}/#{content}"
    end
  rescue
    _ -> "Unknown/Bit"
  end

  defp infer_category(bit) do
    case Map.get(bit, :kind) do
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
end
