defmodule Thunderline.Thundercore.Domain do
  @moduledoc """
  Thundercore Domain — The Origin/Seedpoint Domain (#1 in Pantheon).

  Provides:
  - **Tick emanation**: System heartbeat for temporal coherence
  - **System clock**: Monotonic time service
  - **Identity kernel**: PAC seedpoint generation
  - **Temporal alignment**: Synchronization primitives

  ## System Cycle

  Thundercore is the START of the system cycle (Core → Wall).
  It provides the universal heartbeat that all other domains synchronize to.

  ## Event Categories

  - `core.tick.*` - Tick/heartbeat events
  - `core.identity.*` - Identity kernel events
  - `core.clock.*` - Clock synchronization events

  ## Components

  - `Thundercore.TickEmitter` - System heartbeat GenServer
  - `Thundercore.SystemClock` - Monotonic time service
  - `Thundercore.IdentityKernel` - PAC seedpoint resource

  ## Reference

  - HC-46 in THUNDERLINE_MASTER_PLAYBOOK.md
  - Pantheon Position: #1 – Origin/Seedpoint domain
  """

  use Ash.Domain,
    extensions: [AshAdmin.Domain],
    otp_app: :thunderline

  admin do
    show? true
  end

  resources do
    resource Thunderline.Thundercore.Resources.TickState
    resource Thunderline.Thundercore.Resources.IdentityKernel
  end
end
