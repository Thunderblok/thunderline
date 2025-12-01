defmodule Thunderline.Thunderbit.UIContract do
  @moduledoc """
  Thunderbit UI Contract - Rendering Specifications

  Converts Thunderbits to UI-ready specifications following the
  ThunderbitUISpec schema that front-ends consume.

  ## UI Spec Schema

  ```typescript
  interface ThunderbitUISpec {
    id: string;
    canonical_name: string;
    geometry: { type, shape, position };
    visual: { base_color, energy, salience, state, animation };
    links: [{ target_id, relation_type, strength }];
    label: string;
    tooltip: string;
    category: string;
    role: string;
  }
  ```

  ## Usage

      iex> UIContract.to_spec(bit)
      %{id: "...", geometry: %{...}, visual: %{...}, ...}

      iex> UIContract.render_all([bit1, bit2])
      [%{...}, %{...}]
  """

  alias Thunderline.Thunderbit.Category
  alias Thunderline.Thundercore.Thunderbit, as: CoreBit

  # ===========================================================================
  # Types
  # ===========================================================================

  @type ui_spec :: %{
          id: String.t(),
          canonical_name: String.t(),
          geometry: geometry_spec(),
          visual: visual_spec(),
          links: [link_spec()],
          label: String.t(),
          tooltip: String.t(),
          category: String.t(),
          role: String.t()
        }

  @type geometry_spec :: %{
          type: String.t(),
          shape: String.t(),
          position: %{x: float(), y: float(), z: float()}
        }

  @type visual_spec :: %{
          base_color: String.t(),
          energy: float(),
          salience: float(),
          state: String.t(),
          animation: String.t()
        }

  @type link_spec :: %{
          target_id: String.t(),
          relation_type: String.t(),
          strength: float()
        }

  # ===========================================================================
  # Main API
  # ===========================================================================

  @doc """
  Converts a Thunderbit to a UI specification.

  ## Examples

      iex> UIContract.to_spec(bit)
      %{
        id: "abc-123",
        canonical_name: "Proposition.Question/IsItSafe@energy=0.5",
        geometry: %{type: "node", shape: "hex", position: %{x: 0.5, y: 0.5, z: 0}},
        visual: %{base_color: "#8B5CF6", energy: 0.5, salience: 0.5, state: "idle", animation: "spin"},
        links: [],
        label: "Is it safe?",
        tooltip: "Is it safe?",
        category: "cognitive",
        role: "transformer"
      }
  """
  @spec to_spec(map()) :: ui_spec()
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
  Converts multiple Thunderbits to UI specifications.
  """
  @spec render_all([map()]) :: [ui_spec()]
  def render_all(bits) when is_list(bits) do
    Enum.map(bits, &to_spec/1)
  end

  @doc """
  Broadcasts UI specs to the Thunderfield PubSub topic.
  """
  @spec broadcast(ui_spec() | [ui_spec()]) :: :ok
  def broadcast(specs) when is_list(specs) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_spawn, specs}
    )
  end

  def broadcast(spec) when is_map(spec) do
    broadcast([spec])
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

  # ===========================================================================
  # Geometry Building
  # ===========================================================================

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
  # Visual Building
  # ===========================================================================

  defp build_visual(bit, cat) do
    %{
      base_color: cat.geometry.base_color,
      energy: Map.get(bit, :energy, 0.5),
      salience: Map.get(bit, :salience, 0.5),
      state: status_to_state(Map.get(bit, :status, :active)),
      animation: Atom.to_string(cat.geometry.animation)
    }
  end

  defp status_to_state(:spawning), do: "thinking"
  defp status_to_state(:active), do: "idle"
  defp status_to_state(:fading), do: "fading"
  defp status_to_state(:archived), do: "fading"
  defp status_to_state(_), do: "idle"

  # ===========================================================================
  # Links Building
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
