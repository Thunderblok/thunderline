defmodule Thunderline.Thundercore.Domain do
  @moduledoc """
  Thundercore Domain — The Origin/Seedpoint Domain (#1 in Pantheon).

  Provides:
  - **Tick emanation**: System heartbeat for temporal coherence
  - **System clock**: Monotonic time service
  - **Identity kernel**: PAC seedpoint generation
  - **Temporal alignment**: Synchronization primitives
  - **Reward loop**: Edge-of-chaos reward signals and tuning

  ## System Cycle

  Thundercore is the START of the system cycle (Core → Wall).
  It provides the universal heartbeat that all other domains synchronize to.

  ## Event Categories

  - `core.tick.*` - Tick/heartbeat events
  - `core.identity.*` - Identity kernel events
  - `core.clock.*` - Clock synchronization events
  - `core.reward.*` - Reward loop events

  ## Components

  - `Thundercore.TickEmitter` - System heartbeat GenServer
  - `Thundercore.SystemClock` - Monotonic time service
  - `Thundercore.IdentityKernel` - PAC seedpoint resource
  - `Thundercore.Reward.*` - Reward loop subsystem

  ## GraphQL Queries

  - `reward_snapshots` — List reward snapshots for a run
  - `reward_snapshot` — Get single reward snapshot

  ## Reference

  - HC-46 in THUNDERLINE_MASTER_PLAYBOOK.md
  - HC Orders: Operation TIGER LATTICE, Thread 3
  - Pantheon Position: #1 – Origin/Seedpoint domain
  """

  use Ash.Domain,
    extensions: [AshAdmin.Domain, AshGraphql.Domain],
    otp_app: :thunderline

  admin do
    show? true
  end

  graphql do
    queries do
      # RewardSnapshot queries
      list Thunderline.Thundercore.Reward.RewardSnapshot, :reward_snapshots, :by_run
      get Thunderline.Thundercore.Reward.RewardSnapshot, :reward_snapshot, :read
    end
  end

  resources do
    resource Thunderline.Thundercore.Resources.TickState
    resource Thunderline.Thundercore.Resources.IdentityKernel
    resource Thunderline.Thundercore.Reward.RewardSnapshot
  end
end
