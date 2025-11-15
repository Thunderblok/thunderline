# Phase 4.0 – ThunderPrism DAG Scratchpad

**Status**: Specification  
**Date**: November 15, 2025  
**Prerequisite**: Thunderbolt namespace migration complete ✅

---

## Mission

Stabilize **Thunderbolt ML stack** and add **ThunderPrism** as a persistent DAG scratchpad for ML decision trails. This creates "memory rails" that any AI (inside or outside the network) can query, visualize, and use as context.

**What we're building**:
- **Thunderbolt** = ML brain (Parzen + SLA + Controller + Broadway)
- **ThunderPrism** = DAG scratchpad (writes ML decision nodes + edges)
- **Later**: 3D vine / force-graph visualization

**What we're NOT touching**:
- ❌ Thundervine core (leave for Phase 5+)
- ❌ Thunderbit complexity (defer)
- ❌ Moving Thunderbolt ↔ Thundervine modules

---

## 0. Pre-Flight: "No Doppelgängers" Audit

**Objective**: Ensure no shadow modules or overlapping domains after Thunderbolt namespace migration.

### 0.1. Hunt Old Namespaces

```bash
# Should return ZERO hits in lib/ and test/
rg "Thunderline\.ML\." lib test
rg "Thunderline\.RAG\." lib test
rg "Thunderline\.NLP\." lib test
```

**Acceptance**:
- ✅ Zero hits in source code
- ℹ️ Any hits in `docs/` are clearly examples/documentation only
- ✅ All references now use `Thunderline.Thunderbolt.{ML,RAG,NLP}.*`

### 0.2. List Ash Domains and Check for Overlap

```bash
# Find all domain modules
fd "domain.ex" lib/thunderline
```

**For each domain found** (e.g., `thunderbolt/domain.ex`, `thundervine/domain.ex`, `thunderflow/domain.ex`):

1. **Open the file** and confirm:
   - Thunderbolt domain registers **only** ML/RAG/NLP resources
   - No resource is registered in **two domains** (double registration)
   - Each domain has clear responsibility boundaries

2. **If double registration found**:
   - Log it: `[Module] registered in [Domain1] and [Domain2]`
   - Remove from the domain that doesn't match responsibility
   - Likely belongs under Thunderbolt now

**Acceptance**:
- ✅ Each resource registered in exactly ONE domain
- ✅ Thunderbolt owns: ML controllers, RAG documents, embedding models
- ✅ No ML/RAG/NLP resources in Thundervine or other domains

### 0.3. Check for Duplicate Controllers/Consumers

```bash
# Find all controllers
rg "defmodule .*Controller" lib/thunderline

# Find all consumers
rg "defmodule .*Consumer" lib/thunderline/thunderbolt lib/thunderline/thunderflow
```

**Acceptance**:
- ✅ Only **one** ML controller: `Thunderline.Thunderbolt.ML.Controller`
- ✅ Only **one** ML Broadway consumer: `Thunderline.Thunderbolt.ML.ModelSelectionConsumer`
- ✅ No old "ML controller" under Thundervine or legacy namespace

---

## 1. Optional: Clean Up 4 Failing Thunderbolt ML Tests

**Objective**: Get Thunderbolt ML suite to 100% green before adding ThunderPrism layer.

**Current Status**: 147 tests, 4 failures (KerasONNX related)

### Tasks

```bash
# Run ML test suite
mix test test/thunderline/thunderbolt/ml --seed 0
```

For each of the 4 failing tests:

1. **Identify failure type**:
   - Real bug (bad shape, missing config, wrong path)?
   - Fixture/config drift (wrong expectations, missing test asset)?

2. **Fix with minimal surface area**:
   - Config/fixture issue → Update tests or test helpers
   - Genuine runtime bug → Fix code + add guards

**Acceptance**:
- ✅ `mix test test/thunderline/thunderbolt/ml` → All passing
- ✅ No new dependencies added
- ✅ Fixes are minimal and scoped

---

## 2. New Work: ThunderPrism DAG Scratchpad

### 2.1. Domain & Resources

**Create**: `lib/thunderline/thunderprism/domain.ex`

```elixir
defmodule Thunderline.Thunderprism.Domain do
  use Ash.Domain

  resources do
    resource Thunderline.Thunderprism.PrismNode
    resource Thunderline.Thunderprism.PrismEdge
  end
end
```

#### PrismNode Resource

**File**: `lib/thunderline/thunderprism/prism_node.ex`

```elixir
defmodule Thunderline.Thunderprism.PrismNode do
  use Ash.Resource,
    domain: Thunderline.Thunderprism.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prism_nodes"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :pac_id, :string do
      allow_nil? false
      public? true
    end

    attribute :iteration, :integer do
      allow_nil? false
      public? true
    end

    attribute :chosen_model, :string do
      allow_nil? false
      public? true
    end

    # JSON blobs so we don't over-model early
    attribute :model_probabilities, :map do
      default %{}
      public? true
    end

    attribute :model_distances, :map do
      default %{}
      public? true
    end

    attribute :meta, :map do
      default %{}
      public? true
    end

    attribute :timestamp, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :out_edges, Thunderline.Thunderprism.PrismEdge do
      destination_attribute :from_id
      public? true
    end

    has_many :in_edges, Thunderline.Thunderprism.PrismEdge do
      destination_attribute :to_id
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :pac_id,
        :iteration,
        :chosen_model,
        :model_probabilities,
        :model_distances,
        :meta,
        :timestamp
      ]
    end

    update :update do
      accept [:meta, :model_probabilities, :model_distances]
    end
  end
end
```

#### PrismEdge Resource

**File**: `lib/thunderline/thunderprism/prism_edge.ex`

```elixir
defmodule Thunderline.Thunderprism.PrismEdge do
  use Ash.Resource,
    domain: Thunderline.Thunderprism.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prism_edges"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :from_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :to_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :relation_type, :string do
      allow_nil? false
      default "next"
      public? true
    end

    attribute :meta, :map do
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :from_node, Thunderline.Thunderprism.PrismNode do
      source_attribute :from_id
      public? true
    end

    belongs_to :to_node, Thunderline.Thunderprism.PrismNode do
      source_attribute :to_id
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:from_id, :to_id, :relation_type, :meta]
    end

    update :update do
      accept [:meta]
    end
  end
end
```

**Acceptance**:
- ✅ New domain compiled
- ✅ Run `mix ash_postgres.generate_migrations prism_tables`
- ✅ Migration generated for `prism_nodes` and `prism_edges` tables
- ✅ No overlap with Thunderbolt or Thundervine domains
- ✅ Run `mix ash.migrate` to apply migrations

---

### 2.2. HTTP API Layer

**File**: `lib/thunderline_web/controllers/thunderprism_controller.ex`

```elixir
defmodule ThunderlineWeb.ThunderprismController do
  use ThunderlineWeb, :controller

  action_fallback ThunderlineWeb.FallbackController

  @doc """
  POST /api/thunderprism/nodes
  Body: {pac_id, iteration, chosen_model, model_probabilities, model_distances, meta, timestamp}
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

  @doc """
  GET /api/thunderprism/nodes/:id
  """
  def get_node(conn, %{"id" => id}) do
    with {:ok, node} <-
           Thunderline.Thunderprism.PrismNode
           |> Ash.get(id, load: [:out_edges, :in_edges]) do
      json(conn, %{data: node})
    end
  end

  @doc """
  GET /api/thunderprism/graph?pac_id=...&limit=100
  Returns: {nodes: [...], links: [...]} for 3d-force-graph
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

  @doc """
  POST /api/thunderprism/edges
  Body: {from_id, to_id, relation_type, meta}
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

  @doc """
  GET /api/thunderprism/nodes/:id/edges
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
```

**Router Addition**: `lib/thunderline_web/router.ex`

```elixir
scope "/api/thunderprism", ThunderlineWeb do
  pipe_through :api

  post "/nodes", ThunderprismController, :create_node
  get "/nodes/:id", ThunderprismController, :get_node
  get "/graph", ThunderprismController, :get_graph
  
  post "/edges", ThunderprismController, :create_edge
  get "/nodes/:id/edges", ThunderprismController, :get_node_edges
end
```

**API Response Format** (for 3d-force-graph compatibility):

```json
GET /api/thunderprism/graph?pac_id=pac-1&limit=100

{
  "nodes": [
    {
      "id": "uuid-1",
      "pac_id": "pac-1",
      "iteration": 42,
      "chosen_model": "model_a",
      "meta": { "score": 0.95 }
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
```

**Acceptance**:
- ✅ All 5 endpoints work via `curl` or Postman
- ✅ `/graph` endpoint returns 3d-force-graph compatible format
- ✅ Node creation returns proper status codes
- ✅ Errors handled via FallbackController

---

### 2.3. Non-Blocking ML Hook (Feature-Gated)

**File**: `lib/thunderline/thunderprism/ml_tap.ex`

```elixir
defmodule Thunderline.Thunderprism.MLTap do
  @moduledoc """
  Non-blocking tap from Thunderbolt ML stack to ThunderPrism DAG.
  Records ML decision nodes for visualization and AI context.
  
  Feature-gated: only active when :enable_thunderprism is true.
  """

  require Logger

  @feature :enable_thunderprism

  @doc """
  Maybe record an ML decision node to ThunderPrism.
  Fire-and-forget: errors logged but don't block ML pipeline.
  
  Expected input from ML Controller/Consumer:
    %{
      pac_id: "pac-123",
      iteration: 42,
      chosen_model: "model_a",
      model_probs: %{model_a: 0.6, model_b: 0.3, model_c: 0.1},
      model_distances: %{model_a: 0.2, model_b: 0.5, model_c: 0.8},
      meta: %{...}
    }
  """
  def maybe_record(%{
        pac_id: pac_id,
        iteration: iteration,
        chosen_model: chosen_model,
        model_probs: probs,
        model_distances: distances
      } = data) do
    if Thunderline.Feature.enabled?(@feature) do
      # Fire-and-forget: don't block ML pipeline
      Task.start(fn ->
        try do
          meta = Map.get(data, :meta, %{})
          
          Thunderline.Thunderprism.PrismNode
          |> Ash.Changeset.for_create(:create, %{
            pac_id: pac_id,
            iteration: iteration,
            chosen_model: chosen_model,
            model_probabilities: probs,
            model_distances: distances,
            meta: meta,
            timestamp: DateTime.utc_now()
          })
          |> Ash.create()
        rescue
          error ->
            Logger.warning(
              "ThunderPrism MLTap failed (non-blocking): #{inspect(error)}"
            )
            :ok
        end
      end)
    end

    :ok
  end

  # Fallback for incomplete data
  def maybe_record(_data), do: :ok
end
```

**Integration Point**: In `Thunderline.Thunderbolt.ML.Controller` or `ModelSelectionConsumer`

**Example addition to Controller**:

```elixir
# After model selection logic
defp handle_selection_result(selection_result, state) do
  # Existing logic...
  
  # Non-blocking tap to ThunderPrism
  Thunderline.Thunderprism.MLTap.maybe_record(%{
    pac_id: selection_result.pac_id,
    iteration: selection_result.iteration,
    chosen_model: selection_result.chosen_model,
    model_probs: selection_result.model_probabilities,
    model_distances: selection_result.model_distances,
    meta: %{
      sla_target: state.sla_target,
      timestamp: DateTime.utc_now()
    }
  })
  
  # Continue existing logic...
end
```

**Feature Flag Configuration**: `config/dev.exs`

```elixir
config :thunderline, :features,
  enable_thunderprism: false  # Set to true to enable DAG recording
```

**Acceptance**:
- ✅ Feature flag defaults to `false`
- ✅ When enabled, ML decisions create PrismNode records
- ✅ Task runs async (fire-and-forget)
- ✅ Errors logged but don't crash ML pipeline
- ✅ When disabled, zero overhead (single boolean check)
- ✅ Integration point clearly documented

---

## 3. Guardrails / Explicit Don'ts

**For Phase 4.0, DO NOT**:

❌ **Change any existing Thundervine DAG or Thunderbit code**
   - Thundervine stays untouched until Phase 5+
   - No moving Thunderbolt ↔ Thundervine modules

❌ **Move Thunderbolt ML resources into Thundervine domain**
   - Keep domains cleanly separated
   - Thunderbolt = ML brain
   - Thunderprism = DAG scratchpad

❌ **Add PrismNode/PrismEdge to Thundervine or Thunderbolt domains**
   - ThunderPrism is its own domain
   - Resources registered only in `Thunderline.Thunderprism.Domain`

❌ **Make MLTap blocking or add retries**
   - Fire-and-forget only
   - Errors logged, not propagated
   - ML pipeline must never wait for Prism writes

**DO**:

✅ **Treat Thunderbolt as "ML brain"**
   - Parzen + SLA + Controller + Broadway
   - Existing logic untouched

✅ **Treat ThunderPrism as "DAG scratchpad / memory rails"**
   - Records ML decisions for visualization
   - Queryable by AI agents
   - Foundation for 3D force-graph later

✅ **Keep ThunderPrism feature-gated**
   - Easy to enable/disable
   - No impact on tests when off
   - Production can opt-in gradually

---

## 4. Testing Strategy

### 4.1. ThunderPrism Unit Tests

**File**: `test/thunderline/thunderprism/prism_node_test.exs`

```elixir
defmodule Thunderline.Thunderprism.PrismNodeTest do
  use Thunderline.DataCase

  describe "PrismNode creation" do
    test "creates node with required fields" do
      assert {:ok, node} =
               Thunderline.Thunderprism.PrismNode
               |> Ash.Changeset.for_create(:create, %{
                 pac_id: "pac-test-1",
                 iteration: 1,
                 chosen_model: "model_a",
                 timestamp: DateTime.utc_now()
               })
               |> Ash.create()

      assert node.pac_id == "pac-test-1"
      assert node.iteration == 1
      assert node.chosen_model == "model_a"
    end

    test "creates node with optional probabilities and distances" do
      assert {:ok, node} =
               Thunderline.Thunderprism.PrismNode
               |> Ash.Changeset.for_create(:create, %{
                 pac_id: "pac-test-2",
                 iteration: 2,
                 chosen_model: "model_b",
                 model_probabilities: %{model_a: 0.3, model_b: 0.7},
                 model_distances: %{model_a: 0.6, model_b: 0.2},
                 timestamp: DateTime.utc_now()
               })
               |> Ash.create()

      assert node.model_probabilities == %{model_a: 0.3, model_b: 0.7}
      assert node.model_distances == %{model_a: 0.6, model_b: 0.2}
    end
  end
end
```

**File**: `test/thunderline/thunderprism/ml_tap_test.exs`

```elixir
defmodule Thunderline.Thunderprism.MLTapTest do
  use Thunderline.DataCase
  
  alias Thunderline.Thunderprism.MLTap

  setup do
    # Enable feature for tests
    Application.put_env(:thunderline, :features, enable_thunderprism: true)
    
    on_exit(fn ->
      Application.put_env(:thunderline, :features, enable_thunderprism: false)
    end)
  end

  test "records ML decision when feature enabled" do
    data = %{
      pac_id: "tap-test-1",
      iteration: 5,
      chosen_model: "model_x",
      model_probs: %{model_x: 0.8},
      model_distances: %{model_x: 0.1}
    }

    assert :ok = MLTap.maybe_record(data)
    
    # Give async task time to complete
    Process.sleep(100)
    
    # Verify node was created
    {:ok, nodes} = Ash.read(Thunderline.Thunderprism.PrismNode)
    assert Enum.any?(nodes, &(&1.pac_id == "tap-test-1"))
  end

  test "returns :ok when feature disabled" do
    Application.put_env(:thunderline, :features, enable_thunderprism: false)
    
    data = %{
      pac_id: "disabled-test",
      iteration: 1,
      chosen_model: "model_y",
      model_probs: %{},
      model_distances: %{}
    }

    assert :ok = MLTap.maybe_record(data)
    
    # Verify no node was created
    {:ok, nodes} = Ash.read(Thunderline.Thunderprism.PrismNode)
    refute Enum.any?(nodes, &(&1.pac_id == "disabled-test"))
  end
end
```

### 4.2. API Integration Tests

**File**: `test/thunderline_web/controllers/thunderprism_controller_test.exs`

```elixir
defmodule ThunderlineWeb.ThunderprismControllerTest do
  use ThunderlineWeb.ConnCase

  describe "POST /api/thunderprism/nodes" do
    test "creates a new node", %{conn: conn} do
      params = %{
        pac_id: "api-test-1",
        iteration: 10,
        chosen_model: "model_z",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      conn = post(conn, ~p"/api/thunderprism/nodes", params)
      assert %{"data" => node} = json_response(conn, 201)
      assert node["pac_id"] == "api-test-1"
    end
  end

  describe "GET /api/thunderprism/graph" do
    test "returns graph structure", %{conn: conn} do
      # Create test nodes first
      # ...

      conn = get(conn, ~p"/api/thunderprism/graph?limit=10")
      assert %{"nodes" => nodes, "links" => links} = json_response(conn, 200)
      assert is_list(nodes)
      assert is_list(links)
    end
  end
end
```

**Acceptance**:
- ✅ All unit tests passing
- ✅ API integration tests passing
- ✅ Feature flag behavior verified
- ✅ Async behavior tested (with appropriate delays)

---

## 5. Deployment Checklist

### 5.1. Database Migration

```bash
# Generate migration
mix ash_postgres.generate_migrations prism_tables

# Review migration file
# Should create: prism_nodes, prism_edges tables with proper indexes

# Apply migration
mix ash.migrate
```

### 5.2. Configuration

**Production**: `config/prod.exs`

```elixir
# Keep disabled by default in production
config :thunderline, :features,
  enable_thunderprism: false
```

**Development**: `config/dev.exs`

```elixir
# Can enable for local testing
config :thunderline, :features,
  enable_thunderprism: true  # or false
```

**Environment Variable Override**: `config/runtime.exs`

```elixir
config :thunderline, :features,
  enable_thunderprism: System.get_env("ENABLE_THUNDERPRISM") == "true"
```

### 5.3. Monitoring

Add telemetry for ThunderPrism operations:

```elixir
# In MLTap.maybe_record/1
:telemetry.execute(
  [:thunderline, :thunderprism, :node, :recorded],
  %{count: 1},
  %{pac_id: pac_id, model: chosen_model}
)
```

**Acceptance**:
- ✅ Migrations applied in all environments
- ✅ Feature flag documented
- ✅ Telemetry events firing
- ✅ Logs show MLTap activity when enabled

---

## 6. Success Criteria

**Phase 4.0 is complete when**:

✅ **Pre-flight audit clean**:
- Zero old namespace references (`Thunderline.ML.*`, etc.)
- No double resource registrations
- No duplicate controllers/consumers

✅ **ThunderPrism domain live**:
- PrismNode and PrismEdge resources defined
- Migrations applied
- Domain registered separately from Thunderbolt/Thundervine

✅ **HTTP API functional**:
- All 5 endpoints working
- Graph endpoint returns 3d-force-graph compatible JSON
- Error handling via FallbackController

✅ **MLTap integrated**:
- Non-blocking calls from ML Controller/Consumer
- Feature-gated (defaults to disabled)
- Errors logged, don't crash pipeline

✅ **Tests passing**:
- Unit tests for PrismNode, PrismEdge
- API integration tests
- MLTap async behavior verified
- ML suite still 100% green (if optional cleanup done)

✅ **Documentation updated**:
- API endpoints documented
- Feature flag usage clear
- Integration points identified
- Guardrails respected (no Thundervine changes)

---

## 7. Next Steps (Post-Phase 4.0)

**Phase 5.0** (Future):
- 3D force-graph visualization frontend
- AI agent query interface for ThunderPrism
- Edge creation logic (connect sequential ML decisions)
- ThunderPrism → Thundervine integration (when both are stable)

**Immediate follow-up**:
- Monitor ThunderPrism performance in dev
- Collect sample DAG graphs for visualization design
- Document ML decision patterns visible in graph

---

## 8. Team Marching Orders

1. **Run pre-flight audit** (Section 0)
   - Verify no namespace pollution
   - Check for domain overlap
   - Confirm single ML controller/consumer

2. **(Optional) Fix 4 Thunderbolt ML test failures** (Section 1)
   - Get ML suite to 100% green
   - Recommended before layering ThunderPrism

3. **Implement ThunderPrism** (Section 2)
   - Create domain + resources
   - Build HTTP API
   - Add MLTap integration (feature-gated)

4. **Write tests** (Section 4)
   - Unit tests for resources
   - API integration tests
   - Feature flag behavior tests

5. **Deploy** (Section 5)
   - Apply migrations
   - Configure feature flags
   - Add monitoring/telemetry

**Remember**: Thunderbolt = ML brain. ThunderPrism = DAG scratchpad. Thundervine = untouched (for now). 🧠⚡🌿
