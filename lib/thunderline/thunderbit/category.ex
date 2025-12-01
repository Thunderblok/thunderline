defmodule Thunderline.Thunderbit.Category do
  @moduledoc """
  Thunderbit Category Protocol - Category Definitions

  Defines the 8 core Thunderbit categories that map to the Upper Ontology.
  Each category specifies:
  - Role in the computational graph
  - I/O specifications
  - Capabilities and restrictions
  - Composition/wiring rules
  - Ethics constraints
  - UI geometry hints

  ## Categories

  | Category | Role | Ontology |
  |----------|------|----------|
  | Sensory | Observer | Entity.Physical |
  | Cognitive | Transformer | Proposition.* |
  | Mnemonic | Storage | Entity.Conceptual |
  | Motor | Actuator | Process.Action |
  | Social | Router | Relation.* |
  | Ethical | Critic | Proposition.Goal |
  | Perceptual | Analyzer | Attribute.State |
  | Executive | Controller | Process.Action |

  ## Usage

      iex> Category.get(:sensory)
      {:ok, %Category{role: :observer, ...}}

      iex> Category.wiring_valid?(:sensory, :cognitive)
      true

      iex> Category.wiring_valid?(:motor, :sensory)
      false
  """

  alias Thunderline.Thundercore.Ontology

  # ===========================================================================
  # Types
  # ===========================================================================

  @type id :: :sensory | :cognitive | :mnemonic | :motor | :social | :ethical | :perceptual | :executive

  @type role :: :observer | :transformer | :storage | :actuator | :router | :critic | :analyzer | :controller

  @type composition :: :serial | :parallel | :feedback | :broadcast

  @type io_type :: :event | :tensor | :message | :context | :signal

  @type capability ::
          :read_sensors
          | :write_events
          | :access_memory
          | :spawn_bits
          | :mutate_pac
          | :trigger_action
          | :evaluate_policy
          | :veto_action
          | :subscribe_topics
          | :select_targets
          | :sequence_steps

  @type geometry :: %{
          type: :node | :glyph | :voxel | :halo | :edge,
          shape: :circle | :hex | :capsule | :star | :diamond | :triangle | :square,
          base_color: String.t(),
          size_basis: :energy | :salience | :fixed,
          animation: :pulse | :drift | :static | :spin
        }

  @type io_spec :: %{
          name: atom(),
          type: io_type(),
          shape: term(),
          topic: String.t() | nil,
          required: boolean()
        }

  @type t :: %__MODULE__{
          id: id(),
          name: String.t(),
          ontology_path: [atom()],
          role: role(),
          inputs: [io_spec()],
          outputs: [io_spec()],
          capabilities: [capability()],
          forbidden: [capability()],
          can_link_to: [id()],
          can_receive_from: [id()],
          composition_mode: composition(),
          required_maxims: [String.t()],
          forbidden_maxims: [String.t()],
          geometry: geometry(),
          description: String.t(),
          examples: [String.t()]
        }

  defstruct [
    :id,
    :name,
    :ontology_path,
    :role,
    :inputs,
    :outputs,
    :capabilities,
    :forbidden,
    :can_link_to,
    :can_receive_from,
    :composition_mode,
    :required_maxims,
    :forbidden_maxims,
    :geometry,
    :description,
    :examples
  ]

  # ===========================================================================
  # Category Definitions
  # ===========================================================================

  # Store as raw maps, convert to structs on access
  @categories_data %{
    sensory: %{
      id: :sensory,
      name: "Sensory",
      ontology_path: [:being, :entity, :physical],
      role: :observer,
      inputs: [
        %{name: :raw_input, type: :signal, shape: :any, topic: nil, required: true}
      ],
      outputs: [
        %{name: :parsed_event, type: :event, shape: :any, topic: "thunderbits:sensory", required: true}
      ],
      capabilities: [:read_sensors, :subscribe_topics],
      forbidden: [:write_events, :trigger_action, :veto_action],
      can_link_to: [:cognitive, :mnemonic, :perceptual, :social],
      can_receive_from: [],
      composition_mode: :serial,
      required_maxims: ["Res in armonia"],
      forbidden_maxims: [],
      geometry: %{
        type: :node,
        shape: :circle,
        base_color: "#3B82F6",
        size_basis: :energy,
        animation: :pulse
      },
      description: "Ingests external signals (text, voice, sensors) and converts to events",
      examples: ["Text input parser", "Voice transcriber", "Sensor reader"]
    },
    cognitive: %{
      id: :cognitive,
      name: "Cognitive",
      ontology_path: [:being, :proposition],
      role: :transformer,
      inputs: [
        %{name: :event, type: :event, shape: :any, topic: nil, required: true},
        %{name: :context, type: :context, shape: :map, topic: nil, required: false}
      ],
      outputs: [
        %{name: :transformed, type: :event, shape: :any, topic: "thunderbits:cognitive", required: true},
        %{name: :inference, type: :message, shape: :any, topic: nil, required: false}
      ],
      capabilities: [:access_memory, :spawn_bits],
      forbidden: [:trigger_action, :veto_action],
      can_link_to: [:motor, :social, :ethical, :mnemonic, :executive],
      can_receive_from: [:sensory, :perceptual, :mnemonic, :executive],
      composition_mode: :parallel,
      required_maxims: ["Veritas liberabit"],
      forbidden_maxims: [],
      geometry: %{
        type: :node,
        shape: :hex,
        base_color: "#8B5CF6",
        size_basis: :salience,
        animation: :spin
      },
      description: "Reasons, classifies, and infers from events and context",
      examples: ["Intent classifier", "Entity extractor", "Reasoning engine"]
    },
    mnemonic: %{
      id: :mnemonic,
      name: "Mnemonic",
      ontology_path: [:being, :entity, :conceptual],
      role: :storage,
      inputs: [
        %{name: :store_event, type: :event, shape: :any, topic: nil, required: false},
        %{name: :query, type: :message, shape: :any, topic: nil, required: false}
      ],
      outputs: [
        %{name: :retrieved, type: :context, shape: :any, topic: nil, required: true},
        %{name: :stored_ack, type: :event, shape: :any, topic: nil, required: false}
      ],
      capabilities: [:access_memory],
      forbidden: [:trigger_action, :write_events, :veto_action],
      can_link_to: [:cognitive, :perceptual, :social],
      can_receive_from: [:sensory, :cognitive, :motor],
      composition_mode: :parallel,
      required_maxims: ["Qualitas regit"],
      forbidden_maxims: [],
      geometry: %{
        type: :node,
        shape: :circle,
        base_color: "#6366F1",
        size_basis: :fixed,
        animation: :static
      },
      description: "Stores and retrieves context, memories, and state",
      examples: ["Working memory", "Long-term memory", "Context buffer"]
    },
    motor: %{
      id: :motor,
      name: "Motor",
      ontology_path: [:being, :process, :action],
      role: :actuator,
      inputs: [
        %{name: :action_request, type: :event, shape: :any, topic: nil, required: true},
        %{name: :verdict, type: :message, shape: :any, topic: nil, required: false}
      ],
      outputs: [
        %{name: :action_event, type: :event, shape: :any, topic: "thunderbits:actions", required: true},
        %{name: :side_effect, type: :signal, shape: :any, topic: nil, required: false}
      ],
      capabilities: [:write_events, :trigger_action],
      forbidden: [:read_sensors, :veto_action],
      can_link_to: [:mnemonic],
      can_receive_from: [:cognitive, :social, :ethical, :executive],
      composition_mode: :serial,
      required_maxims: ["Primum non nocere", "Acta non verba"],
      forbidden_maxims: ["Acta sine consilio"],
      geometry: %{
        type: :node,
        shape: :capsule,
        base_color: "#22C55E",
        size_basis: :energy,
        animation: :pulse
      },
      description: "Emits events and triggers actions in the world",
      examples: ["Event emitter", "API caller", "PAC action executor"]
    },
    social: %{
      id: :social,
      name: "Social",
      ontology_path: [:being, :relation],
      role: :router,
      inputs: [
        %{name: :event, type: :event, shape: :any, topic: nil, required: true},
        %{name: :routing_context, type: :context, shape: :map, topic: nil, required: false}
      ],
      outputs: [
        %{name: :routed_event, type: :event, shape: :any, topic: nil, required: true}
      ],
      capabilities: [:select_targets, :subscribe_topics],
      forbidden: [:trigger_action, :veto_action],
      can_link_to: [:motor, :cognitive, :mnemonic],
      can_receive_from: [:sensory, :cognitive, :perceptual],
      composition_mode: :broadcast,
      required_maxims: ["In nexus virtus"],
      forbidden_maxims: [],
      geometry: %{
        type: :edge,
        shape: :diamond,
        base_color: "#F97316",
        size_basis: :salience,
        animation: :drift
      },
      description: "Routes events between agents and manages connections",
      examples: ["Message router", "Agent selector", "Topic dispatcher"]
    },
    ethical: %{
      id: :ethical,
      name: "Ethical",
      ontology_path: [:being, :proposition, :goal],
      role: :critic,
      inputs: [
        %{name: :action_proposal, type: :event, shape: :any, topic: nil, required: true},
        %{name: :policy_context, type: :context, shape: :map, topic: nil, required: true}
      ],
      outputs: [
        %{name: :verdict, type: :message, shape: %{allowed: :boolean, reason: :string}, topic: nil, required: true}
      ],
      capabilities: [:evaluate_policy, :veto_action],
      forbidden: [:trigger_action, :write_events],
      can_link_to: [:motor, :social],
      can_receive_from: [:cognitive, :executive],
      composition_mode: :serial,
      required_maxims: ["Veritas liberabit", "In nexus virtus", "Primum non nocere"],
      forbidden_maxims: [],
      geometry: %{
        type: :halo,
        shape: :star,
        base_color: "#EC4899",
        size_basis: :salience,
        animation: :spin
      },
      description: "Evaluates constraints and policies, can veto actions",
      examples: ["Policy checker", "Safety validator", "Ethics evaluator"]
    },
    perceptual: %{
      id: :perceptual,
      name: "Perceptual",
      ontology_path: [:being, :attribute, :state],
      role: :analyzer,
      inputs: [
        %{name: :raw_signal, type: :signal, shape: :any, topic: nil, required: true}
      ],
      outputs: [
        %{name: :features, type: :tensor, shape: {:dynamic}, topic: nil, required: true},
        %{name: :patterns, type: :event, shape: :any, topic: nil, required: false}
      ],
      capabilities: [:read_sensors, :access_memory],
      forbidden: [:trigger_action, :write_events, :veto_action],
      can_link_to: [:cognitive, :mnemonic, :social],
      can_receive_from: [:sensory],
      composition_mode: :parallel,
      required_maxims: ["Qualitas regit"],
      forbidden_maxims: [],
      geometry: %{
        type: :glyph,
        shape: :triangle,
        base_color: "#FBBF24",
        size_basis: :energy,
        animation: :pulse
      },
      description: "Extracts features and patterns from raw signals",
      examples: ["Feature extractor", "Pattern detector", "Attention filter"]
    },
    executive: %{
      id: :executive,
      name: "Executive",
      ontology_path: [:being, :process, :action],
      role: :controller,
      inputs: [
        %{name: :trigger, type: :event, shape: :any, topic: nil, required: true},
        %{name: :plan, type: :context, shape: :list, topic: nil, required: false}
      ],
      outputs: [
        %{name: :control_event, type: :event, shape: :any, topic: nil, required: true},
        %{name: :spawn_request, type: :message, shape: :any, topic: nil, required: false}
      ],
      capabilities: [:spawn_bits, :sequence_steps, :select_targets],
      forbidden: [:trigger_action],
      can_link_to: [:sensory, :cognitive, :mnemonic, :motor, :social, :ethical, :perceptual],
      can_receive_from: [:cognitive, :ethical],
      composition_mode: :serial,
      required_maxims: ["Primus causa est voluntas"],
      forbidden_maxims: [],
      geometry: %{
        type: :node,
        shape: :square,
        base_color: "#14B8A6",
        size_basis: :salience,
        animation: :spin
      },
      description: "Orchestrates sequences of Thunderbit operations",
      examples: ["Workflow controller", "Plan executor", "Step sequencer"]
    }
  }

  # Convert map to struct at runtime
  defp to_struct(data) when is_map(data) do
    struct(__MODULE__, data)
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Returns all category IDs.
  """
  @spec all_ids() :: [id()]
  def all_ids, do: Map.keys(@categories_data)

  @doc """
  Returns all categories.
  """
  @spec all() :: [t()]
  def all, do: Enum.map(Map.values(@categories_data), &to_struct/1)

  @doc """
  Gets a category by ID.

  ## Examples

      iex> Category.get(:sensory)
      {:ok, %Category{id: :sensory, role: :observer, ...}}

      iex> Category.get(:invalid)
      {:error, :unknown_category}
  """
  @spec get(id()) :: {:ok, t()} | {:error, :unknown_category}
  def get(id) when is_map_key(@categories_data, id) do
    {:ok, to_struct(Map.get(@categories_data, id))}
  end

  def get(_), do: {:error, :unknown_category}

  @doc """
  Gets a category by ID, raising on error.
  """
  @spec get!(id()) :: t()
  def get!(id) do
    case get(id) do
      {:ok, cat} -> cat
      {:error, _} -> raise ArgumentError, "Unknown category: #{inspect(id)}"
    end
  end

  @doc """
  Lists categories by role.

  ## Examples

      iex> Category.list_by_role(:observer)
      [%Category{id: :sensory, ...}]
  """
  @spec list_by_role(role()) :: [t()]
  def list_by_role(role) do
    @categories_data
    |> Map.values()
    |> Enum.filter(&(&1.role == role))
    |> Enum.map(&to_struct/1)
  end

  @doc """
  Lists categories by capability.
  """
  @spec list_by_capability(capability()) :: [t()]
  def list_by_capability(capability) do
    @categories_data
    |> Map.values()
    |> Enum.filter(&(capability in &1.capabilities))
    |> Enum.map(&to_struct/1)
  end

  # ===========================================================================
  # Wiring Rules
  # ===========================================================================

  @doc """
  Checks if category A can link to category B.

  ## Examples

      iex> Category.wiring_valid?(:sensory, :cognitive)
      true

      iex> Category.wiring_valid?(:motor, :sensory)
      false
  """
  @spec wiring_valid?(id(), id()) :: boolean()
  def wiring_valid?(from_id, to_id) do
    case get(from_id) do
      {:ok, cat} -> to_id in cat.can_link_to
      _ -> false
    end
  end

  @doc """
  Returns all valid downstream categories for a given category.
  """
  @spec valid_targets(id()) :: [id()]
  def valid_targets(id) do
    case get(id) do
      {:ok, cat} -> cat.can_link_to
      _ -> []
    end
  end

  @doc """
  Returns all valid upstream categories for a given category.
  """
  @spec valid_sources(id()) :: [id()]
  def valid_sources(id) do
    case get(id) do
      {:ok, cat} -> cat.can_receive_from
      _ -> []
    end
  end

  @doc """
  Checks if a capability is allowed for a category.
  """
  @spec capability_allowed?(id(), capability()) :: boolean()
  def capability_allowed?(id, capability) do
    case get(id) do
      {:ok, cat} -> capability in cat.capabilities and capability not in cat.forbidden
      _ -> false
    end
  end

  @doc """
  Checks if a capability is forbidden for a category.
  """
  @spec capability_forbidden?(id(), capability()) :: boolean()
  def capability_forbidden?(id, capability) do
    case get(id) do
      {:ok, cat} -> capability in cat.forbidden
      _ -> true
    end
  end

  # ===========================================================================
  # Ethics
  # ===========================================================================

  @doc """
  Returns the required maxims for a category.
  """
  @spec required_maxims(id()) :: [String.t()]
  def required_maxims(id) do
    case get(id) do
      {:ok, cat} -> cat.required_maxims
      _ -> []
    end
  end

  @doc """
  Returns the forbidden maxims for a category.
  """
  @spec forbidden_maxims(id()) :: [String.t()]
  def forbidden_maxims(id) do
    case get(id) do
      {:ok, cat} -> cat.forbidden_maxims
      _ -> []
    end
  end

  @doc """
  Checks if two categories can be composed based on their maxims.
  Returns an error if the combination would violate ethics.
  """
  @spec check_maxim_compatibility(id(), id()) :: :ok | {:error, {:maxim_conflict, String.t()}}
  def check_maxim_compatibility(cat_a, cat_b) do
    with {:ok, a} <- get(cat_a),
         {:ok, b} <- get(cat_b) do
      # Check if A's required maxims conflict with B's forbidden
      conflicts =
        MapSet.intersection(
          MapSet.new(a.required_maxims),
          MapSet.new(b.forbidden_maxims)
        )

      if MapSet.size(conflicts) > 0 do
        {:error, {:maxim_conflict, Enum.at(MapSet.to_list(conflicts), 0)}}
      else
        :ok
      end
    else
      _ -> {:error, :unknown_category}
    end
  end

  # ===========================================================================
  # UI Geometry
  # ===========================================================================

  @doc """
  Returns the UI geometry spec for a category.
  """
  @spec geometry(id()) :: {:ok, geometry()} | {:error, :unknown_category}
  def geometry(id) do
    case get(id) do
      {:ok, cat} -> {:ok, cat.geometry}
      error -> error
    end
  end

  # ===========================================================================
  # Ontology Integration
  # ===========================================================================

  @doc """
  Returns the ontology path for a category.
  """
  @spec ontology_path(id()) :: {:ok, [atom()]} | {:error, :unknown_category}
  def ontology_path(id) do
    case get(id) do
      {:ok, cat} -> {:ok, cat.ontology_path}
      error -> error
    end
  end

  @doc """
  Returns the primary ontology category (Level 1) for a Thunderbit category.
  """
  @spec primary_ontology(id()) :: {:ok, atom()} | {:error, :unknown_category}
  def primary_ontology(id) do
    case ontology_path(id) do
      {:ok, path} -> {:ok, Enum.at(path, 1)}
      error -> error
    end
  end

  @doc """
  Returns the Thunderline domain for a category based on its ontology path.
  """
  @spec domain(id()) :: {:ok, atom() | nil} | {:error, :unknown_category}
  def domain(id) do
    case ontology_path(id) do
      {:ok, path} ->
        leaf = List.last(path)
        Ontology.domain_for(leaf)

      error ->
        error
    end
  end
end
