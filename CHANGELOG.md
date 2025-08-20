# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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



