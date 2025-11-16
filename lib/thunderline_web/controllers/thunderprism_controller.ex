defmodule ThunderlineWeb.ThunderprismController do
  @moduledoc """
  ThunderPrism HTTP API controller.

  Provides 5 endpoints for DAG scratchpad operations:
  - POST /api/thunderprism/nodes - Create a decision node
  - GET /api/thunderprism/nodes/:id - Get node with edges
  - GET /api/thunderprism/graph - Get graph data (3d-force-graph compatible)
  - POST /api/thunderprism/edges - Create an edge between nodes
  - GET /api/thunderprism/nodes/:id/edges - Get all edges for a node

  Phase 4.0 - November 15, 2025
  """
  use ThunderlineWeb, :controller

  require Ash.Query

  action_fallback ThunderlineWeb.FallbackController

  @doc ~S"""
  POST /api/thunderprism/nodes

  Creates a new PrismNode representing an ML decision point.

  Required params:
  - pac_id: string
  - iteration: integer
  - chosen_model: string
  - timestamp: datetime

  Optional params:
  - model_probabilities: map (default: %{})
  - model_distances: map (default: %{})
  - meta: map (default: %{})

  ## Example Request

      POST /api/thunderprism/nodes
      {
        "pac_id": "pac-123",
        "iteration": 42,
        "chosen_model": "model_a",
        "model_probabilities": {"model_a": 0.75, "model_b": 0.25},
        "model_distances": {"model_a": 0.2, "model_b": 0.8},
        "meta": {"score": 0.95},
        "timestamp": "2025-11-15T18:30:00Z"
      }

  ## Example Response

      201 Created
      {
        "data": {
          "id": "uuid-1",
          "pac_id": "pac-123",
          "iteration": 42,
          "chosen_model": "model_a",
          "model_probabilities": {"model_a": 0.75, "model_b": 0.25},
          "model_distances": {"model_a": 0.2, "model_b": 0.8},
          "meta": {"score": 0.95},
          "timestamp": "2025-11-15T18:30:00Z",
          "inserted_at": "2025-11-15T18:30:05Z",
          "updated_at": "2025-11-15T18:30:05Z"
        }
      }
  """
  def create_node(conn, params) do
    with {:ok, node} <-
           Thunderline.Thunderprism.PrismNode
           |> Ash.Changeset.for_create(:create, params)
           |> Ash.create() do
      conn
      |> put_status(:created)
      |> json(%{data: node})
    end
  end

  @doc ~S"""
  GET /api/thunderprism/nodes/:id

  Retrieves a single PrismNode with its edges loaded.

  ## Example Response

      200 OK
      {
        "data": {
          "id": "uuid-1",
          "pac_id": "pac-123",
          "iteration": 42,
          "chosen_model": "model_a",
          "out_edges": [...],
          "in_edges": [...]
        }
      }
  """
  def get_node(conn, %{"id" => id}) do
    with {:ok, node} <-
           Thunderline.Thunderprism.PrismNode
           |> Ash.get(id, load: [:out_edges, :in_edges]) do
      json(conn, %{data: node})
    end
  end

  @doc ~S"""
  GET /api/thunderprism/graph

  Returns graph data in 3d-force-graph compatible format.

  Query params:
  - pac_id (optional): Filter by PAC ID
  - limit (optional): Max nodes to return (default: 100)

  ## Example Request

      GET /api/thunderprism/graph?pac_id=pac-123&limit=50

  ## Example Response

      200 OK
      {
        "nodes": [
          {
            "id": "uuid-1",
            "pac_id": "pac-123",
            "iteration": 42,
            "chosen_model": "model_a",
            "meta": {"score": 0.95}
          },
          {
            "id": "uuid-2",
            "pac_id": "pac-123",
            "iteration": 43,
            "chosen_model": "model_b",
            "meta": {"score": 0.88}
          }
        ],
        "links": [
          {
            "source": "uuid-1",
            "target": "uuid-2",
            "relation_type": "next"
          }
        ]
      }
  """
  def get_graph(conn, params) do
    limit = Map.get(params, "limit", "100") |> String.to_integer()

    query =
      Thunderline.Thunderprism.PrismNode
      |> Ash.Query.load([:out_edges])
      |> Ash.Query.limit(limit)

    query =
      if pac_id = params["pac_id"] do
        Ash.Query.filter(query, pac_id == ^pac_id)
      else
        query
      end

    with {:ok, nodes} <- Ash.read(query) do
      # Build graph structure for 3d-force-graph
      graph_nodes =
        Enum.map(nodes, fn node ->
          %{
            id: node.id,
            pac_id: node.pac_id,
            iteration: node.iteration,
            chosen_model: node.chosen_model,
            meta: node.meta
          }
        end)

      graph_links =
        nodes
        |> Enum.flat_map(fn node ->
          Enum.map(node.out_edges || [], fn edge ->
            %{
              source: edge.from_id,
              target: edge.to_id,
              relation_type: edge.relation_type
            }
          end)
        end)

      json(conn, %{nodes: graph_nodes, links: graph_links})
    end
  end

  @doc ~S"""
  POST /api/thunderprism/edges

  Creates a new PrismEdge connecting two nodes.

  Required params:
  - from_id: uuid
  - to_id: uuid

  Optional params:
  - relation_type: string (default: "next")
  - meta: map (default: %{})

  ## Example Request

      POST /api/thunderprism/edges
      {
        "from_id": "uuid-1",
        "to_id": "uuid-2",
        "relation_type": "next",
        "meta": {"confidence": 0.95}
      }

  ## Example Response

      201 Created
      {
        "data": {
          "id": "edge-uuid-1",
          "from_id": "uuid-1",
          "to_id": "uuid-2",
          "relation_type": "next",
          "meta": {"confidence": 0.95},
          "inserted_at": "2025-11-15T18:30:05Z",
          "updated_at": "2025-11-15T18:30:05Z"
        }
      }
  """
  def create_edge(conn, params) do
    with {:ok, edge} <-
           Thunderline.Thunderprism.PrismEdge
           |> Ash.Changeset.for_create(:create, params)
           |> Ash.create() do
      conn
      |> put_status(:created)
      |> json(%{data: edge})
    end
  end

  @doc ~S"""
  GET /api/thunderprism/nodes/:id/edges

  Returns all edges (incoming and outgoing) for a specific node.

  ## Example Response

      200 OK
      {
        "data": [
          {
            "id": "edge-uuid-1",
            "from_id": "uuid-0",
            "to_id": "uuid-1",
            "relation_type": "next"
          },
          {
            "id": "edge-uuid-2",
            "from_id": "uuid-1",
            "to_id": "uuid-2",
            "relation_type": "next"
          }
        ]
      }
  """
  def get_node_edges(conn, %{"id" => id}) do
    with {:ok, node} <-
           Thunderline.Thunderprism.PrismNode
           |> Ash.get(id, load: [:out_edges, :in_edges]) do
      edges = (node.out_edges || []) ++ (node.in_edges || [])
      json(conn, %{data: edges})
    end
  end
end
