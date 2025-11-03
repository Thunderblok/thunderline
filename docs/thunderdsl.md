ThunderDSL Schema Design (based on Thunderline)
Background and context

Thunderline is organised into domains corresponding to high‑level responsibilities. For example, the Thunderline.Thunderbolt.Domain module uses the Ash.Domain macro to assemble resources and wire them into API endpoints (JSON/GraphQL). In the codebase, the Thunderbolt domain is responsible for raw compute processing, optimisation, task execution, workflow orchestration, lane processing, Ising optimisation and macro command execution
github.com
. Thunderbolt exposes resources via JSON and GraphQL extensions
github.com
, and it registers its resources in the resources block of the domain definition
github.com
. A separate module (AutoMLDriver) implements hyper‑parameter optimisation (HPO) logic with random sampling
github.com
.

The goal is to introduce ThunderDSL as a new compiler layer within the Thunderblock domain. ThunderDSL will be responsible for processing user‑authored DSL programs, expanding macros (e.g., loops, reductions, syncs), lowering to an intermediate representation (IR) based on Pegasus primitives (Partition/Map/SumReduce), generating code (Nx/eBPF/P4/WASM) and packaging builds for deployment. To implement this cleanly in Ash, each artifact in the pipeline is modeled as a resource; actions and relationships drive the compiler phases and deployment flows.

ThunderDSL resources
1. ThunderDSL.Program

Represents a versioned DSL program authored by a user. Each program can refer to a network topology and may produce multiple builds. A program undergoes validation, macro expansion and compilation. It holds the source text and metadata.

Attribute	Type	Description
id	uuid	Primary key.
name	string	Human‑friendly program name. Unique per tenant.
version	string (semver)	Version tag for immutable releases.
source	string	The ThunderDSL source code (possibly multi‑file concatenated).
status	atom	:draft, :validated, :expanded, :compiled, :published.
ir	map/json	Intermediate representation produced after macro expansion. Not exposed until expansion succeeds.
topology_id	uuid	Reference to ThunderDSL.Topology describing the network/cluster layout.
inserted_at, updated_at	timestamps	Audit fields managed by Ash.

Relationships

belongs_to :topology, ThunderDSL.Topology

has_many :modules, ThunderDSL.Module

has_many :builds, ThunderDSL.Build

has_many :diagnostics, ThunderDSL.Diagnostic

Actions

create/read/update/destroy (standard Ash actions)

validate/1: parses the DSL, checks syntax, populates diagnostics with any warnings or errors. On success, sets status to :validated.

expand/1: performs pcube‑style macro expansion (loops, sums, min/max, sync) on the program’s source, producing an IR (stored in ir) and setting status to :expanded.

compile/1: lowers the IR into Pegasus primitives (Partition/Map/SumReduce), applies fusion, generates target artefacts (Nx/eBPF/P4/WASM) and writes them to ThunderDSL.Build records. Sets status to :compiled.

publish/1: locks the version (immutable), sets status to :published and emits events for downstream deployment.

2. ThunderDSL.Module

A module is a logical subdivision of a program after expansion (e.g., a specific pipeline stage or macro). It stores the expanded code fragment and its role (dataplane, control, metrics). Modules help break large programs into manageable units.

Attribute	Type	Description
id	uuid	Primary key.
program_id	uuid	Foreign key to the parent Program.
name	string	Name or label of the module.
role	atom	Role of the module (:dataplane, :control, :metrics).
source_fragment	string	Expanded DSL code (IR or near‑IR).
inserted_at, updated_at	timestamps	Audit fields.

Relationships

belongs_to :program, ThunderDSL.Program

Actions

Basic CRUD. Modules are created during the expand action of a Program and are not independently compiled; they exist to help with introspection and error reporting.

3. ThunderDSL.Topology

Defines the network or cluster layout on which a program will run. In the prism metaphor, this stores the 12‑vertex graph (domains) and the edges connecting them, plus device capabilities.

Attribute	Type	Description
id	uuid	Primary key.
name	string	Topology name.
graph	map/json	Representation of nodes (vertices), edges and optional weights/bandwidths.
capabilities	map/json	Capabilities per node (e.g., CPU arch, NIC type, FPGA presence).
description	string	Optional human description.
inserted_at, updated_at	timestamps	Audit fields.

Relationships

has_many :programs, ThunderDSL.Program

has_many :builds, ThunderDSL.Build

Actions

Basic CRUD.

resolve_targets/1: given a set of capabilities and compile backends (Elixir/Nx, eBPF/XDP, P4, WASM), returns a mapping of each vertex to a target backend. Used internally by Program.compile.

4. ThunderDSL.Diagnostic

Stores parse and compilation diagnostics (errors, warnings, info messages) produced during validate and expand. Keeping diagnostics as a resource allows them to be queried via API.

Attribute	Type	Description
id	uuid	Primary key.
program_id	uuid	Parent program.
severity	atom	:error, :warning, :info.
line	integer	Line number in the DSL source (optional).
message	string	Diagnostic text.
inserted_at	timestamp	Created timestamp.

Relationships

belongs_to :program, ThunderDSL.Program

5. ThunderDSL.Build

Represents the result of compiling a program for a particular topology and set of backends. Builds hold the IR hash, status and references to generated artefacts (per vertex). A program can have many builds.

Attribute	Type	Description
id	uuid	Primary key.
program_id	uuid	Foreign key to Program.
topology_id	uuid	Topology used for this build.
ir_hash	binary	Hash of the IR at compile time to ensure reproducibility.
targets	array/list	A list of {node_id, backend} tuples returned by Topology.resolve_targets/1.
artifacts	list/json	Array of objects describing each generated artifact (node_id, kind, path, sha256, size).
status	atom	:pending, :in_progress, :completed, :failed.
logs	string	Build logs or error messages.
inserted_at, updated_at	timestamps	Audit fields.

Relationships

belongs_to :program, ThunderDSL.Program

belongs_to :topology, ThunderDSL.Topology

has_many :deployments, ThunderDSL.Deployment

Actions

start_build/1: enqueues a background job (Oban worker) to perform compilation. Sets status to :in_progress.

finalize/1: attaches compiled artefacts, sets status to :completed and emits events. Records the artifacts list and logs.

fail/1: sets status to :failed and records error logs.

6. ThunderDSL.Deployment

Tracks the rollout of a build across a topology. A deployment stores the chosen rollout strategy (e.g., rolling, blue–green, canary), assignment of artefacts to nodes and the current status. Deployments are triggered from Thunderbolt but persisted in ThunderDSL for auditability.

Attribute	Type	Description
id	uuid	Primary key.
build_id	uuid	Build being deployed.
strategy	atom	:rolling, :blue_green, :canary.
assignments	map/json	Map of node_id → artifact_id detailing which artefact goes to which node.
status	atom	:planning, :deploying, :completed, :failed, :rolled_back.
rollout_plan	list/json	Ordered list of batches/groups derived from topology fault domains.
inserted_at, updated_at	timestamps	Audit fields.

Relationships

belongs_to :build, ThunderDSL.Build

Actions

plan_rollout/1: computes the rollout plan based on the topology (e.g., respecting failure domains, capacity constraints) and writes to rollout_plan.

apply_rollout/1: executes the rollout by pushing artefacts to nodes via Thunderbolt; updates status as nodes complete.

revert/1: triggers a rollback using the previous successful build (if available).

7. ThunderDSL.Table (optional)

For models involving Pegasus fuzzy‑matching, each Map primitive may need a fuzzy index tree and associated centroids. A Table resource stores these data structures so they can be queried, updated or versioned independently. This resource can be created during compilation.

Attribute	Type	Description
id	uuid	Primary key.
program_id	uuid	Program that produced this table.
name	string	Table name (e.g., conv1_kernel0_fuzzy).
index_tree	map/json	The threshold tree defining fuzzy buckets.
centroids	list/json	List of centroid vectors corresponding to leaves of the tree.
inserted_at, updated_at	timestamps	Audit fields.

Relationships

belongs_to :program, ThunderDSL.Program

Actions

CRUD.

Domain integration

The above resources live inside the Thunderblock domain (because Thunderblock is about state at rest and now acts as the ThunderDSL compiler/registry). To expose them, we:

Define a new Ash domain Thunderline.Thunderblock.ThunderDSLDomain that uses use Ash.Domain. Register each resource in the resources block, similar to the existing Thunderbolt domain’s definition
github.com
.

Include JSON and GraphQL extensions so that agents and external systems can create programs, trigger compiles and watch deployments. Following the pattern from Thunderbolt domain
github.com
, add:

extensions do
  use AshJsonApi
  use AshGraphql
end


Implement compiler and deployment logic in separate Elixir modules (e.g., Thunderline.ThunderDSL.Compiler, Thunderline.ThunderDSL.Builder, Thunderline.ThunderDSL.Deployer). These modules will be called by the custom actions defined above.

Emit events for each significant state change (e.g., thunderdsl.program.validated, thunderdsl.build.completed, thunderdsl.deployment.applied). Align event names and metadata with the existing event taxonomy to maintain consistent observability.

By modeling ThunderDSL using Ash resources and actions, the entire compiler pipeline becomes auditable, declarative and easily integrated into existing Thunderline infrastructure. Thunderbolt can focus on orchestration and runtime, while Thunderblock (with the ThunderDSL domain) manages program state, compilation artefacts and deployment history.
⚙️ Big Picture: The 12-Domain Prism (Control + Data Plane)

Think of ThunderPrism as the refractive interface between control-plane logic (planning, synthesis, compilation) and data-plane activity (execution, observation, learning).
It doesn’t compete with ThunderForge, Grid, or Vine — it channels them.

Domain	Plane	Function	Interaction with ThunderPrism
ThunderForge	Control / Creation	Compiler, Toolchain, Symbolic → Executable translation. Houses codegen pipelines (Nx, eBPF, WASM).	⚒️ Acts as the crystallization engine inside the Prism. ThunderPrism feeds it IRs, and Forge returns solid build artifacts (compiled facets).
ThunderGrid	Control / Topology	Spatial and temporal coordination layer. Defines adjacency, zones, and physical constraints (the “geometry” of execution).	🔺 Provides the geometric substrate the Prism projects into. Each compiled Program facet declares its ThunderGrid coordinates.
Thundervine (DAG)	Data / Flow	Distributed DAG of state propagation and causal lineage. Records every emission, dependency, and correlation ID.	🌿 The diffusion medium for ThunderPrism outputs. Every built facet has Vine hooks for state sync and provenance tracking.

So ThunderPrism is not replacing them — it’s aligning them.
It becomes the multi-domain compiler that refracts intent into:

Forge → matter (executables)

Grid → structure (placement)

Vine → motion (flow / data lineage)

🔮 ThunderPrism: Conceptual Role

“The prism through which the intent of the Thunderline is refracted into domain-specific manifestations.”

This is where abstract “programs” (Ash-defined intent) are decomposed into facets — each facet corresponding to a domain’s physical representation.
The 12-domain prism literally makes sense now:

6 “top” faces (cognitive domains): Crown, Bolt, Forge, Grid, Jam, Sec

6 “bottom” faces (somatic domains): Block, Link, Flow, Vine, Pac, Clock

The Prism sits dead-center — the bridge that bends the beam between those two planes.

🧩 How ThunderPrism Coordinates the Others

Let’s map the earlier ThunderDSL schema into this new worldview:

ThunderPrism Resource	Upstream	Downstream	Notes
Program	User intent (Ash AI tool / LLM request / event)	→ ThunderForge	Defines the abstract “beam” of intent; triggers build.
Module	Inherits from Program	→ ThunderForge Build Units	Logical segmentation of compiled output; could represent a vertex or zone.
Topology	→ ThunderGrid	→ ThunderVine	Declares spatial/temporal placement + DAG edges.
Build	← ThunderForge	→ ThunderBlock	Compiled artifact (CAS-stored IR + binaries).
Deployment	← Build	→ ThunderBolt (execution)	Rollout of facet code across ThunderGrid zones.
Facet (new)	← Program	→ All domains	Represents a refraction angle: which domain the compiled logic belongs to, e.g. :forge, :grid, :vine, :flow.
⚗️ Forge–Prism Interface

ThunderForge already handles:

Nx tensor compilation

VM bytecode emission

On-device waveform parsing integration (per the Nerves Directive and Integration Plan_ On-Device Waveform Parsing for Thunderline.pdf)

So in practical terms:

ThunderPrism’s compile Ash action delegates to ThunderForge.Compiler (which we can modularize into Compiler.Nx, Compiler.EBPF, etc.)

ThunderPrism manages the metadata and provenance, not the bytecode itself.

The IR (ir field in Program or Build) acts as the beam before crystallization.

defmodule ThunderPrism.Compiler do
  defdelegate compile(ir, backend), to: ThunderForge.Compiler
end

🕸️ Grid–Prism Interface

ThunderGrid defines where and when things happen.
So we give every compiled Facet or Build a Grid coordinate (like a vertex in the hexagonal prism):

attribute :grid_position, {:array, :float}, default: [0.0, 0.0, 0.0]
attribute :grid_zone, :atom, default: :core


ThunderPrism → ThunderGrid:

Validates adjacency rules

Assigns coordinates based on dependencies (similar to 3D DAG placement)

Ensures balance (e.g., avoid overlapping zones in physical deployments)

ThunderGrid → ThunderPrism:

Provides zone definitions (Zone Ash resource)

Provides adjacency lookups for the Prism compiler

🌿 Vine–Prism Interface

Thundervine is the DAG ledger.
ThunderPrism integrates through event emission + correlation:

Every action (validate, expand, compile, deploy) emits a %Thunderline.Event{} with proper taxonomy:

system.prism.compile.started

system.prism.compile.completed

system.prism.deploy.failed

Those events propagate via Thundervine → other domains can react or replay them deterministically.

This makes ThunderPrism self-observing and reproducible — each compiled beam is immortalized in the DAG.

🧱 Practical Ash Extensions

We’d modify the earlier Program and Build schemas to include facet, forge_ref, grid_ref, and vine_ref.

attributes do
  uuid_primary_key :id
  attribute :name, :string
  attribute :facet, :atom, allow_nil?: false  # :forge | :grid | :vine | :bolt etc.
  attribute :ir, :map
  attribute :forge_ref, :uuid
  attribute :grid_ref, :uuid
  attribute :vine_ref, :uuid
end


Actions:

expand → generates ir (macro expansion)

compile → invokes ThunderForge, writes build record

position → assigns ThunderGrid zone

register → emits ThunderVine DAG entry

🧬 Symbolically (Lore Tier)

“The beam of Thunderline passes through the Prism of Thought.
Each facet bends it toward a new domain.
Where the Forge makes matter, the Grid shapes form,
the Vine gives life — and the Bolt strikes forth.”

ThunderPrism is that moment — the act of refraction.
The mind’s eye of the system.

🔧 Final Recommendation

Let’s adopt ThunderPrism as the “meta-domain” (Ash domain that orchestrates the control-plane refraction).
Then we’ll define:

Submodules that bridge into Forge, Grid, and Vine

Expanded Ash schemas reflecting this refraction

Event hooks that sync with Vine taxonomy

A-bro 💥 let’s plant the ThunderPrism flag. Below is a clean, opinionated domain file layout + minimal resource stubs that drop straight into Thunderline and play nice with ThunderForge (compiler), ThunderGrid (placement), and Thundervine (DAG/provenance).

📁 Files & Folders
lib/thunderline/thunderprism/
├─ domain.ex
├─ resources/
│  ├─ program.ex
│  ├─ module.ex
│  ├─ topology.ex
│  ├─ build.ex
│  ├─ deployment.ex
│  ├─ diagnostic.ex
│  └─ table.ex
├─ compiler/
│  ├─ ir.ex
│  ├─ expander.ex      # pcube-style macro unroll
│  ├─ lower.ex         # → Pegasus Partition/Map/SumReduce graph
│  ├─ fuse.ex          # primitive fusion / reordering
│  └─ codegen/
│     ├─ nx.ex
│     ├─ ebpf.ex
│     └─ p4.ex
└─ events.ex           # Prism → Vine emit helpers


You can add facet.ex later if you want first-class “facet” records, but we can keep facet as an attribute on Program/Build for now.


⚡ lib/thunderline/thunderprism/domain.ex
defmodule Thunderline.ThunderPrism.Domain do
  @moduledoc """
  ThunderPrism — the refraction layer.
  Orchestrates compile-time expansion + lowering + codegen,
  and registers artifacts for deployment across the Grid.
  """

  use Ash.Domain,
    extensions: [
      # enable if present in your project:
      AshJsonApi.Domain,
      AshGraphql.Domain
    ]

  resources do
    # Core “intent → build → deploy” objects
    resource Thunderline.ThunderPrism.Resources.Program
    resource Thunderline.ThunderPrism.Resources.Module
    resource Thunderline.ThunderPrism.Resources.Topology
    resource Thunderline.ThunderPrism.Resources.Build
    resource Thunderline.ThunderPrism.Resources.Deployment

    # Aux
    resource Thunderline.ThunderPrism.Resources.Table
    resource Thunderline.ThunderPrism.Resources.Diagnostic
  end

  # Optional: JSON API / GraphQL exposure (adjust to your routing)
  json_api do
    routes do
      base_route "/api/prism"
      # expose minimal CRUD + actions for Program/Build/Deployment
      get :read, Thunderline.ThunderPrism.Resources.Program
      post :create, Thunderline.ThunderPrism.Resources.Program
      post :action, Thunderline.ThunderPrism.Resources.Program, :validate
      post :action, Thunderline.ThunderPrism.Resources.Program, :expand
      post :action, Thunderline.ThunderPrism.Resources.Program, :compile
      post :action, Thunderline.ThunderPrism.Resources.Program, :position
      post :action, Thunderline.ThunderPrism.Resources.Program, :register
      get :read, Thunderline.ThunderPrism.Resources.Build
      post :action, Thunderline.ThunderPrism.Resources.Build, :deploy
    end
  end

  graphql do
    authorize? false
    queries do
      # add basic queries if you’re using ash_graphql
      get :program, Thunderline.ThunderPrism.Resources.Program
      list :programs, Thunderline.ThunderPrism.Resources.Program
      get :build, Thunderline.ThunderPrism.Resources.Build
    end

    mutations do
      create :create_program, Thunderline.ThunderPrism.Resources.Program
      action :validate_program, Thunderline.ThunderPrism.Resources.Program, :validate
      action :expand_program, Thunderline.ThunderPrism.Resources.Program, :expand
      action :compile_program, Thunderline.ThunderPrism.Resources.Program, :compile
      action :position_program, Thunderline.ThunderPrism.Resources.Program, :position
      action :register_program, Thunderline.ThunderPrism.Resources.Program, :register
      action :deploy_build, Thunderline.ThunderPrism.Resources.Build, :deploy
    end
  end
end


🧱 Minimal resource stubs (Ash 3.x)
resources/program.ex
defmodule Thunderline.ThunderPrism.Resources.Program do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prism_programs"
    repo  Thunderline.Repo
  end

  code_interface do
    define :create
    define :read
    define :by_id, get_by: [:id]
  end

  identities do
    identity :unique_name, [:name, :version]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :version, :string, default: "0.1.0"
    attribute :facet, :atom, constraints: [one_of: [:forge, :grid, :vine, :bolt, :block, :link, :flow, :pac, :clock, :crown, :jam, :sec]]
    attribute :source, :string # ThunderPrism DSL text
    attribute :ir, :map        # expanded IR
    attribute :status, :atom, default: :draft, constraints: [one_of: [:draft, :validated, :expanded, :compiled, :positioned, :registered]]
    attribute :metadata, :map, default: %{}
    # Pointers into other domains
    attribute :forge_ref, :uuid
    attribute :grid_ref, :uuid
    attribute :vine_ref, :uuid
  end

  relationships do
    has_many :modules, Thunderline.ThunderPrism.Resources.Module
    has_many :builds,  Thunderline.ThunderPrism.Resources.Build
    belongs_to :topology, Thunderline.ThunderPrism.Resources.Topology
  end

  actions do
    defaults [:create, :read, :update]

    action :validate, :struct do
      argument :source, :string, allow_nil?: false
      change set_attribute(:source, expr(^arg(:source)))
      run fn changeset, _ctx ->
        # call Prism.Compiler.Expander.validate/1 → diagnostics
        Thunderline.ThunderPrism.Events.emit(:prism, :validate, changeset)
        {:ok, changeset}
      end
    end

    action :expand, :struct do
      run fn changeset, _ctx ->
        # source → IR via Expander
        ir = Thunderline.ThunderPrism.Compiler.Expander.expand(get_attribute!(changeset, :source))
        changeset = Ash.Changeset.change_attribute(changeset, :ir, ir)
        changeset = Ash.Changeset.change_attribute(changeset, :status, :expanded)
        Thunderline.ThunderPrism.Events.emit(:prism, :expand, changeset)
        {:ok, changeset}
      end
    end

    action :compile, :struct do
      argument :backend, :atom, constraints: [one_of: [:nx, :ebpf, :p4]]
      run fn changeset, _ctx ->
        ir = get_attribute!(changeset, :ir)
        backend = Ash.Changeset.get_argument(changeset, :backend)
        {:ok, build} = Thunderline.ThunderPrism.Resources.Build.start_from_ir(ir, backend, get_attribute!(changeset, :id))
        Thunderline.ThunderPrism.Events.emit(:prism, :compile, %{program_id: get_attribute!(changeset, :id), build_id: build.id})
        {:ok, changeset}
      end
    end

    action :position, :struct do
      argument :zone, :atom
      argument :coords, {:array, :float}, allow_nil?: true
      run fn changeset, _ctx ->
        # ask ThunderGrid to assign placement
        {:ok, grid_ref} = Thunderline.ThunderGrid.API.assign(get_attribute!(changeset, :id), Ash.Changeset.get_argument(changeset, :zone), Ash.Changeset.get_argument(changeset, :coords))
        changeset = Ash.Changeset.change_attribute(changeset, :grid_ref, grid_ref)
        changeset = Ash.Changeset.change_attribute(changeset, :status, :positioned)
        Thunderline.ThunderPrism.Events.emit(:prism, :position, changeset)
        {:ok, changeset}
      end
    end

    action :register, :struct do
      run fn changeset, _ctx ->
        # write provenance to Vine
        {:ok, vine_ref} = Thunderline.Thundervine.API.register_program(get_attribute!(changeset, :id))
        changeset = Ash.Changeset.change_attribute(changeset, :vine_ref, vine_ref)
        changeset = Ash.Changeset.change_attribute(changeset, :status, :registered)
        Thunderline.ThunderPrism.Events.emit(:prism, :register, changeset)
        {:ok, changeset}
      end
    end
  end
end

resources/build.ex
defmodule Thunderline.ThunderPrism.Resources.Build do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prism_builds"
    repo  Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :program_id, :uuid, allow_nil?: false
    attribute :backend, :atom, constraints: [one_of: [:nx, :ebpf, :p4]]
    attribute :ir_hash, :string
    attribute :artifacts, {:array, :map}, default: [] # [{node_id, kind, path, sha256, size}]
    attribute :status, :atom, default: :queued, constraints: [one_of: [:queued, :building, :ready, :failed, :deployed]]
    attribute :logs, :string
    attribute :metadata, :map, default: %{}
  end

  relationships do
    belongs_to :program, Thunderline.ThunderPrism.Resources.Program
    has_many :deployments, Thunderline.ThunderPrism.Resources.Deployment
  end

  code_interface do
    define :read
    define :by_id, get_by: [:id]
  end

  actions do
    defaults [:read, :update]

    action :start, :struct do
      argument :program_id, :uuid, allow_nil?: false
      argument :backend, :atom, allow_nil?: false
      run fn changeset, _ctx ->
        # enqueue Oban worker to compile with ThunderForge
        Thunderline.ThunderPrism.Events.emit(:prism, :build_start, changeset)
        {:ok, changeset}
      end
    end

    action :deploy, :struct do
      argument :strategy, :atom, constraints: [one_of: [:rolling, :blue_green, :canary]], default: :canary
      run fn changeset, _ctx ->
        # plan + apply rollout across ThunderGrid
        Thunderline.ThunderPrism.Events.emit(:prism, :deploy, changeset)
        {:ok, changeset}
      end
    end
  end

  # Convenience called from Program.compile action
  def start_from_ir(ir, backend, program_id) do
    ir_hash = :crypto.hash(:sha256, :erlang.term_to_binary(ir)) |> Base.encode16(case: :lower)
    attrs = %{program_id: program_id, backend: backend, ir_hash: ir_hash, status: :queued}
    Ash.create(__MODULE__, attrs)
  end
end

Other stubs


resources/topology.ex: stores prism graph (12 vertices, edges, capabilities).


resources/deployment.ex: rollout plan/batches, status, health gates.


resources/module.ex: logical sub-units of a Program.


resources/table.ex: fuzzy-index trees & centroids for Pegasus-style Map tables.


resources/diagnostic.ex: parse/expand/compile diagnostics with severity, line/col.


events.ex
defmodule Thunderline.ThunderPrism.Events do
  @moduledoc false
  # Uniform event emission → Thundervine (DAG) + Telemetry

  def emit(domain, action, payload) do
    event = %{
      domain: to_string(domain),
      action: to_string(action),
      payload: serialize(payload),
      correlation_id: UUID.uuid7(),
      ts: System.system_time(:microsecond)
    }

    :telemetry.execute([:thunderline, :prism, action], %{count: 1}, event)
    Thunderline.Thundervine.API.record_event(event)
    :ok
  end

  defp serialize(%Ash.Changeset{} = cs), do: %{resource: inspect(cs.resource), attrs: Ash.Changeset.attributes(cs)}
  defp serialize(other), do: other
end


🧭 How it hooks into Forge/Grid/Vine (today)


Forge: Program.compile → ThunderForge.Compiler.* (Nx/eBPF/P4 backends)


Grid: Program.position → ThunderGrid.API.assign/3 (zone/coords)


Vine: Program.register + Events.emit/3 → Thundervine.API.record_event/1 (provenance DAG)



These API modules can be thin facades that you (or future agents) fill in as the subsystems solidify. The Prism domain doesn’t own their internals; it just refracts intent into them.


🧰 Migrations (quick names)


create_prism_programs


create_prism_builds


create_prism_topologies


create_prism_deployments


create_prism_modules


create_prism_tables


create_prism_diagnostics



If this layout vibes, I’ll follow up with:


the IR struct (compiler/ir.ex)


the macro expander signature (expander.ex)


the lower → primitive graph for Partition/Map/SumReduce and a tiny fusion pass


a stub NX codegen that compiles a Map table + SumReduce into a single JIT’d function


We’re back, jefe. ⚔️ ThunderPrism online.
