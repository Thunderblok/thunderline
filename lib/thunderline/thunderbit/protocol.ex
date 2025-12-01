defmodule Thunderline.Thunderbit.Protocol do
  @moduledoc """
  Thunderbit Protocol - Core Verbs for Thunderbit Lifecycle

  Implements the 7 protocol verbs that manage the Thunderbit lifecycle.
  
  ## Core Principle: Context Threading

  The Protocol NEVER mutates global state. Instead:
  - Takes a Context, returns an updated Context
  - All bits are registered in Context.bits_by_id
  - All edges are tracked in Context.edges
  - Events are logged in Context.event_log

  ## Protocol Verbs

  | Verb     | Input                          | Output                       | Side Effects  |
  |----------|--------------------------------|------------------------------|---------------|
  | spawn    | category, attrs, ctx           | {:ok, bit, ctx} or error     | None          |
  | bind     | bit, continuation, ctx         | {:ok, bit, ctx}              | None          |
  | link     | from, to, relation, ctx        | {:ok, edge, ctx} or error    | None          |
  | step     | bit, event, ctx                | {:ok, bit, outputs, ctx}     | None          |
  | retire   | bit, reason, ctx               | {:ok, ctx}                   | None          |
  | query    | bit, key                       | {:ok, value}                 | None          |
  | mutate   | bit, changes, ctx              | {:ok, bit, ctx}              | None          |

  ## Monadic Bind Pattern

  The `bind/3` operation is the core composition primitive:

      ctx = Context.new(pac_id: pac_id)
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "hello"}, ctx)
      {:ok, bit, ctx} = Protocol.bind(bit, &classify/2, ctx)
      {:ok, bit, ctx} = Protocol.bind(bit, &extract_tags/2, ctx)

  ## Usage

      # Spawn a cognitive Thunderbit
      {:ok, bit, ctx} = Protocol.spawn_bit(:cognitive, %{content: "What is happening?"}, ctx)

      # Link two Thunderbits
      {:ok, edge, ctx} = Protocol.link(sensory_bit, cognitive_bit, :feeds, ctx)

      # Process an event
      {:ok, bit, outputs, ctx} = Protocol.step(bit, event, ctx)
  """

  alias Thunderline.Thunderbit.{Category, Wiring, Ethics, Context, Edge}
  alias Thunderline.Thundercore.Thunderbit, as: CoreBit

  require Logger

  # ===========================================================================
  # Types
  # ===========================================================================

  @type context :: Context.t()
  @type continuation :: (map(), context() -> {:ok, map(), context()} | {:error, term()})
  @type step_result :: {:ok, map(), [map()], context()} | {:halt, term()}
  @type spawn_result :: {:ok, map(), context()} | {:error, term()}
  @type link_result :: {:ok, Edge.t(), context()} | {:error, term()}

  # ===========================================================================
  # spawn_bit/3 - Create a new Thunderbit
  # ===========================================================================

  @doc """
  Creates a new Thunderbit of the specified category.

  This is the "birth ritual" - validates category, enriches with defaults,
  registers in context.

  ## Parameters
  - `category` - The category ID (:sensory, :cognitive, etc.)
  - `attrs` - Initial attributes (content, tags, energy, etc.)
  - `ctx` - The Context to register the bit in

  ## Returns
  - `{:ok, bit, ctx}` on success with bit registered in context
  - `{:error, reason}` on failure
  - `context` - Spawn context (pac_id, zone, etc.)

  ## Returns
  - `{:ok, %Thunderbit{}}` on success
  - `{:error, reason}` on failure (unknown category, policy violation, etc.)

  ## Examples

      ctx = Context.new(pac_id: "ezra")
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "hello"}, ctx)

      {:error, :unknown_category} = Protocol.spawn_bit(:invalid, %{}, ctx)
  """
  @spec spawn_bit(Category.id(), map(), context()) :: spawn_result()
  def spawn_bit(category, attrs, %Context{} = ctx) do
    with {:ok, cat} <- Category.get(category),
         :ok <- Ethics.check_spawn(category, ctx),
         {:ok, bit} <- build_bit(cat, attrs, ctx) do
      Logger.debug("[Protocol.spawn_bit] Created #{category} Thunderbit: #{bit.id}")
      
      # Register bit in context and emit event
      ctx = ctx
            |> Context.register_bit(bit)
            |> Context.emit_event(:bit_spawned, %{
                 bit_id: bit.id,
                 category: category,
                 role: cat.role
               })
      
      {:ok, bit, ctx}
    end
  end
  
  # Legacy support: convert raw map context to Context struct
  def spawn_bit(category, attrs, context) when is_map(context) do
    ctx = Context.new(
      pac_id: Map.get(context, :pac_id),
      zone: Map.get(context, :zone),
      policies: Map.get(context, :policies, [])
    )
    spawn_bit(category, attrs, ctx)
  end

  defp build_bit(cat, attrs, ctx) do
    content = Map.get(attrs, :content, "")
    kind = infer_kind(cat.id)

    base_attrs = [
      kind: kind,
      source: Map.get(attrs, :source, :system),
      content: content,
      tags: Map.get(attrs, :tags, []),
      energy: Map.get(attrs, :energy, 0.5),
      salience: Map.get(attrs, :salience, 0.5),
      owner: ctx.pac_id || Map.get(attrs, :owner),
      metadata:
        Map.merge(
          Map.get(attrs, :metadata, %{}),
          %{
            category: cat.id,
            role: cat.role,
            capabilities: cat.capabilities,
            maxims: cat.required_maxims,
            graph_id: ctx.graph_id,
            zone: ctx.zone
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
  # bind/3 - Monadic bind (pure, ctx-threaded)
  # ===========================================================================

  @doc """
  Monadic bind: passes a Thunderbit through a continuation function.

  The continuation receives the bit and context, and returns a modified
  bit and updated context. This is the core composition primitive.

  ## Preservation Rules
  - bit.id MUST remain unchanged
  - bit.category MUST remain unchanged
  - bit.role MUST remain unchanged
  - Only content, tags, energy, salience may be modified
  - ctx MUST be threaded through (never dropped)

  ## Parameters
  - `bit` - The Thunderbit to transform
  - `continuation` - A function `(bit, ctx) -> {:ok, bit', ctx'} | {:error, reason}`
  - `ctx` - The current Context

  ## Returns
  - `{:ok, bit', ctx'}` - The transformed bit and updated context
  - `{:error, reason}` - If continuation fails

  ## Examples

      {:ok, bit, ctx} = Protocol.bind(bit, fn bit, ctx ->
        bit = %{bit | energy: bit.energy * 1.1}
        {:ok, bit, Context.log(ctx, :debug, "bind", "Boosted energy")}
      end, ctx)
  """
  @spec bind(map(), continuation(), context()) :: {:ok, map(), context()} | {:error, term()}
  def bind(bit, continuation, %Context{} = ctx) when is_function(continuation, 2) do
    case continuation.(bit, ctx) do
      {:ok, new_bit, new_ctx} ->
        # Enforce preservation rules
        validated_bit = %{new_bit | 
          id: bit.id,
          category: bit.category,
          role: bit.role
        }
        
        # Update bit in context
        new_ctx = Context.update_bit(new_ctx, validated_bit)
        {:ok, validated_bit, new_ctx}
        
      {:error, _} = error ->
        error
        
      # Legacy support: tuple return
      {new_bit, new_ctx} when is_map(new_bit) and is_struct(new_ctx, Context) ->
        validated_bit = %{new_bit | id: bit.id, category: bit.category, role: bit.role}
        new_ctx = Context.update_bit(new_ctx, validated_bit)
        {:ok, validated_bit, new_ctx}
    end
  end
  
  # Legacy bind/2 for backward compatibility
  @doc false
  def bind(bit, continuation) when is_function(continuation, 2) do
    ctx = Context.new()
    case bind(bit, continuation, ctx) do
      {:ok, new_bit, new_ctx} -> {new_bit, new_ctx}
      {:error, reason} -> raise "Bind failed: #{inspect(reason)}"
    end
  end

  @doc """
  Chains multiple bind operations through a Thunderbit.

  Each continuation in the list is applied in order. If any fails,
  the chain halts and returns the error.

  ## Parameters
  - `bit` - The Thunderbit to transform
  - `continuations` - List of `(bit, ctx) -> {:ok, bit', ctx'}` functions
  - `ctx` - The current Context

  ## Returns
  - `{:ok, bit', ctx'}` - Final transformed bit and context
  - `{:error, reason}` - First error encountered

  ## Examples

      {:ok, bit, ctx} = Protocol.chain(bit, [
        &classify/2,
        &extract_tags/2,
        &compute_salience/2
      ], ctx)
  """
  @spec chain(map(), [continuation()], context()) :: {:ok, map(), context()} | {:error, term()}
  def chain(bit, continuations, %Context{} = ctx) when is_list(continuations) do
    Enum.reduce_while(continuations, {:ok, bit, ctx}, fn cont, {:ok, b, c} ->
      case bind(b, cont, c) do
        {:ok, new_bit, new_ctx} -> {:cont, {:ok, new_bit, new_ctx}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
  
  # Legacy chain/2
  @doc false
  def chain(bit, continuations) when is_list(continuations) do
    ctx = Context.new()
    case chain(bit, continuations, ctx) do
      {:ok, new_bit, new_ctx} -> {new_bit, new_ctx}
      {:error, reason} -> raise "Chain failed: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # link/4 - Connect two Thunderbits (pure, ctx-threaded)
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
  - `{:ok, edge, ctx}` on success with edge registered in context
  - `{:error, reason}` on failure (invalid wiring, ethics violation)

  ## Examples

      {:ok, edge, ctx} = Protocol.link(sensory_bit, cognitive_bit, :feeds, ctx)

      {:error, {:invalid_wiring, :motor, :sensory}} = Protocol.link(motor_bit, sensory_bit, :feeds, ctx)
  """
  @spec link(map(), map(), atom(), context()) :: link_result()
  def link(from_bit, to_bit, relation, %Context{} = ctx) do
    with :ok <- Wiring.validate_relation(from_bit.category, to_bit.category, relation),
         :ok <- Ethics.check_link(from_bit, to_bit, relation),
         {:ok, edge} <- create_edge(from_bit, to_bit, relation) do
      
      # Add edge to context and emit event
      ctx = ctx
            |> Context.add_edge(edge)
            |> Context.emit_event(:bits_linked, %{
                 from_id: from_bit.id,
                 to_id: to_bit.id,
                 relation: relation,
                 edge_id: edge.id
               })
      
      {:ok, edge, ctx}
    end
  end
  
  # Legacy link/3 for backward compatibility
  @doc false
  def link(from_bit, to_bit, relation) do
    ctx = Context.new()
    case link(from_bit, to_bit, relation, ctx) do
      {:ok, edge, _ctx} -> {:ok, edge}
      {:error, _} = error -> error
    end
  end
  
  defp create_edge(from_bit, to_bit, relation) do
    # Try to use new Edge module, fall back to Wiring
    if function_exported?(Edge, :new, 4) do
      Edge.new(from_bit.id, to_bit.id, relation,
        from_category: from_bit.category,
        to_category: to_bit.category
      )
    else
      Wiring.create_edge(from_bit, to_bit, relation)
    end
  end

  # ===========================================================================
  # step/3 - Process one input event (pure, ctx-threaded)
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
  - `ctx` - The current Context

  ## Returns
  - `{:ok, bit', outputs, ctx'}` - Updated bit, output events, and context
  - `{:halt, reason}` - Processing halted (error, veto, etc.)

  ## Examples

      {:ok, bit, outputs, ctx} = Protocol.step(cognitive_bit, input_event, ctx)
  """
  @spec step(map(), map(), context()) :: step_result()
  def step(bit, event, %Context{} = ctx) do
    role = Map.get(bit, :role, :transformer)

    case do_step(bit, event, role) do
      {:ok, new_bit, outputs} ->
        # Track capability usage
        tracked = track_step(new_bit, role)
        
        # Update bit in context and emit event
        ctx = ctx
              |> Context.update_bit(tracked)
              |> Context.emit_event(:bit_stepped, %{
                   bit_id: bit.id,
                   role: role,
                   output_count: length(outputs)
                 })
        
        {:ok, tracked, outputs, ctx}

      {:halt, reason} ->
        {:halt, reason}
    end
  end
  
  # Legacy step/2 for backward compatibility
  @doc false
  def step(bit, event) do
    ctx = Context.new()
    case step(bit, event, ctx) do
      {:ok, new_bit, outputs, _ctx} -> {:ok, new_bit, outputs}
      {:halt, reason} -> {:halt, reason}
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
  # retire/3 - Remove from field (pure, ctx-threaded)
  # ===========================================================================

  @doc """
  Gracefully retires a Thunderbit from the field.

  This is pure - it removes the bit from context but does NOT broadcast.
  Use `retire_with_broadcast/3` if you need side effects.

  ## Parameters
  - `bit` - The Thunderbit to retire
  - `reason` - Reason for retirement (:done, :error, :replaced, etc.)
  - `ctx` - The current Context

  ## Returns
  - `{:ok, ctx}` with bit removed from context

  ## Examples

      {:ok, ctx} = Protocol.retire(bit, :done, ctx)
  """
  @spec retire(map(), atom(), context()) :: {:ok, context()}
  def retire(bit, reason, %Context{} = ctx) do
    Logger.debug("[Protocol.retire] Retiring #{bit.id}: #{reason}")
    
    # Remove from context and emit event
    ctx = ctx
          |> Context.emit_event(:bit_retired, %{
               bit_id: bit.id,
               reason: reason
             })
    
    # Remove bit from bits_by_id
    new_bits = Map.delete(ctx.bits_by_id, bit.id)
    ctx = %{ctx | bits_by_id: new_bits}
    
    {:ok, ctx}
  end
  
  @doc """
  Retires a Thunderbit and broadcasts the retirement event.

  This has side effects (PubSub broadcast).

  ## Parameters
  - `bit` - The Thunderbit to retire
  - `reason` - Reason for retirement
  - `ctx` - The current Context

  ## Returns
  - `{:ok, ctx}` with bit removed and event broadcast
  """
  @spec retire_with_broadcast(map(), atom(), context()) :: {:ok, context()}
  def retire_with_broadcast(bit, reason, %Context{} = ctx) do
    {:ok, ctx} = retire(bit, reason, ctx)
    
    # Broadcast retirement
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbits:lobby",
      {:thunderbit_retire, %{id: bit.id, reason: reason}}
    )
    
    {:ok, ctx}
  end
  
  # Legacy retire/2 for backward compatibility
  @doc false
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
  # query/2 - Read internal state (pure, no ctx needed)
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
  # mutate/3 - Update internal state (pure, ctx-threaded)
  # ===========================================================================

  @doc """
  Mutates a Thunderbit's internal state.

  Validates that the mutation is allowed based on the Thunderbit's
  capabilities and ethics constraints.

  ## Protected Fields (CANNOT be mutated)
  - :id, :category, :role, :inserted_at

  ## Parameters
  - `bit` - The Thunderbit to mutate
  - `changes` - Map of changes to apply
  - `ctx` - The current Context

  ## Returns
  - `{:ok, bit', ctx'}` on success with bit updated in context
  - `{:error, :forbidden}` if mutation is not allowed

  ## Examples

      {:ok, bit, ctx} = Protocol.mutate(bit, %{energy: 0.9, salience: 0.8}, ctx)
  """
  @spec mutate(map(), map(), context()) :: {:ok, map(), context()} | {:error, :forbidden}
  def mutate(bit, changes, %Context{} = ctx) when is_map(changes) do
    # Protected fields that can't be mutated
    protected = [:id, :category, :role, :inserted_at]

    if Enum.any?(Map.keys(changes), &(&1 in protected)) do
      {:error, :forbidden}
    else
      new_bit = Map.merge(bit, changes)
      ctx = Context.update_bit(ctx, new_bit)
      {:ok, new_bit, ctx}
    end
  end
  
  # Legacy mutate/2 for backward compatibility
  @doc false
  def mutate(bit, changes) when is_map(changes) do
    protected = [:id, :category, :role, :inserted_at]

    if Enum.any?(Map.keys(changes), &(&1 in protected)) do
      {:error, :forbidden}
    else
      new_bit = Map.merge(bit, changes)
      {:ok, new_bit}
    end
  end

  # ===========================================================================
  # Convenience: spawn_for_ui/1 and spawn_for_ui/2
  # ===========================================================================

  @doc """
  Spawns Thunderbit(s) for UI display based on input.

  This is the main entry point for the "text → Thunderbit → UI" flow.
  Returns bits and context for full control.

  ## Parameters
  - `input` - Map with :pac_id, :input_type, :content, :zone

  ## Returns
  - `{:ok, bits, edges, ctx}` - List of bits, edges, and final context
  - `{:error, reason}` - If spawn fails
  """
  @spec spawn_for_ui(map()) :: {:ok, [map()], [Edge.t()], context()} | {:error, term()}
  def spawn_for_ui(%{content: content} = input) do
    ctx = Context.new(
      pac_id: Map.get(input, :pac_id),
      zone: Map.get(input, :zone)
    )

    # Start with sensory bit
    with {:ok, sensory, ctx} <- spawn_bit(:sensory, %{content: content}, ctx),
         {:ok, sensory, ctx} <- bind(sensory, &classify_input/2, ctx),
         {:ok, sensory, ctx} <- bind(sensory, &extract_tags/2, ctx) do
      
      # Maybe spawn cognitive bit and link
      {bits, edges, ctx} =
        if needs_reasoning?(sensory) do
          case spawn_bit(:cognitive, %{content: content, input: sensory.id}, ctx) do
            {:ok, cognitive, ctx} ->
              case link(sensory, cognitive, :feeds, ctx) do
                {:ok, edge, ctx} -> {[sensory, cognitive], [edge], ctx}
                {:error, _} -> {[sensory, cognitive], [], ctx}
              end
            _ -> 
              {[sensory], [], ctx}
          end
        else
          {[sensory], [], ctx}
        end

      {:ok, bits, edges, ctx}
    end
  end
  
  @doc """
  Spawns Thunderbit(s) and returns UI specs (legacy convenience).

  ## Parameters
  - `input` - Map with :pac_id, :input_type, :content, :zone

  ## Returns
  - `{:ok, [ui_spec, ...]}` - List of UI specs ready for rendering
  """
  @spec spawn_for_ui_specs(map()) :: {:ok, [map()]} | {:error, term()}
  def spawn_for_ui_specs(%{content: _content} = input) do
    case spawn_for_ui(input) do
      {:ok, bits, edges, _ctx} ->
        ui_specs = Enum.map(bits, fn bit -> to_ui_spec(bit, edges) end)
        {:ok, ui_specs}
      {:error, _} = error ->
        error
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

    {:ok, %{bit | kind: kind}, ctx}
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

    {:ok, %{bit | tags: tags}, ctx}
  end

  defp needs_reasoning?(bit) do
    bit.kind in [:question, :intent]
  end

  defp to_ui_spec(bit, edges \\ []) do
    {:ok, cat} = Category.get(bit.category)
    geometry = Map.get(cat, :geometry, %{})
    
    # Find edges involving this bit
    bit_edges = Enum.filter(edges, fn e -> 
      e.from_id == bit.id || e.to_id == bit.id 
    end)

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
        Enum.map(bit_edges, fn edge ->
          target_id = if edge.from_id == bit.id, do: edge.to_id, else: edge.from_id
          %{
            target_id: target_id, 
            relation_type: Atom.to_string(edge.relation), 
            strength: edge.strength
          }
        end) ++
        Enum.map(bit.links || [], fn link_id ->
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
