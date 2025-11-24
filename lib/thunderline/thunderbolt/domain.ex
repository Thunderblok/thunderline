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
    extensions: [AshAdmin.Domain, AshOban.Domain, AshJsonApi.Domain, AshGraphql.Domain]

  admin do
    show? true
  end

  json_api do
    prefix "/api/thunderbolt"
    log_errors? true
  end

  graphql do
    authorize? false

    queries do
      list Thunderline.Thunderbolt.Resources.CoreAgent, :core_agents, :read
      list Thunderline.Thunderbolt.Resources.CoreAgent, :active_core_agents, :active_agents
    end

    mutations do
      create Thunderline.Thunderbolt.Resources.CoreAgent, :register_core_agent, :register
      update Thunderline.Thunderbolt.Resources.CoreAgent, :heartbeat_core_agent, :heartbeat
    end
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

    # Automata controls (non-persistent control surface)
    resource Thunderline.Thunderbolt.Resources.AutomataRun
    resource Thunderline.Thunderbolt.Resources.Chunk
    resource Thunderline.Thunderbolt.Resources.ChunkHealth
    resource Thunderline.Thunderbolt.Resources.ActivationRule
    resource Thunderline.Thunderbolt.Resources.OrchestrationEvent

    # Cerebros (ML search & training)
    resource Thunderline.Thunderbolt.Resources.ModelRun
    resource Thunderline.Thunderbolt.Resources.ModelTrial

    # Cerebros Training Pipeline (new)
    resource Thunderline.Thunderbolt.Resources.TrainingDataset do
      define :create_training_dataset, action: :create
      define :update_training_dataset, action: :update
      define :update_corpus_path, action: :set_corpus_path, args: [:corpus_path]
      define :get_training_dataset, action: :read, get_by: [:id]
      define :list_training_datasets, action: :read
      define :freeze_dataset, action: :freeze
    end

    resource Thunderline.Thunderbolt.Resources.DocumentUpload do
      define :create_document_upload, action: :create
      define :list_document_uploads, action: :read
      define :process_upload, action: :mark_processed
    end

    resource Thunderline.Thunderbolt.Resources.CerebrosTrainingJob do
      define :create_training_job, action: :create
      define :get_training_job, action: :read, get_by: [:id]
      define :start_job, action: :start
      define :update_fine_tuned_model, action: :update_fine_tuned_model
      define :complete_job, action: :complete
      define :fail_job, action: :fail
      define :mark_model_loaded, action: :mark_model_loaded
    end

    # New ML stack resources

    # RAG (Retrieval Augmented Generation)
    resource Thunderline.Thunderbolt.RAG.Document
    resource Thunderline.Thunderbolt.ML.TrainingDataset
    resource Thunderline.Thunderbolt.ML.FeatureView
    resource Thunderline.Thunderbolt.ML.ConsentRecord
    resource Thunderline.Thunderbolt.ML.ModelSpec
    resource Thunderline.Thunderbolt.ML.ModelArtifact
    resource Thunderline.Thunderbolt.ML.ModelVersion
    resource Thunderline.Thunderbolt.ML.TrainingRun
    # MLflow integration resources
    resource Thunderline.Thunderbolt.MLflow.Experiment
    resource Thunderline.Thunderbolt.MLflow.Run

    # Unified Persistent Model (UPM)
    resource Thunderline.Thunderbolt.Resources.UpmTrainer
    resource Thunderline.Thunderbolt.Resources.UpmSnapshot
    resource Thunderline.Thunderbolt.Resources.UpmAdapter
    resource Thunderline.Thunderbolt.Resources.UpmDriftWindow

    # Phase 0 MoE + Decision trace resources
    resource Thunderline.MoE.Expert
    resource Thunderline.MoE.DecisionTrace
    # NAS export job & dataset slicing belongs with orchestration/ML side
    resource Thunderline.Export.TrainingSlice

    # ONNX Inference (MCP tool integration)
    resource Thunderline.Thunderbolt.Resources.OnnxInference do
      define :infer, action: :infer, args: [:model_path, :input, :metadata]
    end
  end
end
