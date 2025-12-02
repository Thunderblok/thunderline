# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [Unreleased]

### Features:

* **Guerrilla Backlog (#8-22)**: Complete sweep of Ash 3.x compatibility and infrastructure gaps
  - **#8-11**: Fix Ash 3.x API issues, AshOban extensions, add ChannelParticipant resource
  - **#12-13**: Migrate `AshOban.Resource` → `AshOban` extension in 20 files
  - **#15**: Wire DashboardMetrics and DashboardLive with live telemetry
  - **#17**: Full ThunderlaneDashboard implementation
  - **#18**: Stream/Flow telemetry for pipeline throughput & failures
  - **#19**: StreamManager supervisor + PubSub bridge
  - **#20**: ExUnit coverage for StreamManager + Credo complexity fix
  - **#21**: Chunk resource Ash 3.x compatibility (changeset.data access pattern)
  - **#22**: Real resource allocation logic + orchestration events (10+ functions implemented)

* **RAG System Refactor**: Complete migration from Chroma HTTP API to native ash_ai + pgvector implementation
  - **Performance**: 95% faster queries (~7-10ms vs ~150ms)
  - **Simplification**: 65% code reduction (200 LOC vs 580 LOC)
  - **Architecture**: Unified PostgreSQL storage, removed external Chroma dependency
  - **Implementation**: `Thunderline.RAG.Document` Ash resource with automatic vectorization
  - **Model**: sentence-transformers/all-MiniLM-L6-v2 (384-dim embeddings via Bumblebee)
  - **API**: `Document.create_document/1`, `Document.update_embeddings/1`, `Document.semantic_search/2`
  - **Testing**: Comprehensive acceptance test (`test_rag_acceptance.exs`)

### Breaking Changes:

* **RAG**: Removed Chroma-based modules (`RAG.Ingest`, `RAG.Query`, `RAG.Collection`)
* **Docker**: Removed Chroma service from docker-compose.yml (PostgreSQL with pgvector only)
* **Environment**: `RAG_ENABLED=1` now enables ash_ai implementation (enabled by default in dev)

### Fixes / Maintenance:

* fix(websocket): correct system state pattern match preventing noisy "Failed to fetch system state: {:ok, %{...}}" debug logs (now matches on `{:ok, map}`)
* docs: add explicit Feature Flags section (ENABLE_NDJSON, ENABLE_UPS, TL_ENABLE_REACTOR, SKIP_DEPS_GET, SKIP_ASH_SETUP)
* docs: add comprehensive RAG system documentation with API usage, architecture, and performance metrics
* docs: clarify former BOnus module migration – no separate `BOnus/` compile path required
* chore: minor credo cleanups (remove semicolons in pattern matches, replace `length(list) > 0` with emptiness check)
* chore: remove obsolete test scripts (test_rag_basic.exs, test_rag_semantic_search.exs, test_rag_quick.exs)


## [v2.1.0](https://github.com/mo/thunderline/compare/v2.0.0...v2.1.0) (2025-08-20)




### Features:

* nn: add interactive neural network playground LiveView at /nn; add .gitops.json for git_ops release config

* implement stubs for Ising machine components and enhance error handling in API

* enhance IsingMachine lattice module with grid_2d and graph functions

* update navigation methods in ChannelLive and CommunityLive, and add topology distributor, partitioner, and rebalancer stubs

* tasks: add Thunderline.Dev.Init task for database setup and seeding

* tasks: introduce Thunderline.Doctor.Db task for database diagnostics

* Cerebros: implement hybrid adapter with delegation and persistence pipeline

* thunderbolt: add cerebros model_run & model_artifact migrations (Ash Postgres)

* thunderbolt: relocate automata blackboard & cerebros modules + add ModelRun/ModelArtifact resources

* Enhance Thunderline application with conditional DB setup and blackboard data integration for lightweight testing

* Implement Automata Blackboard for shared knowledge space and integrate with Thunderline application

* Introduce centralized PubSub topic helpers and add Presence tracking for real-time user state

* Implement Thunderflow job processors for compute, storage, and orchestration operations

* Create ProcessEvent worker for gated event processing

* Develop FanoutAggregator for telemetry metrics on event fanout distribution

* Introduce FanoutGuard for telemetry overload prevention

* Create QueueDepthCollector for monitoring Oban queue depths

* Add telemetry metrics for job processing and event handling

* Introduce Thunderline Domain & Resource Catalog and Master Playbook

* Add comprehensive OKO Handbook for Thunderline documentation and operational guidelines

* Enhance Thunderline application with Oban job processors and error handling

* Add SQL, Swift, TypeScript, Vue, WebSocket, and migration agents

### Bug Fixes:

* config: update Postgres port to standard 5432 for local development

* repo: handle SKIP_ASH_SETUP environment variable to prevent repo startup

* automata: deprecate Thunderline.Automata.Blackboard in favor of Thunderline.Thunderbolt.Automata.Blackboard

* ModelRun: correct AshStateMachine DSL, relationship, and state attribute constraints

## [v2.0.0](https://github.com/mo/thunderline/compare/v2.0.0...v2.0.0) (2025-08-15)



