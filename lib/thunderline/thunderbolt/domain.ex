defmodule Thunderline.Thunderbolt.Domain do
  @moduledoc """
  ThunderBolt Ash Domain - Core Processing & Automation

  **Boundary**: "Make it run fast & right" - Raw compute, optimization, execution

  Consolidated from: ThunderCore, Thunder_Ising, ThunderLane, ThunderMag, ThunderCell

  ## Core Responsibilities:
  - Raw compute processing and optimization
  - Task execution and workflow orchestration
  - Lane processing and cellular topology management
  - Ising optimization and performance metrics
  - Macro command execution and task assignment
  - Erlang voxel automata and process grids
  """

  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshOban.Domain, AshJsonApi.Domain, AshGraphql.Domain]

  json_api do
    prefix "/api/thunderbolt"
    log_errors?(true)
  end

  graphql do
    authorize? false
  end

  resources do
    # ThunderCore → ThunderBolt (core processing)
    resource Thunderline.Thunderbolt.Resources.CoreAgent
    resource Thunderline.Thunderbolt.Resources.CoreSystemPolicy
    resource Thunderline.Thunderbolt.Resources.CoreTaskNode
    resource Thunderline.Thunderbolt.Resources.CoreTimingEvent
    resource Thunderline.Thunderbolt.Resources.CoreWorkflowDAG

    # Thunder_Ising → ThunderBolt (optimization)
    resource Thunderline.Thunderbolt.Resources.IsingOptimizationProblem
    resource Thunderline.Thunderbolt.Resources.IsingOptimizationRun
    resource Thunderline.Thunderbolt.Resources.IsingPerformanceMetric

    # ThunderLane → ThunderBolt (lane processing)
    resource Thunderline.Thunderbolt.Resources.CellTopology
    resource Thunderline.Thunderbolt.Resources.ConsensusRun
    resource Thunderline.Thunderbolt.Resources.CrossLaneCoupling
    resource Thunderline.Thunderbolt.Resources.LaneConfiguration
    resource Thunderline.Thunderbolt.Resources.LaneCoordinator
    resource Thunderline.Thunderbolt.Resources.LaneMetrics
    resource Thunderline.Thunderbolt.Resources.PerformanceMetric
    resource Thunderline.Thunderbolt.Resources.RuleOracle
    resource Thunderline.Thunderbolt.Resources.RuleSet
    resource Thunderline.Thunderbolt.Resources.TelemetrySnapshot

    # ThunderMag → ThunderBolt (task execution)
    resource Thunderline.Thunderbolt.Resources.MagMacroCommand
    resource Thunderline.Thunderbolt.Resources.MagTaskAssignment
    resource Thunderline.Thunderbolt.Resources.MagTaskExecution
  end
end
