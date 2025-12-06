defmodule Thunderline.Thundercore.Reward.RewardSnapshot do
  @moduledoc """
  RewardSnapshot — Persistent reward signal records.

  Stores reward computation results for analysis and visualization.
  Supports time-series queries for reward history analysis.

  ## GraphQL

  Available via Thundercore.Domain:
  - `reward_snapshots` — List snapshots with filtering
  - `reward_snapshot` — Get single snapshot by ID

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 3
  """

  use Ash.Resource,
    domain: Thunderline.Thundercore.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "reward_snapshots"
    repo Thunderline.Repo

    migration_types run_id: :string
  end

  graphql do
    type :reward_snapshot

    queries do
      get :get_reward_snapshot, :read
      list :list_reward_snapshots, :by_run
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :run_id, :string do
      allow_nil? false
      description "The CA run this reward is for"
    end

    attribute :tick, :integer do
      allow_nil? false
      default 0
      description "The tick/iteration when computed"
    end

    attribute :reward, :float do
      allow_nil? false
      description "The scalar reward value [0, 1]"
    end

    # Component scores
    attribute :edge_score, :float do
      description "Criticality edge-of-chaos score"
    end

    attribute :emergence, :float do
      description "Emergence score component"
    end

    attribute :stability, :float do
      description "Pattern stability component"
    end

    attribute :healing, :float do
      description "Healing rate component"
    end

    # Tuning signals
    attribute :lambda_delta, :float do
      description "Lambda tuning signal"
    end

    attribute :temp_delta, :float do
      description "Temperature tuning signal"
    end

    attribute :coupling_delta, :float do
      description "Coupling tuning signal"
    end

    # Applied params
    attribute :applied_lambda, :float do
      description "Applied lambda parameter"
    end

    attribute :applied_temperature, :float do
      description "Applied temperature parameter"
    end

    attribute :applied_coupling, :float do
      description "Applied coupling parameter"
    end

    # Zone
    attribute :zone, :atom do
      constraints one_of: [:ordered, :critical, :chaotic]
      description "Dynamical zone classification"
    end

    create_timestamp :inserted_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :run_id,
        :tick,
        :reward,
        :edge_score,
        :emergence,
        :stability,
        :healing,
        :lambda_delta,
        :temp_delta,
        :coupling_delta,
        :applied_lambda,
        :applied_temperature,
        :applied_coupling,
        :zone
      ]
    end

    read :by_run do
      argument :run_id, :string, allow_nil?: false

      filter expr(run_id == ^arg(:run_id))

      pagination do
        offset? true
        default_limit 100
        countable true
      end

      prepare build(sort: [tick: :desc])
    end

    read :latest_for_run do
      argument :run_id, :string, allow_nil?: false

      filter expr(run_id == ^arg(:run_id))

      prepare build(sort: [tick: :desc], limit: 1)
    end

    read :in_zone do
      argument :zone, :atom, allow_nil?: false

      filter expr(zone == ^arg(:zone))

      pagination do
        offset? true
        default_limit 50
        countable true
      end
    end
  end

  code_interface do
    domain Thunderline.Thundercore.Domain

    define :create
    define :by_run, args: [:run_id]
    define :latest_for_run, args: [:run_id]
    define :in_zone, args: [:zone]
  end

  identities do
    identity :run_tick, [:run_id, :tick]
  end
end
