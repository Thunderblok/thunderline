defmodule Thunderline.Thunderblock.Resources.VaultExperience do
  @moduledoc """
  Experience Resource - Consolidated from Thunderline.Memory.Experience

  Experience records - learning from agent actions and outcomes.
  Moved to Thundervault for unified memory and knowledge management.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  postgres do
    table "experiences"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :record_experience do
      description "Record a new experience for an agent"

      accept [
        :experience_type,
        :situation_context,
        :action_taken,
        :outcome,
        :lesson_learned,
        :impact_score,
        :surprise_factor,
        :difficulty_level,
        :emotions_felt,
        :skills_used,
        :environmental_factors
      ]

      argument :agent_id, :uuid do
        allow_nil? false
        description "ID of the agent having the experience"
      end

      argument :decision_id, :uuid do
        description "ID of the associated decision, if any"
      end

      argument :action_id, :uuid do
        description "ID of the associated action, if any"
      end

      change manage_relationship(:agent_id, :agent, type: :append_and_remove)

      change manage_relationship(:decision_id, :decision,
               type: :append_and_remove,
               on_no_match: :ignore
             )

      change manage_relationship(:action_id, :action,
               type: :append_and_remove,
               on_no_match: :ignore
             )

      change fn changeset, _context ->
        # Auto-calculate impact score based on surprise factor and outcome sentiment
        if Ash.Changeset.get_attribute(changeset, :impact_score) == 0.5 do
          surprise = Ash.Changeset.get_attribute(changeset, :surprise_factor) || 0.0
          # Simple heuristic - higher surprise generally means higher impact
          calculated_impact = min(1.0, 0.3 + surprise * 0.7)
          Ash.Changeset.change_attribute(changeset, :impact_score, calculated_impact)
        else
          changeset
        end
      end
    end

    update :reference_experience do
      description "Increment reference counter when experience is recalled"

      change fn changeset, _context ->
        current_count = Ash.Changeset.get_attribute(changeset, :times_referenced) || 0
        Ash.Changeset.change_attribute(changeset, :times_referenced, current_count + 1)
      end

      change fn changeset, _context ->
        # Strengthen learning based on repeated reference
        current_strength = Ash.Changeset.get_attribute(changeset, :learning_strength) || 1.0

        # 10% boost, capped at 1.0
        new_strength = min(1.0, current_strength * 1.1)
        Ash.Changeset.change_attribute(changeset, :learning_strength, new_strength)
      end

      require_atomic? false
    end

    update :reinforce_learning do
      description "Manually adjust learning strength based on outcomes"
      accept [:learning_strength, :lesson_learned]

      argument :reinforcement_factor, :float do
        description "Factor to adjust learning strength by (e.g., 1.2 for positive, 0.8 for negative)"
        constraints min: 0.1, max: 2.0
      end

      change fn changeset, _context ->
        factor = Ash.Changeset.get_argument(changeset, :reinforcement_factor) || 1.0
        current_strength = Ash.Changeset.get_attribute(changeset, :learning_strength) || 1.0
        new_strength = min(1.0, max(0.1, current_strength * factor))
        Ash.Changeset.change_attribute(changeset, :learning_strength, new_strength)
      end

      require_atomic? false
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate match(:situation_context, ~r/.{10,}/) do
      message "Situation context must be at least 10 characters"
    end

    validate match(:action_taken, ~r/.{5,}/) do
      message "Action taken must be at least 5 characters"
    end

    validate match(:outcome, ~r/.{5,}/) do
      message "Outcome must be at least 5 characters"
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :experience_type, :atom do
      allow_nil? false
      constraints one_of: [:success, :failure, :discovery, :interaction, :learning, :adaptation]
      description "Type of experience recorded"
    end

    attribute :situation_context, :string do
      allow_nil? false
      description "Context when experience occurred"
    end

    attribute :action_taken, :string do
      allow_nil? false
      description "What action was taken"
    end

    attribute :outcome, :string do
      allow_nil? false
      description "What happened as a result"
    end

    attribute :lesson_learned, :string do
      description "Key insight or lesson from this experience"
    end

    # Experience metrics
    attribute :impact_score, :float do
      default 0.5
      description "How impactful this experience was (0.0-1.0)"
    end

    attribute :surprise_factor, :float do
      default 0.0
      description "How unexpected the outcome was (0.0-1.0)"
    end

    attribute :difficulty_level, :integer do
      default 5
      constraints min: 1, max: 10
      description "Difficulty level 1-10"
    end

    # Learning reinforcement
    attribute :times_referenced, :integer do
      default 0
      description "How many times this experience has been referenced"
    end

    attribute :learning_strength, :float do
      default 1.0
      description "How well this lesson is learned (0.0-1.0)"
    end

    attribute :emotions_felt, {:array, :string} do
      default []
      description "Emotions associated with this experience"
    end

    attribute :skills_used, {:array, :string} do
      default []
      description "Skills or capabilities utilized"
    end

    attribute :environmental_factors, :map do
      default %{}
      description "Environmental context and factors"
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, Thunderline.Thunderblock.Resources.VaultAgent do
      allow_nil? false
      attribute_writable? true
      description "Agent that had this experience"
    end

    belongs_to :decision, Thunderline.Thunderblock.Resources.VaultDecision do
      allow_nil? true
      attribute_writable? true
      description "Associated decision, if any"
    end

    belongs_to :action, Thunderline.Thunderblock.Resources.VaultAction do
      allow_nil? true
      attribute_writable? true
      description "Associated action, if any"
    end
  end

  calculations do
    calculate :learning_score, :float, expr(impact_score * learning_strength) do
      description "Combined learning score considering impact and strength"
    end

    calculate :recall_frequency,
              :float,
              expr(
                times_referenced /
                  (fragment("EXTRACT(EPOCH FROM (NOW() - inserted_at)) / 86400") + 1)
              ) do
      description "How frequently this experience is recalled (references per day)"
    end
  end

  aggregates do
    count :total_experiences_by_agent, :agent do
      description "Total experiences for this agent"
    end
  end

  identities do
    identity :unique_experience_per_context, [
      :agent_id,
      :situation_context,
      :action_taken,
      :inserted_at
    ] do
      description "Prevent duplicate experiences with same context and action within the same timestamp"
    end
  end
end
