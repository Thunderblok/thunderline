defmodule Thunderline.Thunderlink.Registry do
  @moduledoc """
  Thunderlink Node Registry - Central coordinator for BEAM cluster + edge nodes.

  This module provides a unified interface for:
  - Node registration and lifecycle management
  - Heartbeat tracking and health monitoring
  - Link session management (node-to-node connections)
  - Cluster topology queries and graph generation
  - Capability-based routing and discovery

  ## Architecture

  The registry is built on 6 Ash resources:
  - **Node**: Core node metadata (name, role, status, cluster_type)
  - **Heartbeat**: Rolling liveness records with metrics
  - **LinkSession**: Bidirectional edge connections
  - **NodeCapability**: Key-value capability tags for routing
  - **NodeGroup**: Logical grouping with optional hierarchy
  - **NodeGroupMembership**: Join table for group membership

  ## Usage

      # Register a node
      {:ok, node} = Registry.ensure_node(%{
        name: "worker-1",
        role: "worker",
        domain: "thunderlink",
        cluster_type: "in_cluster"
      })

      # Mark node online and establish link session
      {:ok, {node, session}} = Registry.mark_online(node.id, %{
        remote_node_id: other_node_id,
        session_type: "cluster"
      })

      # Record heartbeat
      {:ok, heartbeat} = Registry.heartbeat(node.id, %{
        cpu_load: 0.45,
        mem_used_mb: 512,
        latency_ms: 23
      })

      # Get cluster topology
      graph = Registry.graph()
      # => %{nodes: [...], links: [...]}

  ## Integration Points

  - **Thundergate**: Calls `ensure_node/1` on WebRTC handshake
  - **Thunderlink**: Calls `mark_online/2` on QUIC connection established
  - **Thunderflow**: Emits cluster.* events on state changes
  - **ThunderlinkController**: Exposes HTTP API for graph queries
  - **Phoenix Channel**: Broadcasts realtime topology updates
  """

  alias Thunderline.Thunderlink.Domain
  alias Thunderline.Thunderlink.Resources.{Node, Heartbeat, LinkSession, NodeCapability}

  require Logger

  @type node_attrs :: %{
          name: String.t(),
          role: String.t(),
          domain: String.t(),
          cluster_type: String.t(),
          hotline_peer_id: String.t() | nil,
          did: String.t() | nil,
          meta: map()
        }

  @type session_attrs :: %{
          remote_node_id: String.t(),
          session_type: String.t(),
          weight: float() | nil,
          latency_ms: integer() | nil,
          bandwidth_mbps: float() | nil,
          meta: map()
        }

  @type heartbeat_metrics :: %{
          status: atom(),
          cpu_load: float() | nil,
          mem_used_mb: integer() | nil,
          latency_ms: integer() | nil,
          meta: map()
        }

  @type graph :: %{
          nodes: [map()],
          links: [map()]
        }

  # ============================================================================
  # Node Lifecycle Management
  # ============================================================================

  @doc """
  Register or update a node in the registry.

  Uses upsert on the unique name identity to ensure idempotency.
  If node exists, updates metadata and last_seen_at.
  If new, creates with initial status `:disconnected`.

  ## Examples

      {:ok, node} = Registry.ensure_node(%{
        name: "worker-1",
        role: "worker",
        domain: "thunderlink",
        cluster_type: "in_cluster",
        hotline_peer_id: "peer_abc123",
        meta: %{zone: "us-west-2a"}
      })

  ## Options

  - `:actor` - The actor performing the action (for authorization)
  - `:authorize?` - Whether to authorize the action (default: true)
  """
  @spec ensure_node(node_attrs(), Keyword.t()) :: {:ok, Node.t()} | {:error, term()}
  def ensure_node(attrs, opts \\ []) do
    node =
      Domain.register_node!(
        attrs.name,
        Map.merge(
          %{
            role: attrs[:role] || "worker",
            domain: attrs[:domain] || "thunderlink",
            cluster_type: attrs[:cluster_type] || "in_cluster"
          },
          Map.take(attrs, [:hotline_peer_id, :did, :meta])
        ),
        opts
      )

    {:ok, node}
  rescue
    e -> {:error, e}
  end

  @doc """
  Mark a node as online and optionally establish a link session.

  Updates the node status to `:online`, sets last_seen_at, and if remote_node_id
  is provided, creates or updates a LinkSession.

  ## Examples

      # Mark online without link session
      {:ok, node} = Registry.mark_online(node_id)

      # Mark online and establish link
      {:ok, {node, session}} = Registry.mark_online(node_id, %{
        remote_node_id: other_node_id,
        session_type: "cluster",
        weight: 1.0
      })

  ## Options

  - `:actor` - The actor performing the action
  - `:authorize?` - Whether to authorize (default: true)
  """
  @spec mark_online(String.t(), session_attrs() | nil, Keyword.t()) ::
          {:ok, Node.t()} | {:ok, {Node.t(), LinkSession.t()}} | {:error, term()}
  def mark_online(node_id, session_attrs \\ nil, opts \\ []) do
    with {:ok, node} <- Domain.mark_node_online!(node_id, opts) do
      if session_attrs && session_attrs[:remote_node_id] do
        case create_or_update_link_session(node_id, session_attrs, opts) do
          {:ok, session} -> {:ok, {node, session}}
          {:error, _} = error -> error
        end
      else
        {:ok, node}
      end
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Mark a node as offline.

  Updates the node status to `:offline` and sets last_seen_at.
  Does NOT automatically close link sessions (they may recover).

  ## Examples

      {:ok, node} = Registry.mark_offline(node_id)
  """
  @spec mark_offline(String.t(), Keyword.t()) :: {:ok, Node.t()} | {:error, term()}
  def mark_offline(node_id, opts \\ []) do
    Domain.mark_node_offline!(node_id, opts)
  rescue
    e -> {:error, e}
  end

  @doc """
  Update a node's status.

  Valid statuses: `:online`, `:offline`, `:degraded`, `:disconnected`

  ## Examples

      {:ok, node} = Registry.mark_status(node_id, :degraded)
  """
  @spec mark_status(String.t(), atom(), Keyword.t()) :: {:ok, Node.t()} | {:error, term()}
  def mark_status(node_id, status, opts \\ []) do
    Domain.mark_node_status!(node_id, status, opts)
  rescue
    e -> {:error, e}
  end

  # ============================================================================
  # Heartbeat Management
  # ============================================================================

  @doc """
  Record a heartbeat for a node with optional metrics.

  Creates a new heartbeat record with current timestamp and provided metrics.
  Old heartbeats are periodically pruned by a separate compression job.

  ## Examples

      {:ok, heartbeat} = Registry.heartbeat(node_id, %{
        status: :online,
        cpu_load: 0.45,
        mem_used_mb: 512,
        latency_ms: 23,
        meta: %{custom_metric: 42}
      })

  ## Options

  - `:actor` - The actor performing the action
  - `:authorize?` - Whether to authorize (default: true)
  """
  @spec heartbeat(String.t(), heartbeat_metrics(), Keyword.t()) ::
          {:ok, Heartbeat.t()} | {:error, term()}
  def heartbeat(node_id, metrics \\ %{}, opts \\ []) do
    Domain.record_heartbeat!(
      node_id,
      metrics[:status] || :online,
      Map.take(metrics, [:cpu_load, :mem_used_mb, :latency_ms, :meta]),
      opts
    )
  rescue
    e -> {:error, e}
  end

  @doc """
  Get recent heartbeats for a node.

  ## Examples

      heartbeats = Registry.recent_heartbeats(node_id, minutes: 5)
  """
  @spec recent_heartbeats(String.t(), Keyword.t()) :: [Heartbeat.t()]
  def recent_heartbeats(node_id, opts \\ []) do
    minutes = Keyword.get(opts, :minutes, 60)

    Domain.recent_heartbeats!(minutes, opts)
    |> Enum.filter(&(&1.node_id == node_id))
  rescue
    _ -> []
  end

  # ============================================================================
  # Link Session Management
  # ============================================================================

  @doc """
  Establish a link session between two nodes.

  Creates a new LinkSession if it doesn't exist, or updates an existing one.
  Automatically sets established_at and last_activity_at.

  ## Examples

      {:ok, session} = Registry.establish_link_session(node_id, %{
        remote_node_id: other_node_id,
        session_type: "cluster",
        weight: 1.0,
        latency_ms: 15
      })
  """
  @spec establish_link_session(String.t(), session_attrs(), Keyword.t()) ::
          {:ok, LinkSession.t()} | {:error, term()}
  def establish_link_session(node_id, attrs, opts \\ []) do
    # Try to find existing session
    existing_sessions =
      Domain.active_link_sessions!(opts)
      |> Enum.filter(fn s ->
        (s.node_id == node_id && s.remote_node_id == attrs.remote_node_id) ||
          (s.node_id == attrs.remote_node_id && s.remote_node_id == node_id)
      end)

    case existing_sessions do
      [session | _] ->
        # Update existing session
        Domain.update_link_session_metrics!(
          session.id,
          Map.take(attrs, [:latency_ms, :bandwidth_mbps, :weight, :meta]),
          opts
        )

      [] ->
        # Create new session
        LinkSession
        |> Ash.Changeset.for_create(:create, %{
          node_id: node_id,
          remote_node_id: attrs.remote_node_id,
          session_type: attrs[:session_type] || "cluster",
          weight: attrs[:weight] || 1.0,
          latency_ms: attrs[:latency_ms],
          bandwidth_mbps: attrs[:bandwidth_mbps],
          meta: attrs[:meta] || %{}
        })
        |> Ash.create(opts)
        |> case do
          {:ok, session} ->
            # Mark as established
            Domain.establish_link_session!(session.id, opts)

          {:error, _} = error ->
            error
        end
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Close a link session.

  Marks the session as closed but doesn't delete it (preserves history).

  ## Examples

      {:ok, session} = Registry.close_link_session(session_id)
  """
  @spec close_link_session(String.t(), Keyword.t()) :: {:ok, LinkSession.t()} | {:error, term()}
  def close_link_session(session_id, opts \\ []) do
    Domain.close_link_session!(session_id, opts)
  rescue
    e -> {:error, e}
  end

  # ============================================================================
  # Query Functions
  # ============================================================================

  @doc """
  List nodes with optional filters.

  ## Examples

      # All nodes
      nodes = Registry.list_nodes()

      # Only online nodes
      nodes = Registry.list_nodes(status: :online)

      # By role
      nodes = Registry.list_nodes(role: "worker")

  ## Filters

  - `:status` - Filter by status (:online, :offline, :degraded, :disconnected)
  - `:role` - Filter by role
  - `:cluster_type` - Filter by cluster type
  - `:domain` - Filter by domain
  """
  @spec list_nodes(Keyword.t()) :: [Node.t()]
  def list_nodes(filters \\ [], opts \\ []) do
    query_opts = build_query_opts(filters, opts)

    cond do
      filters[:status] ->
        Domain.nodes_by_status!(filters[:status], query_opts)

      filters[:role] ->
        Domain.nodes_by_role!(filters[:role], query_opts)

      true ->
        Node
        |> Ash.Query.for_read(:read, %{}, query_opts)
        |> Ash.read!(query_opts)
    end
  rescue
    e ->
      Logger.error("Failed to list nodes: #{inspect(e)}")
      []
  end

  @doc """
  Get a specific node by ID.

  ## Examples

      {:ok, node} = Registry.get_node(node_id)
  """
  @spec get_node(String.t(), Keyword.t()) :: {:ok, Node.t()} | {:error, :not_found}
  def get_node(node_id, opts \\ []) do
    case Ash.get(Node, node_id, opts) do
      {:ok, node} -> {:ok, node}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Get all online nodes.

  ## Examples

      nodes = Registry.online_nodes()
  """
  @spec online_nodes(Keyword.t()) :: [Node.t()]
  def online_nodes(opts \\ []) do
    Domain.online_nodes!(opts)
  rescue
    _ -> []
  end

  # ============================================================================
  # Capability Management
  # ============================================================================

  @doc """
  Add a capability to a node.

  ## Examples

      {:ok, capability} = Registry.add_capability(node_id, %{
        capability_key: "ml_inference",
        capability_value: "transformers",
        enabled: true
      })
  """
  @spec add_capability(String.t(), map(), Keyword.t()) ::
          {:ok, NodeCapability.t()} | {:error, term()}
  def add_capability(node_id, attrs, opts \\ []) do
    NodeCapability
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :node_id, node_id))
    |> Ash.create(opts)
  rescue
    e -> {:error, e}
  end

  @doc """
  Find nodes with a specific capability.

  ## Examples

      nodes = Registry.nodes_with_capability("ml_inference")
      nodes = Registry.nodes_with_capability("ml_inference", "transformers")
  """
  @spec nodes_with_capability(String.t(), String.t() | nil, Keyword.t()) :: [Node.t()]
  def nodes_with_capability(key, value \\ nil, opts \\ []) do
    # Get capabilities
    capabilities =
      if value do
        Domain.node_capabilities_by_capability!(key, value, opts)
      else
        NodeCapability
        |> Ash.Query.for_read(:by_capability, %{capability_key: key}, opts)
        |> Ash.read!(opts)
      end

    # Get unique node IDs
    node_ids = capabilities |> Enum.map(& &1.node_id) |> Enum.uniq()

    # Load nodes
    node_ids
    |> Enum.map(fn id ->
      case get_node(id, opts) do
        {:ok, node} -> node
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
  end

  # ============================================================================
  # Graph Generation (for 3D Visualization)
  # ============================================================================

  @doc """
  Generate cluster topology graph for 3d-force-graph visualization.

  Returns a map with:
  - `nodes`: List of node objects with id, name, role, status, metadata
  - `links`: List of edge objects with source, target, session metadata

  ## Examples

      graph = Registry.graph()
      # => %{
      #   nodes: [
      #     %{id: "uuid1", name: "worker-1", role: "worker", status: "online", val: 10},
      #     %{id: "uuid2", name: "edge-1", role: "edge", status: "online", val: 5}
      #   ],
      #   links: [
      #     %{source: "uuid1", target: "uuid2", value: 1.0, latency_ms: 15}
      #   ]
      # }

  ## Options

  - `:include_offline` - Include offline nodes (default: false)
  - `:actor` - Actor for authorization
  - `:authorize?` - Whether to authorize (default: true)
  """
  @spec graph(Keyword.t()) :: graph()
  def graph(opts \\ []) do
    include_offline = Keyword.get(opts, :include_offline, false)

    # Get nodes
    nodes =
      if include_offline do
        list_nodes([], opts)
      else
        online_nodes(opts)
      end

    # Get active link sessions
    sessions =
      Domain.active_link_sessions!(opts)
      |> Enum.filter(fn session ->
        # Only include sessions where both nodes are in our node list
        node_ids = Enum.map(nodes, & &1.id)
        session.node_id in node_ids && session.remote_node_id in node_ids
      end)

    # Build node objects for 3d-force-graph
    graph_nodes =
      Enum.map(nodes, fn node ->
        %{
          id: node.id,
          name: node.name,
          role: node.role,
          domain: node.domain,
          status: to_string(node.status),
          cluster_type: node.cluster_type,
          # Size node by recent activity (placeholder - could count heartbeats)
          val: if(node.status == :online, do: 10, else: 5),
          meta: node.meta || %{}
        }
      end)

    # Build link objects for 3d-force-graph
    graph_links =
      Enum.map(sessions, fn session ->
        %{
          source: session.node_id,
          target: session.remote_node_id,
          value: session.weight || 1.0,
          session_type: session.session_type,
          latency_ms: session.latency_ms,
          bandwidth_mbps: session.bandwidth_mbps,
          status: to_string(session.status)
        }
      end)

    %{
      nodes: graph_nodes,
      links: graph_links
    }
  rescue
    e ->
      Logger.error("Failed to generate graph: #{inspect(e)}")
      %{nodes: [], links: []}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp create_or_update_link_session(node_id, attrs, opts) do
    # Check if session already exists
    existing =
      Domain.active_link_sessions!(opts)
      |> Enum.find(fn s ->
        (s.node_id == node_id && s.remote_node_id == attrs.remote_node_id) ||
          (s.node_id == attrs.remote_node_id && s.remote_node_id == node_id)
      end)

    if existing do
      # Update existing
      Domain.update_link_session_metrics!(
        existing.id,
        Map.take(attrs, [:latency_ms, :bandwidth_mbps, :weight, :meta]),
        opts
      )
    else
      # Create new
      establish_link_session(node_id, attrs, opts)
    end
  end

  defp build_query_opts(filters, base_opts) do
    # Remove filters that will be handled by specific actions
    filters
    |> Keyword.drop([:status, :role, :cluster_type, :domain])
    |> Keyword.merge(base_opts)
  end
end
