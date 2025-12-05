defmodule Thunderline.Thundercore.Thunderbit do
  @moduledoc """
  Thunderbit - The core unit of meaning in Thunderline.

  A Thunderbit represents a semantic chunk of information that can be visualized,
  reasoned about, and ethically evaluated. Thunderbits are spawned from user input
  (text or voice) and flow through the system as the atoms of meaning.

  ## Schema

  Every Thunderbit has:
  - `:id` - Unique identifier (UUID)
  - `:kind` - Ontological classification (:intent, :question, :command, :memory, etc.)
  - `:source` - Origin (:text, :voice, :system, :pac)
  - `:content` - The raw text that birthed this bit
  - `:ontology_path` - Full path in the upper ontology
  - `:tags` - Extracted entities and topics
  - `:energy` - Confidence/importance score (0.0-1.0)
  - `:salience` - Attention priority (0.0-1.0)
  - `:position` - UI coordinates {x, y, z}
  - `:links` - Related Thunderbit IDs
  - `:maxims` - Applicable MCP ethics maxims
  - `:owner` - Agent/module responsible for this bit
  - `:status` - Lifecycle state (:spawning, :active, :fading, :archived)

  ## Grammar

  Canonical name format:
      <OntologyPath>/<Name>@<Attributes>

  Example:
      Proposition.Question/IsAreaClear@energy=0.72,owner=User1

  ## Usage

      # Create from raw text
      {:ok, bit} = Thunderbit.from_text("Is the crash site clear?", source: :voice)

      # Get canonical name
      Thunderbit.canonical_name(bit)
      # => "Proposition.Question/IsAreaClear@energy=0.72"

      # Spawn into UI field
      Thunderbit.spawn(bit)
  """

  alias Thunderline.Thundercore.Ontology

  @type kind ::
          :intent
          | :question
          | :command
          | :memory
          | :world_update
          | :assertion
          | :goal
          | :error
          | :system

  @type source :: :text | :voice | :system | :pac

  @type status :: :spawning | :active | :fading | :archived

  @type position :: %{x: float(), y: float(), z: float()}

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          source: source(),
          content: String.t(),
          ontology_path: [atom()],
          tags: [String.t()],
          energy: float(),
          salience: float(),
          position: position(),
          links: [String.t()],
          thundercell_ids: [String.t()],
          maxims: [String.t()],
          owner: String.t() | nil,
          status: status(),
          inserted_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :id,
    :kind,
    :source,
    :content,
    :ontology_path,
    :tags,
    :energy,
    :salience,
    :position,
    :links,
    :thundercell_ids,
    :maxims,
    :owner,
    :status,
    :inserted_at,
    :metadata
  ]

  # ===========================================================================
  # Kind → Ontology Mappings
  # ===========================================================================

  @kind_to_ontology %{
    intent: [:being, :proposition, :assertion],
    question: [:being, :proposition, :question],
    command: [:being, :process, :action],
    memory: [:being, :entity, :conceptual],
    world_update: [:being, :process, :event],
    assertion: [:being, :proposition, :assertion],
    goal: [:being, :proposition, :goal],
    error: [:being, :process, :event],
    system: [:being, :process, :event]
  }

  @doc "Returns the ontology path for a Thunderbit kind"
  def ontology_path_for_kind(kind) when is_map_key(@kind_to_ontology, kind) do
    @kind_to_ontology[kind]
  end

  def ontology_path_for_kind(_), do: [:being, :proposition]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new Thunderbit with the given attributes.

  ## Options
  - `:kind` - The semantic kind (required)
  - `:source` - Origin of the bit (default: :system)
  - `:content` - Raw text content (required)
  - `:tags` - List of tags (default: [])
  - `:energy` - Confidence score 0-1 (default: 0.5)
  - `:salience` - Attention priority 0-1 (default: 0.5)
  - `:owner` - Responsible agent (default: nil)
  - `:links` - Related bit IDs (default: [])
  - `:thundercell_ids` - Associated Thundercell IDs (default: [])
  - `:metadata` - Additional data (default: %{})

  ## Examples

      iex> Thunderbit.new(kind: :question, content: "What is happening?")
      {:ok, %Thunderbit{kind: :question, ...}}
  """
  def new(opts) do
    kind = Keyword.fetch!(opts, :kind)
    content = Keyword.fetch!(opts, :content)

    ontology_path = ontology_path_for_kind(kind)
    primary = Enum.at(ontology_path, 1, :proposition)
    maxims = Ontology.maxims_for(primary)

    bit = %__MODULE__{
      id: generate_id(),
      kind: kind,
      source: Keyword.get(opts, :source, :system),
      content: content,
      ontology_path: ontology_path,
      tags: Keyword.get(opts, :tags, []),
      energy: Keyword.get(opts, :energy, 0.5),
      salience: Keyword.get(opts, :salience, 0.5),
      position: spawn_position(),
      links: Keyword.get(opts, :links, []),
      thundercell_ids: Keyword.get(opts, :thundercell_ids, []),
      maxims: maxims,
      owner: Keyword.get(opts, :owner),
      status: :spawning,
      inserted_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    {:ok, bit}
  end

  @doc """
  Creates a Thunderbit, raising on error.
  """
  def new!(opts) do
    # new/1 currently always returns {:ok, bit}
    {:ok, bit} = new(opts)
    bit
  end

  # ===========================================================================
  # Canonical Name (Grammar)
  # ===========================================================================

  @doc """
  Returns the canonical name for a Thunderbit following the grammar:
  `<OntologyPath>/<Name>@<Attributes>`

  ## Examples

      iex> bit = Thunderbit.new!(kind: :question, content: "Is it safe?")
      iex> Thunderbit.canonical_name(bit)
      "Proposition.Question/IsItSafe@energy=0.5,status=spawning"
  """
  def canonical_name(%__MODULE__{} = bit) do
    path_str =
      bit.ontology_path
      |> Enum.drop(1)
      |> Enum.map(&camelize/1)
      |> Enum.join(".")

    name = content_to_name(bit.content)
    attrs = encode_attributes(bit)

    "#{path_str}/#{name}@#{attrs}"
  end

  defp camelize(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp content_to_name(content) do
    content
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.take(4)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp encode_attributes(%__MODULE__{} = bit) do
    [
      "energy=#{Float.round(bit.energy, 2)}",
      "status=#{bit.status}",
      if(bit.owner, do: "owner=#{bit.owner}", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  # ===========================================================================
  # Parsing (Grammar → Thunderbit)
  # ===========================================================================

  @doc """
  Parses a canonical name string back into a Thunderbit.

  ## Examples

      iex> Thunderbit.parse("Proposition.Question/IsItSafe@energy=0.72")
      {:ok, %Thunderbit{kind: :question, energy: 0.72, ...}}
  """
  def parse(canonical) when is_binary(canonical) do
    with [path_and_name, attrs_str] <- String.split(canonical, "@", parts: 2),
         [path_str, name] <- String.split(path_and_name, "/", parts: 2),
         {:ok, ontology_path} <- parse_path(path_str),
         {:ok, attrs} <- parse_attributes(attrs_str) do
      kind = infer_kind_from_path(ontology_path)

      bit = %__MODULE__{
        id: generate_id(),
        kind: kind,
        source: :system,
        content: name_to_content(name),
        ontology_path: [:being | ontology_path],
        tags: [],
        energy: Map.get(attrs, :energy, 0.5),
        salience: Map.get(attrs, :salience, 0.5),
        position: spawn_position(),
        links: [],
        maxims: Ontology.maxims_for(Enum.at(ontology_path, 0, :proposition)),
        owner: Map.get(attrs, :owner),
        status: parse_status(Map.get(attrs, :status, "spawning")),
        inserted_at: DateTime.utc_now(),
        metadata: %{}
      }

      {:ok, bit}
    else
      _ -> {:error, :invalid_canonical_name}
    end
  end

  defp parse_path(path_str) do
    path =
      path_str
      |> String.split(".")
      |> Enum.map(&String.downcase/1)
      |> Enum.map(&String.to_atom/1)

    {:ok, path}
  end

  defp parse_attributes(attrs_str) do
    attrs =
      attrs_str
      |> String.split(",")
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(&(length(&1) == 2))
      |> Enum.map(fn [k, v] -> {String.to_atom(k), parse_value(v)} end)
      |> Map.new()

    {:ok, attrs}
  end

  defp parse_value(v) do
    cond do
      v =~ ~r/^\d+\.\d+$/ -> String.to_float(v)
      v =~ ~r/^\d+$/ -> String.to_integer(v)
      true -> v
    end
  end

  defp infer_kind_from_path(path) do
    case path do
      [:proposition, :question | _] -> :question
      [:proposition, :goal | _] -> :goal
      [:proposition, :assertion | _] -> :assertion
      [:proposition | _] -> :intent
      [:process, :action | _] -> :command
      [:process, :event | _] -> :world_update
      [:entity, :conceptual | _] -> :memory
      _ -> :intent
    end
  end

  defp name_to_content(name) do
    name
    |> String.replace(~r/([A-Z])/, " \\1")
    |> String.trim()
  end

  defp parse_status("spawning"), do: :spawning
  defp parse_status("active"), do: :active
  defp parse_status("fading"), do: :fading
  defp parse_status("archived"), do: :archived
  defp parse_status(_), do: :spawning

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @doc "Transitions bit to active status"
  def activate(%__MODULE__{} = bit) do
    %{bit | status: :active}
  end

  @doc "Transitions bit to fading status"
  def fade(%__MODULE__{} = bit) do
    %{bit | status: :fading}
  end

  @doc "Transitions bit to archived status"
  def archive(%__MODULE__{} = bit) do
    %{bit | status: :archived}
  end

  @doc "Updates energy level"
  def set_energy(%__MODULE__{} = bit, energy) when energy >= 0 and energy <= 1 do
    %{bit | energy: energy}
  end

  @doc "Updates salience level"
  def set_salience(%__MODULE__{} = bit, salience) when salience >= 0 and salience <= 1 do
    %{bit | salience: salience}
  end

  @doc "Adds a link to another Thunderbit"
  def add_link(%__MODULE__{} = bit, link_id) do
    %{bit | links: [link_id | bit.links] |> Enum.uniq()}
  end

  @doc "Adds tags to the Thunderbit"
  def add_tags(%__MODULE__{} = bit, new_tags) when is_list(new_tags) do
    %{bit | tags: (bit.tags ++ new_tags) |> Enum.uniq()}
  end

  @doc "Updates position in UI space"
  def set_position(%__MODULE__{} = bit, %{x: x, y: y, z: z}) do
    %{bit | position: %{x: x, y: y, z: z}}
  end

  # ===========================================================================
  # Thundercell Association (HC-Δ-8)
  # ===========================================================================

  @doc """
  Associates a Thundercell with this Thunderbit.

  Thundercells are raw data substrate chunks; Thunderbits are semantic roles.
  This enables many-to-many relationships: one Thunderbit can tag multiple
  data chunks, and one data chunk can have multiple semantic interpretations.
  """
  def add_thundercell(%__MODULE__{} = bit, cell_id) when is_binary(cell_id) do
    current = bit.thundercell_ids || []
    %{bit | thundercell_ids: [cell_id | current] |> Enum.uniq()}
  end

  @doc "Associates multiple Thundercells with this Thunderbit"
  def add_thundercells(%__MODULE__{} = bit, cell_ids) when is_list(cell_ids) do
    current = bit.thundercell_ids || []
    %{bit | thundercell_ids: (current ++ cell_ids) |> Enum.uniq()}
  end

  @doc "Removes a Thundercell association from this Thunderbit"
  def remove_thundercell(%__MODULE__{} = bit, cell_id) when is_binary(cell_id) do
    current = bit.thundercell_ids || []
    %{bit | thundercell_ids: Enum.reject(current, &(&1 == cell_id))}
  end

  @doc "Returns the list of associated Thundercell IDs"
  def thundercell_ids(%__MODULE__{thundercell_ids: ids}), do: ids || []

  @doc "Checks if this Thunderbit is associated with a specific Thundercell"
  def has_thundercell?(%__MODULE__{} = bit, cell_id) when is_binary(cell_id) do
    cell_id in (bit.thundercell_ids || [])
  end

  # ===========================================================================
  # UI Helpers
  # ===========================================================================

  @doc """
  Returns UI rendering hints for this Thunderbit based on its ontology.
  """
  def ui_hints(%__MODULE__{} = bit) do
    primary = Enum.at(bit.ontology_path, 1, :proposition)

    case Ontology.ui_hints_for(primary) do
      {:ok, hints} ->
        Map.merge(hints, %{
          energy: bit.energy,
          salience: bit.salience,
          status: bit.status
        })

      _ ->
        %{shape: :bubble, base_color: :gray, energy: bit.energy, salience: bit.salience}
    end
  end

  @doc """
  Returns the primary color for this Thunderbit based on kind.
  """
  def color(%__MODULE__{kind: kind}) do
    color_for_kind(kind)
  end

  # Handle DTO maps (from UIContract.to_dto) - extract from geometry or category
  def color(%{geometry: %{base_color: base_color}}) when is_binary(base_color), do: base_color

  def color(%{category: category}) when is_binary(category) do
    color_for_category(category)
  end

  def color(%{category: category}) when is_atom(category) do
    color_for_category(to_string(category))
  end

  def color(_), do: "#6B7280"

  defp color_for_kind(kind) do
    case kind do
      :question -> "#F97316"
      :command -> "#22C55E"
      :goal -> "#EC4899"
      :assertion -> "#14B8A6"
      :intent -> "#8B5CF6"
      :memory -> "#6366F1"
      :world_update -> "#3B82F6"
      :error -> "#EF4444"
      :system -> "#6B7280"
    end
  end

  defp color_for_category(category) do
    case category do
      "sensory" -> "#3B82F6"
      "cognitive" -> "#8B5CF6"
      "executive" -> "#22C55E"
      "memory" -> "#6366F1"
      _ -> "#6B7280"
    end
  end

  @doc """
  Returns the shape for this Thunderbit based on kind.
  """
  def shape(%__MODULE__{kind: kind}) do
    shape_for_kind(kind)
  end

  # Handle DTO maps (from UIContract.to_dto) - extract from geometry or category
  def shape(%{geometry: %{shape: shape}}) when is_binary(shape) do
    String.to_existing_atom(shape)
  rescue
    _ -> :circle
  end

  def shape(%{geometry: %{shape: shape}}) when is_atom(shape), do: shape

  def shape(%{category: category}) when is_binary(category) do
    shape_for_category(category)
  end

  def shape(%{category: category}) when is_atom(category) do
    shape_for_category(to_string(category))
  end

  def shape(_), do: :circle

  defp shape_for_kind(kind) do
    case kind do
      :question -> :bubble
      :command -> :capsule
      :goal -> :star
      :assertion -> :bubble
      :intent -> :hex
      :memory -> :circle
      :world_update -> :diamond
      :error -> :triangle
      :system -> :square
    end
  end

  defp shape_for_category(category) do
    case category do
      "sensory" -> :circle
      "cognitive" -> :hex
      "executive" -> :capsule
      "memory" -> :diamond
      _ -> :circle
    end
  end

  # ===========================================================================
  # Serialization
  # ===========================================================================

  @doc "Converts Thunderbit to a map for JSON serialization"
  def to_map(%__MODULE__{} = bit) do
    %{
      id: bit.id,
      kind: bit.kind,
      source: bit.source,
      content: bit.content,
      ontology_path: Enum.map(bit.ontology_path, &Atom.to_string/1),
      tags: bit.tags,
      energy: bit.energy,
      salience: bit.salience,
      position: bit.position,
      links: bit.links,
      thundercell_ids: bit.thundercell_ids || [],
      maxims: bit.maxims,
      owner: bit.owner,
      status: bit.status,
      inserted_at: DateTime.to_iso8601(bit.inserted_at),
      canonical_name: canonical_name(bit),
      ui: %{
        color: color(bit),
        shape: shape(bit)
      }
    }
  end

  # Handle already-serialized DTO maps (from UIContract.to_dto)
  def to_map(%{id: _} = dto) when is_map(dto) do
    # Already a DTO - just ensure it's JSON-ready
    dto
  end

  @doc "Creates a Thunderbit from a map"
  def from_map(map) when is_map(map) do
    new(
      kind: parse_kind(map["kind"] || map[:kind]),
      source: parse_source(map["source"] || map[:source]),
      content: map["content"] || map[:content] || "",
      tags: map["tags"] || map[:tags] || [],
      energy: map["energy"] || map[:energy] || 0.5,
      salience: map["salience"] || map[:salience] || 0.5,
      owner: map["owner"] || map[:owner],
      thundercell_ids: map["thundercell_ids"] || map[:thundercell_ids] || [],
      metadata: map["metadata"] || map[:metadata] || %{}
    )
  end

  defp parse_kind(kind) when is_atom(kind), do: kind
  defp parse_kind(kind) when is_binary(kind), do: String.to_existing_atom(kind)
  defp parse_kind(_), do: :intent

  defp parse_source(source) when is_atom(source), do: source
  defp parse_source(source) when is_binary(source), do: String.to_existing_atom(source)
  defp parse_source(_), do: :system

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp generate_id do
    Thunderline.UUID.v7()
  end

  defp spawn_position do
    # Start near center with small random offset
    jitter = :rand.uniform() * 0.1
    angle = :rand.uniform() * 2 * :math.pi()

    %{
      x: 0.5 + jitter * :math.cos(angle),
      y: 0.5 + jitter * :math.sin(angle),
      z: 0.0
    }
  end
end
