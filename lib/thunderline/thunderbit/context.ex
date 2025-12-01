defmodule Thunderline.Thunderbit.Context do
  @moduledoc """
  Thunderbit Protocol Context - The Local Universe

  The Context is passed through all Protocol operations, threading state
  without global mutation. It contains:

  - **Bit Registry**: All bits by ID
  - **Edge Registry**: All edges between bits
  - **Scope**: Current PAC, graph, zone
  - **Governance**: Active policies and maxims
  - **Logging**: Transformation and event logs

  ## Usage

      ctx = Context.new(pac_id: "ezra-001")
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "hello"}, ctx)
      {bit, ctx} = Protocol.bind(bit, &classify/2, ctx)

  ## Rules

  1. **Never mutate global state** — always take ctx, return ctx
  2. **Explicit field access** — no magic tricks
  3. **Testable** — ctx can be serialized/replayed
  4. **Optimizable** — can be adapted for ECS or CA grids later
  """

  alias Thunderline.Thunderbit.Category

  @type t :: %__MODULE__{
          # Bit registry
          bits_by_id: %{String.t() => map()},
          edges: [map()],

          # Current scope
          pac_id: String.t() | nil,
          graph_id: String.t() | nil,
          zone: String.t() | nil,

          # Governance
          policies: [map()],
          active_maxims: [String.t()],

          # Logging
          log: [map()],
          event_log: [map()],

          # Session
          session_id: String.t(),
          started_at: DateTime.t(),

          # Metadata
          metadata: map()
        }

  defstruct bits_by_id: %{},
            edges: [],
            pac_id: nil,
            graph_id: nil,
            zone: nil,
            policies: [],
            active_maxims: [],
            log: [],
            event_log: [],
            session_id: nil,
            started_at: nil,
            metadata: %{}

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new context with the given options.

  ## Options

  - `:pac_id` - The PAC agent ID
  - `:graph_id` - The behavior graph ID
  - `:zone` - The spatial zone
  - `:policies` - List of active policies
  - `:metadata` - Additional context data

  ## Examples

      iex> Context.new(pac_id: "ezra-001")
      %Context{pac_id: "ezra-001", session_id: "...", ...}
  """
  def new(opts \\ []) do
    %__MODULE__{
      bits_by_id: %{},
      edges: [],
      pac_id: Keyword.get(opts, :pac_id),
      graph_id: Keyword.get(opts, :graph_id),
      zone: Keyword.get(opts, :zone),
      policies: Keyword.get(opts, :policies, []),
      active_maxims: Keyword.get(opts, :active_maxims, default_maxims()),
      log: [],
      event_log: [],
      session_id: generate_session_id(),
      started_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Bit Registry
  # ===========================================================================

  @doc """
  Registers a bit in the context.
  """
  def register_bit(%__MODULE__{} = ctx, bit) do
    %{ctx | bits_by_id: Map.put(ctx.bits_by_id, bit.id, bit)}
  end

  @doc """
  Updates a bit in the context.
  """
  def update_bit(%__MODULE__{} = ctx, bit) do
    %{ctx | bits_by_id: Map.put(ctx.bits_by_id, bit.id, bit)}
  end

  @doc """
  Gets a bit by ID from the context.
  """
  def get_bit(%__MODULE__{} = ctx, bit_id) do
    Map.get(ctx.bits_by_id, bit_id)
  end

  @doc """
  Lists all bits in the context.
  """
  def list_bits(%__MODULE__{} = ctx) do
    Map.values(ctx.bits_by_id)
  end

  @doc """
  Filters bits by category.
  """
  def bits_by_category(%__MODULE__{} = ctx, category) do
    ctx.bits_by_id
    |> Map.values()
    |> Enum.filter(&(Map.get(&1, :category) == category))
  end

  # ===========================================================================
  # Edge Registry
  # ===========================================================================

  @doc """
  Adds an edge to the context.
  """
  def add_edge(%__MODULE__{} = ctx, edge) do
    %{ctx | edges: [edge | ctx.edges]}
  end

  @doc """
  Gets edges from a specific bit.
  """
  def edges_from(%__MODULE__{} = ctx, bit_id) do
    Enum.filter(ctx.edges, &(&1.from_id == bit_id))
  end

  @doc """
  Gets edges to a specific bit.
  """
  def edges_to(%__MODULE__{} = ctx, bit_id) do
    Enum.filter(ctx.edges, &(&1.to_id == bit_id))
  end

  # ===========================================================================
  # Logging
  # ===========================================================================

  @doc """
  Appends a log entry to the context.
  """
  def log(%__MODULE__{} = ctx, level, message, metadata \\ %{}) do
    entry = %{
      level: level,
      message: message,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    %{ctx | log: [entry | ctx.log]}
  end

  @doc """
  Appends an event to the event log.
  """
  def emit_event(%__MODULE__{} = ctx, event_type, payload \\ %{}) do
    event = %{
      type: event_type,
      payload: payload,
      session_id: ctx.session_id,
      timestamp: DateTime.utc_now()
    }

    %{ctx | event_log: [event | ctx.event_log]}
  end

  @doc """
  Returns log entries in chronological order.
  """
  def get_log(%__MODULE__{} = ctx) do
    Enum.reverse(ctx.log)
  end

  @doc """
  Returns events in chronological order.
  """
  def get_events(%__MODULE__{} = ctx) do
    Enum.reverse(ctx.event_log)
  end

  # ===========================================================================
  # Governance
  # ===========================================================================

  @doc """
  Checks if a maxim is active in the context.
  """
  def maxim_active?(%__MODULE__{} = ctx, maxim) do
    maxim in ctx.active_maxims
  end

  @doc """
  Adds a policy to the context.
  """
  def add_policy(%__MODULE__{} = ctx, policy) do
    %{ctx | policies: [policy | ctx.policies]}
  end

  @doc """
  Checks if a category is allowed to spawn in this context.
  """
  def spawn_allowed?(%__MODULE__{} = ctx, category) do
    # Check if any policy restricts this category
    not Enum.any?(ctx.policies, fn policy ->
      Map.get(policy, :restricted_categories, [])
      |> Enum.member?(category)
    end)
  end

  # ===========================================================================
  # Serialization
  # ===========================================================================

  @doc """
  Converts context to a map for serialization/replay.
  """
  def to_map(%__MODULE__{} = ctx) do
    %{
      bits_by_id: ctx.bits_by_id,
      edges: ctx.edges,
      pac_id: ctx.pac_id,
      graph_id: ctx.graph_id,
      zone: ctx.zone,
      policies: ctx.policies,
      active_maxims: ctx.active_maxims,
      log: ctx.log,
      event_log: ctx.event_log,
      session_id: ctx.session_id,
      started_at: DateTime.to_iso8601(ctx.started_at),
      metadata: ctx.metadata
    }
  end

  @doc """
  Restores context from a map.
  """
  def from_map(map) do
    %__MODULE__{
      bits_by_id: map["bits_by_id"] || map[:bits_by_id] || %{},
      edges: map["edges"] || map[:edges] || [],
      pac_id: map["pac_id"] || map[:pac_id],
      graph_id: map["graph_id"] || map[:graph_id],
      zone: map["zone"] || map[:zone],
      policies: map["policies"] || map[:policies] || [],
      active_maxims: map["active_maxims"] || map[:active_maxims] || [],
      log: map["log"] || map[:log] || [],
      event_log: map["event_log"] || map[:event_log] || [],
      session_id: map["session_id"] || map[:session_id] || generate_session_id(),
      started_at: parse_datetime(map["started_at"] || map[:started_at]),
      metadata: map["metadata"] || map[:metadata] || %{}
    }
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp generate_session_id do
    Thunderline.UUID.v7()
  end

  defp default_maxims do
    # Core maxims always active
    [
      "Primum non nocere",
      "Veritas liberabit",
      "Res in armonia"
    ]
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
