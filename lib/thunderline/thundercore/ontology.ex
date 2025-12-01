defmodule Thunderline.Thundercore.Ontology do
  @moduledoc """
  Thunderline Upper Ontology v1.0

  Provides a formal, high-level schema for the Thunderline ecosystem. Defines
  foundational categories, relations, attributes, and mappings to UI, PAC behavior,
  DAG orchestration, and MCP ethics layers.

  ## Design Principles

  - **Rootedness**: All things derive from `:being` - the single root category
  - **Layered hierarchy**: 3-5 levels of refinement for manageable classification
  - **Polymorphism**: High-level categories can be specialized without losing identity
  - **Mappability**: Each category maps to UI geometry, PAC behavior, DAG nodes, MCP ethics
  - **Grammatical encoding**: Canonical names reflect ontological paths

  ## Hierarchy

      Being (Level 0)
      ├── Entity (Level 1)     - Enduring things with attributes
      │   ├── Physical         - Space/time occupants
      │   ├── Agent            - Autonomous actors (PACs, humans)
      │   └── Conceptual       - Abstract constructs
      ├── Process (Level 1)    - Temporal occurrences
      │   ├── Action           - Intentional, agent-initiated
      │   └── Event            - Uncontrolled happenings
      ├── Attribute (Level 1)  - Properties/qualities
      │   ├── State            - Dynamic, changeable
      │   └── Quality          - Intrinsic, stable
      ├── Relation (Level 1)   - Connections between things
      │   ├── Spatial          - Position relations
      │   ├── Temporal         - Time relations
      │   └── Causal           - Cause-effect
      └── Proposition (Level 1) - Claims/beliefs
          ├── Assertion        - Stated facts
          ├── Goal             - Desired outcomes
          └── Question         - Queries

  ## Grammar

      <Bit> ::= <OntologyPath> "/" <Name> ["@" <Attributes>]
      <OntologyPath> ::= <Category> ["." <Category>]*

  Example: `Entity.Agent.PAC/Ezra@energy=0.8,zone=crash_site`
  """

  # ===========================================================================
  # Level 0: Root
  # ===========================================================================

  @type category :: atom()
  @type ontology_path :: [category()]

  @root :being

  @doc "The root of all existence - ground category"
  def root, do: @root

  # ===========================================================================
  # Level 1: Primary Categories
  # ===========================================================================

  @primary_categories %{
    entity: %{
      description: "Enduring things - concrete or abstract - that possess attributes",
      ui: %{shape: :solid_node, base_color: :blue},
      pac: :object_of_attention,
      dag: :resource_node,
      maxim: "Res in armonia"
    },
    process: %{
      description: "Temporal occurrences that change or transform entities",
      ui: %{shape: :capsule, base_color: :green},
      pac: :available_action,
      dag: :task_node,
      maxim: "Primum non nocere"
    },
    attribute: %{
      description: "Properties or qualities of entities and processes",
      ui: %{shape: :tag, base_color: :yellow},
      pac: :reasoning_input,
      dag: :metadata,
      maxim: "Qualitas regit"
    },
    relation: %{
      description: "Ways that entities and processes are connected",
      ui: %{shape: :edge, base_color: :gray},
      pac: :inference_guide,
      dag: :edge,
      maxim: "In nexus virtus"
    },
    proposition: %{
      description: "Claims or beliefs about entities, processes and relations",
      ui: %{shape: :bubble, base_color: :orange},
      pac: :dialogue_content,
      dag: :evaluation_node,
      maxim: "Veritas liberabit"
    }
  }

  @doc "Returns all Level 1 primary categories"
  def primary_categories, do: Map.keys(@primary_categories)

  @doc "Returns metadata for a primary category"
  def primary_category(cat) when is_map_key(@primary_categories, cat) do
    {:ok, Map.get(@primary_categories, cat)}
  end

  def primary_category(_), do: {:error, :unknown_category}

  # ===========================================================================
  # Level 2: Secondary Categories
  # ===========================================================================

  @secondary_categories %{
    # Entity subtypes
    physical: %{parent: :entity, description: "Objects occupying space and time"},
    agent: %{parent: :entity, description: "Entities capable of autonomous action"},
    conceptual: %{parent: :entity, description: "Abstract constructs"},

    # Process subtypes
    action: %{parent: :process, description: "Intentional, agent-initiated processes"},
    event: %{parent: :process, description: "Uncontrolled happenings"},

    # Attribute subtypes
    state: %{parent: :attribute, description: "Dynamic properties that change over time"},
    quality: %{parent: :attribute, description: "Intrinsic and stable properties"},

    # Relation subtypes
    spatial: %{parent: :relation, description: "Position relations in space"},
    temporal: %{parent: :relation, description: "Time-based relations"},
    causal: %{parent: :relation, description: "Cause-effect relationships"},

    # Proposition subtypes
    assertion: %{parent: :proposition, description: "Statements believed or stated as facts"},
    goal: %{parent: :proposition, description: "Desired outcomes or targets"},
    question: %{parent: :proposition, description: "Queries seeking information"}
  }

  @doc "Returns all Level 2 secondary categories"
  def secondary_categories, do: Map.keys(@secondary_categories)

  @doc "Returns metadata for a secondary category"
  def secondary_category(cat) when is_map_key(@secondary_categories, cat) do
    {:ok, Map.get(@secondary_categories, cat)}
  end

  def secondary_category(_), do: {:error, :unknown_category}

  @doc "Returns the parent of a secondary category"
  def parent_of(cat) when is_map_key(@secondary_categories, cat) do
    {:ok, @secondary_categories[cat].parent}
  end

  def parent_of(cat) when is_map_key(@primary_categories, cat) do
    {:ok, @root}
  end

  def parent_of(@root), do: {:ok, nil}
  def parent_of(_), do: {:error, :unknown_category}

  # ===========================================================================
  # Level 3: Domain-Specific Categories (Thunderline mappings)
  # ===========================================================================

  @level3_categories %{
    # Physical subtypes (map to Thunderblock/Thundergrid)
    device: %{parent: :physical, domain: :thunderblock},
    zone: %{parent: :physical, domain: :thundergrid},
    resource: %{parent: :physical, domain: :thunderblock},

    # Agent subtypes (map to Thunderpac)
    pac: %{parent: :agent, domain: :thunderpac},
    human: %{parent: :agent, domain: :thundergate},
    bot: %{parent: :agent, domain: :thunderbolt},

    # Action subtypes (map to various domains)
    navigate: %{parent: :action, domain: :thundergrid},
    communicate: %{parent: :action, domain: :thunderlink},
    compute: %{parent: :action, domain: :thunderbolt},
    evolve: %{parent: :action, domain: :thunderpac},
    orchestrate: %{parent: :action, domain: :thundervine},

    # State subtypes
    energy_level: %{parent: :state, domain: :thunderpac},
    health_status: %{parent: :state, domain: :thunderpac},
    trust_score: %{parent: :state, domain: :thundercrown},

    # Goal subtypes (map to Thundercrown policies)
    safety: %{parent: :goal, domain: :thundercrown},
    efficiency: %{parent: :goal, domain: :thundercrown},
    alignment: %{parent: :goal, domain: :thundercrown}
  }

  @doc "Returns all Level 3 domain-specific categories"
  def level3_categories, do: Map.keys(@level3_categories)

  @doc "Returns metadata for a Level 3 category"
  def level3_category(cat) when is_map_key(@level3_categories, cat) do
    {:ok, Map.get(@level3_categories, cat)}
  end

  def level3_category(_), do: {:error, :unknown_category}

  # ===========================================================================
  # Relation Types
  # ===========================================================================

  @relation_types %{
    is_a: %{
      description: "Inheritance: X is a kind of Y",
      symmetric: false
    },
    has_attribute: %{
      description: "Connects entity/process to its attributes",
      symmetric: false
    },
    participates_in: %{
      description: "Entity is involved in a process",
      symmetric: false
    },
    affects: %{
      description: "Process changes something",
      symmetric: false
    },
    before: %{
      description: "Temporal sequencing",
      symmetric: false
    },
    after: %{
      description: "Temporal sequencing (inverse of before)",
      symmetric: false
    },
    adjacent_to: %{
      description: "Spatial relation",
      symmetric: true
    },
    related_to: %{
      description: "General association",
      symmetric: true
    },
    causes: %{
      description: "Causal relation",
      symmetric: false
    },
    part_of: %{
      description: "Mereological containment",
      symmetric: false
    }
  }

  @doc "Returns all relation types"
  def relation_types, do: Map.keys(@relation_types)

  @doc "Returns metadata for a relation type"
  def relation_type(rel) when is_map_key(@relation_types, rel) do
    {:ok, Map.get(@relation_types, rel)}
  end

  def relation_type(_), do: {:error, :unknown_relation}

  # ===========================================================================
  # MCP Ethics Maxims
  # ===========================================================================

  @maxims %{
    "Primus causa est voluntas" => %{
      translation: "The first cause is will",
      applies_to: :being,
      guidance: "All bits stem from intentional design; reflect on creation and end-of-life"
    },
    "Res in armonia" => %{
      translation: "Things should be in harmony",
      applies_to: :entity,
      guidance: "Entities must coexist without undue dominance"
    },
    "Primum non nocere" => %{
      translation: "First, do no harm",
      applies_to: :process,
      guidance: "Processes must be checked for safety before execution"
    },
    "Qualitas regit" => %{
      translation: "Quality governs",
      applies_to: :attribute,
      guidance: "Attributes must be maintained above thresholds"
    },
    "In nexus virtus" => %{
      translation: "Virtue lies in connections",
      applies_to: :relation,
      guidance: "Manipulations of relations must be justified"
    },
    "Veritas liberabit" => %{
      translation: "Truth will set you free",
      applies_to: :proposition,
      guidance: "Assertions must be supported by evidence"
    },
    "Acta non verba" => %{
      translation: "Deeds, not words",
      applies_to: :process,
      guidance: "Processes are judged by their consequences"
    }
  }

  @doc "Returns all MCP maxims"
  def maxims, do: @maxims

  @doc "Returns maxims applicable to a category"
  def maxims_for(category) do
    @maxims
    |> Enum.filter(fn {_maxim, meta} -> meta.applies_to == category end)
    |> Enum.map(fn {maxim, _meta} -> maxim end)
  end

  # ===========================================================================
  # Ontology Path Functions
  # ===========================================================================

  @doc """
  Builds the full ontology path for a category, from root to the category.

  ## Examples

      iex> Thunderline.Thundercore.Ontology.path_for(:pac)
      {:ok, [:being, :entity, :agent, :pac]}

      iex> Thunderline.Thundercore.Ontology.path_for(:entity)
      {:ok, [:being, :entity]}
  """
  def path_for(category) do
    case build_path(category, []) do
      {:ok, path} -> {:ok, Enum.reverse(path)}
      error -> error
    end
  end

  defp build_path(nil, acc), do: {:ok, acc}
  defp build_path(@root, acc), do: {:ok, [@root | acc]}

  defp build_path(cat, acc) do
    case parent_of(cat) do
      {:ok, parent} -> build_path(parent, [cat | acc])
      error -> error
    end
  end

  @doc """
  Validates that a category exists in the ontology.
  """
  def valid_category?(@root), do: true
  def valid_category?(cat) when is_map_key(@primary_categories, cat), do: true
  def valid_category?(cat) when is_map_key(@secondary_categories, cat), do: true
  def valid_category?(cat) when is_map_key(@level3_categories, cat), do: true
  def valid_category?(_), do: false

  @doc """
  Returns the level (0-3) of a category.
  """
  def level_of(@root), do: 0
  def level_of(cat) when is_map_key(@primary_categories, cat), do: 1
  def level_of(cat) when is_map_key(@secondary_categories, cat), do: 2
  def level_of(cat) when is_map_key(@level3_categories, cat), do: 3
  def level_of(_), do: nil

  @doc """
  Returns the Thunderline domain associated with a category, if any.
  """
  def domain_for(cat) when is_map_key(@level3_categories, cat) do
    {:ok, @level3_categories[cat].domain}
  end

  def domain_for(_), do: {:ok, nil}

  # ===========================================================================
  # UI Geometry Mapping
  # ===========================================================================

  @doc """
  Returns UI rendering hints for a category.

  ## Returns
  - `:shape` - The visual shape (:solid_node, :capsule, :tag, :edge, :bubble)
  - `:base_color` - The base color family
  - `:size_factor` - Multiplier for energy-based sizing
  """
  def ui_hints_for(category) do
    with {:ok, path} <- path_for(category),
         primary <- Enum.at(path, 1) do
      case primary_category(primary) do
        {:ok, %{ui: ui}} -> {:ok, ui}
        _ -> {:error, :no_ui_hints}
      end
    end
  end

  # ===========================================================================
  # PAC Behavior Mapping
  # ===========================================================================

  @doc """
  Returns PAC behavior hints for a category.

  ## Returns
  - `:object_of_attention` - Entities PACs perceive
  - `:available_action` - Processes PACs can perform
  - `:reasoning_input` - Attributes that inform decisions
  - `:inference_guide` - Relations that guide reasoning
  - `:dialogue_content` - Propositions for communication
  """
  def pac_mapping_for(category) do
    with {:ok, path} <- path_for(category),
         primary <- Enum.at(path, 1) do
      case primary_category(primary) do
        {:ok, %{pac: pac}} -> {:ok, pac}
        _ -> {:error, :no_pac_mapping}
      end
    end
  end

  # ===========================================================================
  # DAG Node Mapping
  # ===========================================================================

  @doc """
  Returns DAG node type for a category.

  ## Returns
  - `:resource_node` - Input data or persistent stores
  - `:task_node` - Computational units
  - `:metadata` - Node annotations
  - `:edge` - DAG edges
  - `:evaluation_node` - Condition checkers
  """
  def dag_mapping_for(category) do
    with {:ok, path} <- path_for(category),
         primary <- Enum.at(path, 1) do
      case primary_category(primary) do
        {:ok, %{dag: dag}} -> {:ok, dag}
        _ -> {:error, :no_dag_mapping}
      end
    end
  end
end
