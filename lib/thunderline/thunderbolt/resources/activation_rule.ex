defmodule Thunderline.Thunderbolt.Resources.ActivationRule do
  @moduledoc """
  ActivationRule Resource - Neural activation patterns for Thunderbit meshes

  Defines ML-driven rules and neural patterns that determine when dormant
  Thunderbits should be activated. Maintains optimal distribution while
  optimizing for performance and energy efficiency using nx/axon integration.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource, AshOban.Resource, AshGraphql.Resource]
  import Ash.Resource.Change.Builtins
  import Ash.Resource.Change.Builtins


  # IN-MEMORY CONFIGURATION (sqlite removed)
  # Using :embedded data layer

  json_api do
    type "activation_rule"

    routes do
      base "/activation-rules"
      get :read
      index :read
      post :create
      patch :update
      delete :destroy
      patch :evaluate, route: "/:id/evaluate"
      patch :train, route: "/:id/train"
    end
  end

  attributes do
    uuid_primary_key :id

    # Rule metadata
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :rule_type, :atom, constraints: [
      one_of: [:energy_threshold, :signal_density, :neighbor_activity,
               :external_demand, :temporal_pattern, :ml_prediction, :hybrid]
    ], default: :energy_threshold

    # Rule configuration
    attribute :enabled, :boolean, default: true
    attribute :priority, :integer, default: 50  # 1-100, higher = more important
    attribute :trigger_conditions, :map, default: %{
      energy_min: 100,
      signal_count_min: 5,
      neighbor_active_count_min: 2
    }

    # ML and AI parameters
    attribute :ml_model_config, :map, default: %{
      algorithm: "decision_tree",
      features: ["energy", "signal_density", "neighbor_activity"],
      accuracy_threshold: 0.85
    }

    attribute :prediction_weights, :map, default: %{
      energy: 0.3,
      signals: 0.2,
      neighbors: 0.2,
      external: 0.2,
      temporal: 0.1
    }

    # Performance tracking
    attribute :activation_success_rate, :decimal, default: Decimal.new("0.0")
    attribute :false_positive_rate, :decimal, default: Decimal.new("0.0")
    attribute :avg_activation_time_ms, :decimal, default: Decimal.new("0.0")
    attribute :total_evaluations, :integer, default: 0
    attribute :successful_activations, :integer, default: 0

    # Constraints and limits
    attribute :max_activations_per_minute, :integer, default: 100
    attribute :cooldown_seconds, :integer, default: 30
    attribute :target_active_percentage, :decimal, default: Decimal.new("5.0")

    # Time-based patterns
    attribute :temporal_patterns, {:array, :map}, default: []
    attribute :last_evaluation, :utc_datetime
    attribute :last_training, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :chunk, Thunderline.Thunderbolt.Resources.Chunk do
      attribute_writable? true
    end

    has_many :orchestration_events, Thunderline.Thunderbolt.Resources.OrchestrationEvent
  end

  calculations do
    calculate :effectiveness_score, :decimal, expr(
      (activation_success_rate - false_positive_rate) * 100
    )

    calculate :is_due_for_training, :boolean, expr(
      is_nil(last_training) or
      last_training < ago(7, :day) or
      activation_success_rate < 0.8
    )

    calculate :activations_per_hour, :decimal, expr(
      if(total_evaluations > 0,
         successful_activations / (total_evaluations / 60.0),
         0)
    )
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :create_ml_rule do
      accept [
        :name, :description, :rule_type, :enabled, :priority,
        :trigger_conditions, :ml_model_config, :prediction_weights,
        :max_activations_per_minute, :target_active_percentage
      ]

      change before_action(&initialize_ml_model/1)
      change after_action(&register_for_evaluation/2)
    end

    update :evaluate do
      accept []
      argument :chunk_state, :map, allow_nil?: false
      argument :context_data, :map, default: %{}

      change before_action(&run_evaluation_logic/1)
      change after_action(&record_evaluation_result/2)
      change after_action(&create_orchestration_event/2)
    end

    update :train do
      accept []
      argument :training_data, {:array, :map}, allow_nil?: false

      change before_action(&execute_training_cycle/1)
      change set_attribute(:last_training, &DateTime.utc_now/0)
      change after_action(&validate_model_accuracy/2)
    end

    update :update_performance do
      accept [
        :activation_success_rate, :false_positive_rate,
        :avg_activation_time_ms, :total_evaluations, :successful_activations
      ]
      change after_action(&check_performance_thresholds/2)
    end

    read :active_rules do
      filter expr(enabled == true)
    end

    read :high_priority_rules do
      filter expr(enabled == true and priority > 70)
    end

    read :rules_needing_training do
      filter expr(is_due_for_training == true)
    end

    read :effective_rules do
      filter expr(effectiveness_score > 70)
    end

    read :rules_for_chunk do
      argument :chunk_id, :uuid, allow_nil?: false
      filter expr(chunk_id == ^arg(:chunk_id))
    end
  end

  # oban do
  #   triggers do
  #     # TODO: Fix schedule syntax for AshOban 3.x
  #     # trigger :evaluate_activation_rules do
  #     #   action :evaluate
  #     #   schedule "*/30 * * * * *"  # Every 30 seconds
  #     #   where expr(enabled == true)
  #     # end

  #     # trigger :retrain_models do
  #     #   action :train
  #     #   schedule "0 2 * * 0"  # Weekly at 2 AM on Sunday
  #     #   where expr(is_due_for_training == true)
  #     # end
  #   end
  # end

  # TODO: Configure notifications when proper extension is available
  # notifications do
  #   publish :rule_evaluated, ["thunderbolt:activation:evaluated", :id]
  #   publish :activation_triggered, ["thunderbolt:activation:triggered", :chunk_id]
  #   publish :model_retrained, ["thunderbolt:activation:retrained", :id]
  # end

  # Private action implementations
  defp initialize_ml_model(changeset) do
    # TODO: Initialize ML model based on configuration
    # For now, set up basic decision tree structure
    ml_config = Ash.Changeset.get_attribute(changeset, :ml_model_config)

    updated_config = Map.merge(ml_config, %{
      initialized_at: DateTime.utc_now(),
      model_id: Ecto.UUID.generate(),
      status: "initialized"
    })

    Ash.Changeset.change_attribute(changeset, :ml_model_config, updated_config)
  end

  defp register_for_evaluation(_changeset, rule) do
    # Register this rule with the activation intelligence system
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:activation:registry",
      {:rule_registered, rule}
    )
    {:ok, rule}
  end

  defp run_evaluation_logic(changeset) do
    # TODO: Implement sophisticated evaluation logic
    # This would analyze chunk state, context data, and apply ML models
    # For now, implement simple threshold-based logic

    changeset = Ash.Changeset.change_attribute(
      changeset,
      :last_evaluation,
      DateTime.utc_now()
    )

    # Increment evaluation counter
    current_evaluations = Ash.Changeset.get_attribute(changeset, :total_evaluations)
    Ash.Changeset.change_attribute(changeset, :total_evaluations, current_evaluations + 1)
  end

  defp record_evaluation_result(_changeset, rule) do
    # TODO: Record evaluation results for performance tracking
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:activation:result",
      {:evaluation_completed, rule.id, %{timestamp: DateTime.utc_now()}}
    )
    {:ok, rule}
  end

  defp create_orchestration_event(_changeset, rule) do
    # TODO: Create orchestration event record
    {:ok, rule}
  end

  defp execute_training_cycle(changeset) do
    # TODO: Implement ML training cycle using provided training data
    # Update model parameters, retrain algorithms, validate accuracy

    ml_config = Ash.Changeset.get_attribute(changeset, :ml_model_config)
    updated_config = Map.put(ml_config, :last_training, DateTime.utc_now())

    Ash.Changeset.change_attribute(changeset, :ml_model_config, updated_config)
  end

  defp validate_model_accuracy(_changeset, rule) do
    # TODO: Validate model accuracy against test data
    # If accuracy is below threshold, trigger retraining or rule adjustment
    {:ok, rule}
  end

  defp check_performance_thresholds(_changeset, rule) do
    # Check if performance has degraded and needs intervention
    if Decimal.lt?(rule.activation_success_rate, Decimal.new("0.7")) do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "thunderbolt:activation:alert",
        {:performance_degraded, rule}
      )
    end
    {:ok, rule}
  end
end
