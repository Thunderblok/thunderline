defmodule Thunderline.Thundergrid.Prism.AutomataSnapshot do
  @moduledoc """
  AutomataSnapshot — Timestamped CA/NCA metrics for introspection.

  Stores periodic snapshots of automata state for:
  - Historical analysis and trend detection
  - GraphQL queries for dashboard visualization
  - Edge-of-chaos monitoring
  - Side-quest metric timelines

  ## Metrics Captured

  **Criticality (HC-40):**
  - PLV (Phase-Locking Value)
  - Permutation entropy
  - Langton's λ̂
  - Lyapunov exponent
  - Edge score
  - Zone classification

  **Side-Quest (TIGER LATTICE):**
  - Clustering coefficient
  - Sortedness measure
  - Healing rate
  - Pattern stability
  - Emergence score

  **Doctrine Layer (TIGER LATTICE):**
  - Algotype clustering (same-doctrine spatial clustering)
  - Algotype Ising energy (doctrine spin interactions)
  - Doctrine distribution (map of doctrine -> count)
  - Doctrine entropy (diversity of doctrines)

  ## GraphQL

  Exposed via Thundergrid.Domain as `automata_snapshot` type.
  """
  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "automata_snapshots"
    repo Thunderline.Repo
  end

  graphql do
    type :automata_snapshot

    queries do
      get :get_automata_snapshot, :read
      list :list_automata_snapshots, :by_run
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :run_id,
        :tick,
        :plv,
        :entropy,
        :lambda_hat,
        :lyapunov,
        :edge_score,
        :zone,
        :clustering,
        :sortedness,
        :healing_rate,
        :pattern_stability,
        :emergence_score,
        :grid_tick,
        :cell_count,
        :meta,
        # Doctrine Layer fields
        :algotype_clustering,
        :algotype_ising_energy,
        :doctrine_distribution,
        :doctrine_entropy
      ]
    end

    read :by_run do
      argument :run_id, :string, allow_nil?: false
      argument :limit, :integer, default: 100

      filter expr(run_id == ^arg(:run_id))
      prepare build(sort: [tick: :desc], limit: arg(:limit))
    end

    read :recent do
      argument :limit, :integer, default: 50
      prepare build(sort: [sampled_at: :desc], limit: arg(:limit))
    end

    read :by_zone do
      argument :zone, :atom, allow_nil?: false
      filter expr(zone == ^arg(:zone))
      prepare build(sort: [sampled_at: :desc])
    end

    read :critical_snapshots do
      filter expr(zone == :critical)
      prepare build(sort: [edge_score: :desc])
    end

    read :doctrine_distribution do
      description "Get latest doctrine distribution for a CA run"
      argument :run_id, :string, allow_nil?: false
      filter expr(run_id == ^arg(:run_id) and not is_nil(doctrine_distribution))
      prepare build(sort: [tick: :desc], limit: 1)
    end

    read :doctrine_history do
      description "Get doctrine distribution history for a CA run"
      argument :run_id, :string, allow_nil?: false
      argument :limit, :integer, default: 50
      filter expr(run_id == ^arg(:run_id) and not is_nil(algotype_clustering))
      prepare build(sort: [tick: :desc], limit: arg(:limit))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :run_id, :string do
      allow_nil? false
      public? true
      description "CA run identifier"
    end

    attribute :tick, :integer do
      allow_nil? false
      public? true
      description "CA tick when snapshot was taken"
    end

    # Criticality metrics
    attribute :plv, :float do
      public? true
      description "Phase-Locking Value [0,1]"
    end

    attribute :entropy, :float do
      public? true
      description "Permutation entropy [0,1]"
    end

    attribute :lambda_hat, :float do
      public? true
      description "Langton's λ̂ parameter [0,1]"
    end

    attribute :lyapunov, :float do
      public? true
      description "Lyapunov exponent estimate"
    end

    attribute :edge_score, :float do
      public? true
      description "Edge-of-chaos score [0,1]"
    end

    attribute :zone, :atom do
      public? true
      constraints one_of: [:ordered, :critical, :chaotic]
      description "Dynamical zone classification"
    end

    # Side-quest metrics
    attribute :clustering, :float do
      public? true
      description "Spatial clustering coefficient [0,1]"
    end

    attribute :sortedness, :float do
      public? true
      description "Order/sortedness measure [0,1]"
    end

    attribute :healing_rate, :float do
      public? true
      description "Damage recovery rate [0,1]"
    end

    attribute :pattern_stability, :float do
      public? true
      description "Pattern persistence [0,1]"
    end

    attribute :emergence_score, :float do
      public? true
      description "Novel structure detection [0,1]"
    end

    # Doctrine Layer metrics (Operation TIGER LATTICE)
    attribute :algotype_clustering, :float do
      public? true
      description "Same-doctrine spatial clustering [0,1]"
    end

    attribute :algotype_ising_energy, :float do
      public? true
      description "Ising energy from doctrine spin interactions"
    end

    attribute :doctrine_distribution, :map do
      public? true
      description "Map of doctrine atom -> count"
    end

    attribute :doctrine_entropy, :float do
      public? true
      description "Normalized entropy of doctrine distribution [0,1]"
    end

    # Grid state
    attribute :grid_tick, :integer do
      public? true
      description "Grid's internal tick counter"
    end

    attribute :cell_count, :integer do
      public? true
      description "Number of cells in grid"
    end

    attribute :meta, :map do
      default %{}
      public? true
      description "Additional snapshot metadata"
    end

    attribute :sampled_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
      description "When snapshot was captured"
    end

    create_timestamp :inserted_at
  end

  calculations do
    calculate :is_critical, :boolean, expr(zone == :critical) do
      description "Whether system is at edge of chaos"
    end

    calculate :criticality_score, :float, expr(
      (plv * 0.25) + (entropy * 0.25) + (edge_score * 0.5)
    ) do
      description "Composite criticality score"
    end

    calculate :side_quest_score, :float, expr(
      (clustering * 0.3) + (emergence_score * 0.4) + (pattern_stability * 0.3)
    ) do
      description "Composite side-quest score"
    end

    calculate :algotype_score, :float, expr(
      (algotype_clustering * 0.5) + ((1.0 - abs(algotype_ising_energy)) * 0.5)
    ) do
      description "Composite algotype health score (high clustering + low energy = good)"
    end
  end

  identities do
    identity :unique_run_tick, [:run_id, :tick]
  end
end
