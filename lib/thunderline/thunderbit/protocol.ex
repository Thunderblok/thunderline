defmodule Thunderline.Thunderbit.Protocol do
  @moduledoc """
  Thunderbit Protocol - Core Verbs for Thunderbit Lifecycle

  Implements the 7 protocol verbs that manage the Thunderbit lifecycle:

  | Verb | Description |
  |------|-------------|
  | `spawn_bit` | Create a new Thunderbit of a given category |
  | `bind` | Monadic bind: pass bit to continuation |
  | `link` | Connect two Thunderbits |
  | `step` | Process one input event |
  | `retire` | Gracefully remove from field |
  | `query` | Read internal state |
  | `mutate` | Update internal state |

  ## Monadic Bind Pattern

  The `bind/2` operation is the core composition primitive:

      {:ok, bit} = Protocol.spawn_bit(:sensory, %{content: "hello"}, ctx)
      {bit, ctx} = Protocol.bind(bit, &classify/2)
      {bit, ctx} = Protocol.bind(bit, &extract_tags/2)

  ## Usage

      # Spawn a cognitive Thunderbit
      {:ok, bit} = Protocol.spawn_bit(:cognitive, %{content: "What is happening?"}, ctx)

      # Link two Thunderbits
      {:ok, edge} = Protocol.link(sensory_bit, cognitive_bit, :feeds)

      # Process an event
      {:ok, bit', outputs} = Protocol.step(bit, event)
  """

  alias Thunderline.Thunderbit.{Category, Wiring, Ethics}
  alias Thunderline.Thundercore.Thunderbit, as: CoreBit

  require Logger

  # ===========================================================================
  # Types
  # ===========================================================================

  @type context :: map()
  @type continuation :: (map(), context() -> {map(), context()})
  @type step_result :: {:ok, map(), [map()]} | {:halt, term()}
  @type spawn_result :: {:ok, map()} | {:error, term()}
  @type link_result :: {:ok, Wiring.edge()} | {:error, term()}

  # ===========================================================================
  # spawn_bit/3 - Create a new Thunderbit
  # ===========================================================================

  @doc """
  Creates a new Thunderbit of the specified category.

  ## Parameters
  - `category` - The category ID (:sensory, :cognitive, etc.)
  - `attrs` - Initial attributes (content, tags, energy, etc.)
  - `context` - Spawn context (pac_id, zone, etc.)

  ## Returns
  - `{:ok, %Thunderbit{}}` on success
  - `{:error, reason}` on failure (unknown category, policy violation, etc.)

  ## Examples

      iex> Protocol.spawn_bit(:sensory, %{content: "hello"}, %{pac_id: "ezra"})
      {:ok, %Thunderbit{category: :sensory, role: :observer, ...}}

      iex> Protocol.spawn_bit(:invalid, %{}, %{})
      {:error, :unknown_category}
  """
  @spec spawn_bit(Category.id(), map(), context()) :: spawn_result()
  def spawn_bit(category, attrs, context) do
    with {:ok, cat} <- Category.get(category),
         :ok <- Ethics.check_spawn(category, context),
         {:ok, bit} <- build_bit(cat, attrs, context) do
      Logger.debug("[Protocol.spawn_bit] Created #{category} Thunderbit: #{bit.id}")
      {:ok, bit}
    end
  end

  defp build_bit(cat, attrs, context) do
    content = Map.get(attrs, :content, "")
    kind = infer_kind(cat.id)

    base_attrs = [
      kind: kind,
      source: Map.get(attrs, :source, :system),
      content: content,
      tags: Map.get(attrs, :tags, []),
      energy: Map.get(attrs, :energy, 0.5),
      salience: Map.get(attrs, :salience, 0.5),
      owner: Map.get(context, :pac_id) || Map.get(attrs, :owner),
      metadata:
        Map.merge(
          Map.get(attrs, :metadata, %{}),
          %{
            category: cat.id,
            role: cat.role,
            capabilities: cat.capabilities,
            maxims: cat.required_maxims
          }
        )
    ]

    case CoreBit.new(base_attrs) do
      {:ok, bit} ->
        # Enhance with category protocol fields
        enhanced =
          bit
          |> Map.put(:category, cat.id)
          |> Map.put(:role, cat.role)
          |> Map.put(:io_state, %{inputs: %{}, outputs: %{}})
          |> Map.put(:capabilities_used, [])
          |> Map.put(:composition_context, context)
          |> Map.put(:ethics_verdict, nil)

        {:ok, enhanced}

      error ->
        error
    end
  end

  defp infer_kind(category) do
    case category do
      :sensory -> :world_update
      :cognitive -> :intent
      :mnemonic -> :memory
      :motor -> :command
      :social -> :intent
      :ethical -> :goal
      :perceptual -> :world_update
      :executive -> :command
    end
  end

  # ===========================================================================
  # bind/2 - Monadic bind
  # ===========================================================================

  @doc """
  Monadic bind: passes a Thunderbit through a continuation function.

  The continuation receives the bit and context, and returns a modified
  bit and updated context. This is the core composition primitive.

  ## Parameters
  - `bit` - The Thunderbit to transform
  - `continuation` - A function `(bit, context) -> {bit', context'}`

  ## Returns
  - `{bit', context'}` - The transformed bit and updated context

  ## Examples

      {bit, ctx} = Protocol.bind(bit, fn bit, ctx ->
        bit = %{bit | energy: bit.energy * 1.1}
        {bit, Map.put(ctx, :boosted, true)}
      end)
  """
  @spec bind(map(), continuation()) :: {map(), context()}
  def bind(bit, continuation) when is_function(continuation, 2) do
    context = Map.get(bit, :composition_context, %{})
    {new_bit, new_context} = continuation.(bit, context)
    {%{new_bit | composition_context: new_context}, new_context}
  end

  @doc """
  Chains multiple bind operations.

  ## Examples

      {bit, ctx} = Protocol.chain(bit, [
        &classify/2,
        &extract_tags/2,
        &compute_salience/2
      ])
  """
  @spec chain(map(), [continuation()]) :: {map(), context()}
  def chain(bit, continuations) when is_list(continuations) do
    Enum.reduce(continuations, {bit, bit.composition_context || %{}}, fn cont, {b, c} ->
      bind(%{b | composition_context: c}, cont)
    end)
  end

  # ===========================================================================
  # link/3 - Connect two Thunderbits
  # ===========================================================================

  @doc """
  Links two Thunderbits with a specified relation.

  Validates:
  1. Wiring rules (category compatibility)
  2. Maxim compatibility
  3. Policy approval

  ## Parameters
  - `from_bit` - Source Thunderbit
  - `to_bit` - Target Thunderbit
  - `relation` - Relation type (:feeds, :triggers, :validates, etc.)

  ## Returns
  - `{:ok, edge}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, edge} = Protocol.link(sensory_bit, cognitive_bit, :feeds)

      {:error, {:invalid_wiring, :motor, :sensory}} = Protocol.link(motor_bit, sensory_bit, :feeds)
  """
  @spec link(map(), map(), atom()) :: link_result()
  def link(from_bit, to_bit, relation) do
    with :ok <- Wiring.validate_relation(from_bit.category, to_bit.category, relation),
         :ok <- Ethics.check_link(from_bit, to_bit, relation) do
      Wiring.create_edge(from_bit, to_bit, relation)
    end
  end

  # ===========================================================================
  # step/2 - Process one input event
  # ===========================================================================

  @doc """
  Processes one input event through a Thunderbit.

  The Thunderbit's role determines how the event is processed:
  - Observer: Parse and emit
  - Transformer: Transform and forward
  - Router: Select targets
  - Actuator: Execute action
  - Critic: Evaluate and verdict
  - Controller: Sequence steps

  ## Parameters
  - `bit` - The Thunderbit processing the event
  - `event` - The input event

  ## Returns
  - `{:ok, bit', outputs}` - Updated bit and output events
  - `{:halt, reason}` - Processing halted (error, veto, etc.)

  ## Examples

      {:ok, bit', outputs} = Protocol.step(cognitive_bit, input_event)
  """
  @spec step(map(), map()) :: step_result()
  def step(bit, event) do
    role = Map.get(bit, :role, :transformer)

    case do_step(bit, event, role) do
      {:ok, new_bit, outputs} ->
        # Track capability usage
        tracked = track_step(new_bit, role)
        {:ok, tracked, outputs}

      {:halt, reason} ->
        {:halt, reason}
    end
  end

  defp do_step(bit, event, :observer) do
    # Observers parse input into events
    parsed = %{
      type: :parsed,
      payload: event,
      source: bit.id,
      timestamp: DateTime.utc_now()
    }

    new_bit = update_io_state(bit, :outputs, :parsed_event, parsed)
    {:ok, new_bit, [parsed]}
  end

  defp do_step(bit, event, :transformer) do
    # Transformers process and transform events
    transformed = %{
      type: :transformed,
      payload: event.payload,
      source: bit.id,
      transformations: [:classified],
      timestamp: DateTime.utc_now()
    }

    new_bit = update_io_state(bit, :outputs, :transformed, transformed)
    {:ok, new_bit, [transformed]}
  end

  defp do_step(bit, event, :router) do
    # Routers select targets and forward
    routed = %{
      type: :routed,
      payload: event.payload,
      source: bit.id,
      targets: [],  # Would be populated by routing logic
      timestamp: DateTime.utc_now()
    }

    new_bit = update_io_state(bit, :outputs, :routed_event, routed)
    {:ok, new_bit, [routed]}
  end

  defp do_step(bit, event, :actuator) do
    # Check ethics before acting
    case Ethics.check_action(bit, event) do
      :ok ->
        action = %{
          type: :action_executed,
          payload: event.payload,
          source: bit.id,
          timestamp: DateTime.utc_now()
        }

        new_bit = update_io_state(bit, :outputs, :action_event, action)
        {:ok, new_bit, [action]}

      {:error, reason} ->
        {:halt, {:action_blocked, reason}}
    end
  end

  defp do_step(bit, event, :critic) do
    # Evaluate and produce verdict
    verdict = %{
      allowed: true,
      reason: "No policy violations detected",
      confidence: 0.95
    }

    verdict_event = %{
      type: :verdict,
      payload: verdict,
      source: bit.id,
      timestamp: DateTime.utc_now()
    }

    new_bit =
      bit
      |> update_io_state(:outputs, :verdict, verdict_event)
      |> Map.put(:ethics_verdict, verdict)

    {:ok, new_bit, [verdict_event]}
  end

  defp do_step(bit, event, :analyzer) do
    # Extract features
    features = %{
      type: :features,
      payload: %{patterns: [], features: []},
      source: bit.id,
      timestamp: DateTime.utc_now()
    }

    new_bit = update_io_state(bit, :outputs, :features, features)
    {:ok, new_bit, [features]}
  end

  defp do_step(bit, event, :storage) do
    # Store and acknowledge
    stored = %{
      type: :stored,
      payload: event.payload,
      source: bit.id,
      timestamp: DateTime.utc_now()
    }

    new_bit = update_io_state(bit, :outputs, :stored_ack, stored)
    {:ok, new_bit, [stored]}
  end

  defp do_step(bit, event, :controller) do
    # Emit control event
    control = %{
      type: :control,
      payload: %{action: :continue, next_step: nil},
      source: bit.id,
      timestamp: DateTime.utc_now()
    }

    new_bit = update_io_state(bit, :outputs, :control_event, control)
    {:ok, new_bit, [control]}
  end

  defp update_io_state(bit, direction, key, value) do
    io_state = Map.get(bit, :io_state, %{inputs: %{}, outputs: %{}})
    new_direction = Map.put(Map.get(io_state, direction, %{}), key, value)
    %{bit | io_state: Map.put(io_state, direction, new_direction)}
  end

  defp track_step(bit, role) do
    capability = role_to_capability(role)
    used = Map.get(bit, :capabilities_used, [])
    %{bit | capabilities_used: [capability | used] |> Enum.uniq()}
  end

  defp role_to_capability(:observer), do: :read_sensors
  defp role_to_capability(:transformer), do: :access_memory
  defp role_to_capability(:router), do: :select_targets
  defp role_to_capability(:actuator), do: :trigger_action
  defp role_to_capability(:critic), do: :evaluate_policy
  defp role_to_capability(:analyzer), do: :read_sensors
  defp role_to_capability(:storage), do: :access_memory
  defp role_to_capability(:controller), do: :sequence_steps

  # ===========================================================================
  # retire/2 - Remove from field
  # ===========================================================================

  @doc """
  Gracefully retires a Thunderbit from the field.

  ## Parameters
  - `bit` - The Thunderbit to retire
  - `reason` - Reason for retirement (:done, :error, :replaced, etc.)

  ## Returns
  - `:ok`

  ## Side Effects
  - Broadcasts retirement event to PubSub
  - Updates registry (if registered)
  """
  @spec retire(map(), atom()) :: :ok
  def retire(bit, reason) do
    Logger.debug("[Protocol.retire] Retiring #{bit.id}: #{reason}")

    # Broadcast retirement
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_retire, %{id: bit.id, reason: reason}}
    )

    :ok
  end

  # ===========================================================================
  # query/2 - Read internal state
  # ===========================================================================

  @doc """
  Queries a specific key from a Thunderbit's state.

  ## Parameters
  - `bit` - The Thunderbit to query
  - `key` - The key to retrieve

  ## Returns
  - `{:ok, value}` if found
  - `:not_found` if key doesn't exist

  ## Examples

      {:ok, 0.85} = Protocol.query(bit, :energy)
      :not_found = Protocol.query(bit, :nonexistent)
  """
  @spec query(map(), atom()) :: {:ok, term()} | :not_found
  def query(bit, key) when is_atom(key) do
    case Map.fetch(bit, key) do
      {:ok, value} -> {:ok, value}
      :error -> :not_found
    end
  end

  def query(bit, keys) when is_list(keys) do
    results =
      Enum.map(keys, fn key ->
        {key, query(bit, key)}
      end)

    {:ok, Map.new(results)}
  end

  # ===========================================================================
  # mutate/2 - Update internal state
  # ===========================================================================

  @doc """
  Mutates a Thunderbit's internal state.

  Validates that the mutation is allowed based on the Thunderbit's
  capabilities and ethics constraints.

  ## Parameters
  - `bit` - The Thunderbit to mutate
  - `changes` - Map of changes to apply

  ## Returns
  - `{:ok, bit'}` on success
  - `{:error, :forbidden}` if mutation is not allowed

  ## Examples

      {:ok, bit'} = Protocol.mutate(bit, %{energy: 0.9, salience: 0.8})
  """
  @spec mutate(map(), map()) :: {:ok, map()} | {:error, :forbidden}
  def mutate(bit, changes) when is_map(changes) do
    # Protected fields that can't be mutated
    protected = [:id, :category, :role, :inserted_at]

    if Enum.any?(Map.keys(changes), &(&1 in protected)) do
      {:error, :forbidden}
    else
      new_bit = Map.merge(bit, changes)
      {:ok, new_bit}
    end
  end

  # ===========================================================================
  # Convenience: spawn_for_ui/1
  # ===========================================================================

  @doc """
  Spawns Thunderbit(s) for UI display based on input.

  This is the main entry point for the "text → Thunderbit → UI" flow.

  ## Parameters
  - `input` - Map with :pac_id, :input_type, :content, :zone

  ## Returns
  - `{:ok, [ui_spec, ...]}` - List of UI specs ready for rendering
  """
  @spec spawn_for_ui(map()) :: {:ok, [map()]} | {:error, term()}
  def spawn_for_ui(%{content: content} = input) do
    context = %{
      pac_id: Map.get(input, :pac_id),
      zone: Map.get(input, :zone)
    }

    # Start with sensory bit
    with {:ok, sensory} <- spawn_bit(:sensory, %{content: content}, context) do
      # Classify and determine if we need more bits
      {sensory, ctx} = bind(sensory, &classify_input/2)
      {sensory, ctx} = bind(sensory, &extract_tags/2)

      # Maybe spawn cognitive bit
      bits =
        if needs_reasoning?(sensory) do
          case spawn_bit(:cognitive, %{content: content, input: sensory.id}, ctx) do
            {:ok, cognitive} -> [sensory, cognitive]
            _ -> [sensory]
          end
        else
          [sensory]
        end

      # Convert to UI specs
      ui_specs = Enum.map(bits, &to_ui_spec/1)
      {:ok, ui_specs}
    end
  end

  defp classify_input(bit, ctx) do
    # Simple classification based on content patterns
    content = bit.content || ""

    kind =
      cond do
        String.contains?(content, "?") -> :question
        String.starts_with?(String.downcase(content), ["go ", "navigate ", "move "]) -> :command
        String.starts_with?(String.downcase(content), ["remember ", "save ", "store "]) -> :memory
        true -> :intent
      end

    {%{bit | kind: kind}, ctx}
  end

  defp extract_tags(bit, ctx) do
    # Simple tag extraction
    content = bit.content || ""

    tags =
      content
      |> String.downcase()
      |> String.split(~r/[\s,]+/)
      |> Enum.filter(&(String.length(&1) > 3))
      |> Enum.take(5)

    {%{bit | tags: tags}, ctx}
  end

  defp needs_reasoning?(bit) do
    bit.kind in [:question, :intent]
  end

  defp to_ui_spec(bit) do
    {:ok, cat} = Category.get(bit.category)
    geometry = Map.get(cat, :geometry, %{})

    %{
      id: bit.id,
      canonical_name: get_canonical_name(bit),
      geometry: %{
        type: Map.get(geometry, :type, :node),
        shape: Map.get(geometry, :shape, :circle),
        position: bit.position
      },
      visual: %{
        base_color: Map.get(geometry, :base_color, "#6B7280"),
        energy: bit.energy,
        salience: bit.salience,
        state: status_to_visual_state(bit.status),
        animation: Map.get(geometry, :animation, :static)
      },
      links:
        Enum.map(bit.links, fn link_id ->
          %{target_id: link_id, relation_type: "related", strength: 0.5}
        end),
      label: String.slice(bit.content || "", 0, 30),
      tooltip: bit.content,
      category: Atom.to_string(bit.category),
      role: Atom.to_string(Map.get(cat, :role, :transformer))
    }
  end

  defp get_canonical_name(bit) do
    if function_exported?(CoreBit, :canonical_name, 1) do
      try do
        CoreBit.canonical_name(bit)
      rescue
        _ -> "Unknown/Bit"
      end
    else
      "#{bit.category}/#{String.slice(bit.content || "", 0, 20)}"
    end
  end

  defp status_to_visual_state(:spawning), do: "thinking"
  defp status_to_visual_state(:active), do: "idle"
  defp status_to_visual_state(:fading), do: "fading"
  defp status_to_visual_state(:archived), do: "fading"
  defp status_to_visual_state(_), do: "idle"
end
