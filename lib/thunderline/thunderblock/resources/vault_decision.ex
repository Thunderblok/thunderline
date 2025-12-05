defmodule Thunderline.Thunderblock.Resources.VaultDecision do
  @moduledoc """
  Decision Resource - Migrated from lib/thunderline/pac/resources/decision

  Agent decisions in the PAC (Perception-Action-Cognition) system.
  Records decision-making processes and outcomes for learning and analysis.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "decisions"
    repo Thunderline.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :make_decision do
      accept [
        :agent_id,
        :type,
        :context,
        :input_data,
        :options_considered,
        :selected_option,
        :reasoning,
        :confidence_score,
        :risk_assessment,
        :expected_outcome,
        :decision_time_ms,
        :tags,
        :parent_decision_id
      ]
    end

    update :record_outcome do
      accept [:actual_outcome, :was_successful]
      require_atomic? false

      change fn changeset, _context ->
        expected = Ash.Changeset.get_attribute(changeset, :expected_outcome)
        actual = changeset.arguments[:actual_outcome]

        if expected && actual do
          # Simple accuracy calculation based on shared keys
          accuracy = calculate_outcome_accuracy(expected, actual)
          Ash.Changeset.change_attribute(changeset, :outcome_accuracy, accuracy)
        else
          changeset
        end
      end
    end

    update :add_tags do
      argument :new_tags, {:array, :string}, allow_nil?: false
      require_atomic? false

      change fn changeset, context ->
        current_tags = Ash.Changeset.get_attribute(changeset, :tags) || []
        new_tags = context.arguments.new_tags || []
        updated_tags = Enum.uniq(current_tags ++ new_tags)
        Ash.Changeset.change_attribute(changeset, :tags, updated_tags)
      end
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
    end

    read :by_type do
      argument :type, :atom, allow_nil?: false
      filter expr(type == ^arg(:type))
    end

    read :by_confidence_range do
      argument :min_confidence, :decimal, allow_nil?: false
      argument :max_confidence, :decimal, allow_nil?: false

      filter expr(
               confidence_score >= ^arg(:min_confidence) and
                 confidence_score <= ^arg(:max_confidence)
             )
    end

    read :successful_decisions do
      filter expr(was_successful == true)
    end

    read :failed_decisions do
      filter expr(was_successful == false)
    end

    read :high_confidence do
      filter expr(confidence_score >= 0.8)
    end

    read :high_risk do
      filter expr(risk_assessment >= 0.7)
    end

    read :recent_decisions do
      argument :hours, :integer, default: 24
      filter expr(inserted_at > ago(^arg(:hours), :hour))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_tags do
      argument :tags, {:array, :string}, allow_nil?: false
      filter expr(exists(tags, ^arg(:tags)))
    end
  end

  # ===== POLICIES =====
  policies do
    # Bypass for AshAuthentication internal operations
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Read: Allow all authenticated users
    policy action_type(:read) do
      authorize_if actor_present()
    end

    # Create/Update: Require authenticated actor
    policy action_type([:create, :update]) do
      authorize_if actor_present()
    end

    # Destroy: Only owner (via agent relationship) or admin
    policy action_type(:destroy) do
      authorize_if relates_to_actor_via([:agent, :created_by_user])
      authorize_if expr(^actor(:role) == :admin)
    end
  end

  preparations do
    prepare build(load: [:agent])
  end

  validations do
    validate present([:agent_id, :type, :context, :selected_option])
    validate string_length(:context, min: 1, max: 200)

    validate numericality(:confidence_score,
               greater_than_or_equal_to: 0,
               less_than_or_equal_to: 1
             )

    validate numericality(:risk_assessment, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)

    validate numericality(:outcome_accuracy,
               greater_than_or_equal_to: 0,
               less_than_or_equal_to: 1
             ) do
      where present(:outcome_accuracy)
    end

    validate numericality(:decision_time_ms, greater_than_or_equal_to: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      allow_nil? false
      description "Type of decision made"
    end

    attribute :context, :string do
      allow_nil? false
      constraints max_length: 200
      description "Decision-making context description"
    end

    attribute :input_data, :map do
      allow_nil? false
      default %{}
      description "Input data used for decision-making"
    end

    attribute :options_considered, {:array, :map} do
      allow_nil? false
      default []
      description "List of options that were evaluated"
    end

    attribute :selected_option, :map do
      allow_nil? false
      description "The option that was chosen"
    end

    attribute :reasoning, :string do
      allow_nil? true
      description "Explanation of decision-making process"
    end

    attribute :confidence_score, :decimal do
      allow_nil? false
      default Decimal.new("0.5")
      constraints min: 0, max: 1
      description "Agent confidence in decision (0.0 to 1.0)"
    end

    attribute :risk_assessment, :decimal do
      allow_nil? false
      default Decimal.new("0.5")
      constraints min: 0, max: 1
      description "Assessed risk level (0.0 = low, 1.0 = high)"
    end

    attribute :expected_outcome, :map do
      allow_nil? true
      description "Expected result of the decision"
    end

    attribute :actual_outcome, :map do
      allow_nil? true
      description "Actual result after execution"
    end

    attribute :outcome_accuracy, :decimal do
      allow_nil? true
      constraints min: 0, max: 1
      description "How well expected matched actual outcome"
    end

    attribute :decision_time_ms, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Time taken to make decision (milliseconds)"
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      description "Tags for categorizing decisions"
    end

    attribute :was_successful, :boolean do
      allow_nil? true
      description "Whether the decision led to success"
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, Thunderline.Thunderblock.Resources.VaultAgent do
      allow_nil? false
      attribute_writable? true
    end

    has_many :actions, Thunderline.Thunderblock.Resources.VaultAction do
      destination_attribute :decision_id
      description "Actions spawned by this decision"
    end

    belongs_to :parent_decision, __MODULE__ do
      allow_nil? true
      attribute_writable? true
      description "Parent decision for sub-decisions"
    end

    has_many :child_decisions, __MODULE__ do
      destination_attribute :parent_decision_id
      description "Sub-decisions made as part of this decision"
    end
  end

  calculations do
    calculate :decision_complexity, :integer, expr(length(options_considered))

    calculate :has_outcome, :boolean, expr(not is_nil(actual_outcome))

    calculate :risk_vs_confidence, :decimal, expr(risk_assessment - confidence_score) do
      description "Difference between risk and confidence (negative = confident despite risk)"
    end
  end

  aggregates do
    count :action_count, :actions
    count :child_decision_count, :child_decisions

    avg :average_action_success_rate, :actions, :success do
      authorize? false
    end

    avg :average_decision_time, :child_decisions, :decision_time_ms do
      authorize? false
    end
  end

  # Private functions that would be used in changes
  defp calculate_outcome_accuracy(expected, actual) when is_map(expected) and is_map(actual) do
    expected_keys = Map.keys(expected) |> MapSet.new()
    actual_keys = Map.keys(actual) |> MapSet.new()
    common_keys = MapSet.intersection(expected_keys, actual_keys)

    if MapSet.size(common_keys) == 0 do
      Decimal.new("0.0")
    else
      matches =
        Enum.count(common_keys, fn key ->
          Map.get(expected, key) == Map.get(actual, key)
        end)

      Decimal.div(matches, MapSet.size(common_keys))
    end
  end

  defp calculate_outcome_accuracy(_expected, _actual), do: Decimal.new("0.0")
end
