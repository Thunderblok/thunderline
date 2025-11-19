defmodule ThunderlineWeb.ThunderlinkController do
  @moduledoc """
  REST API endpoints for Thunderlink cluster topology and node management.

  Provides HTTP access to:
  - Cluster graph visualization data (3d-force-graph compatible)
  - Node listing with filtering and pagination
  - Individual node details with relationships

  All endpoints use the Registry ETS cache for fast reads.
  """

  use ThunderlineWeb, :controller
  alias Thunderline.Thunderlink.Registry

  action_fallback ThunderlineWeb.FallbackController

  @doc """
  GET /api/thunderlink/graph

  Returns cluster topology as 3d-force-graph compatible structure.

  ## Response

      {
        "nodes": [
          {
            "id": "node_uuid",
            "name": "worker-1",
            "domain": "thunderlink",
            "status": "online",
            "role": "worker"
          }
        ],
        "links": [
          {
            "source": "node_uuid_1",
            "target": "node_uuid_2",
            "weight": 1.0,
            "session_type": "cluster"
          }
        ]
      }
  """
  def graph(conn, _params) do
    graph_data = Registry.graph()
    json(conn, graph_data)
  end

  @doc """
  GET /api/thunderlink/nodes

  List all nodes with optional filtering.

  ## Query Parameters

  - `status` - Filter by status (online, offline, degraded, disconnected)
  - `domain` - Filter by domain name
  - `role` - Filter by role
  - `cluster_type` - Filter by cluster type (in_cluster, edge)

  ## Response

      {
        "nodes": [
          {
            "id": "node_uuid",
            "name": "worker-1",
            "domain": "thunderlink",
            "status": "online",
            "role": "worker",
            "cluster_type": "in_cluster",
            "last_seen_at": "2024-01-15T10:30:00Z",
            "inserted_at": "2024-01-15T08:00:00Z"
          }
        ]
      }
  """
  def index(conn, params) do
    opts = build_query_opts(params)
    nodes = Registry.list_nodes(opts)
    json(conn, %{nodes: nodes})
  end

  @doc """
  GET /api/thunderlink/nodes/:id

  Get a specific node by ID with optional relationship loading.

  ## Query Parameters

  - `load` - Comma-separated list of relationships to load (e.g., "heartbeats,capabilities")

  ## Response

      {
        "node": {
          "id": "node_uuid",
          "name": "worker-1",
          "domain": "thunderlink",
          "status": "online",
          "role": "worker",
          "cluster_type": "in_cluster",
          "last_seen_at": "2024-01-15T10:30:00Z",
          "heartbeats": [...],
          "capabilities": [...]
        }
      }
  """
  def show(conn, %{"id" => node_id} = params) do
    load_opts = parse_load_param(params["load"])
    opts = [load: load_opts]

    case Registry.get_node(node_id, opts) do
      {:ok, node} ->
        json(conn, %{node: node})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Node not found"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp build_query_opts(params) do
    []
    |> maybe_add_filter(:status, params["status"])
    |> maybe_add_filter(:domain, params["domain"])
    |> maybe_add_filter(:role, params["role"])
    |> maybe_add_filter(:cluster_type, params["cluster_type"])
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts

  defp maybe_add_filter(opts, key, value) do
    Keyword.put(opts, key, value)
  end

  defp parse_load_param(nil), do: []
  defp parse_load_param(""), do: []

  defp parse_load_param(load_str) when is_binary(load_str) do
    load_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_load_param(_), do: []
end
