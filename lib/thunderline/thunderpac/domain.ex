defmodule Thunderline.Thunderpac.Domain do
  @moduledoc """
  Thunderpac Domain — The PAC Lifecycle Domain (#2 in Pantheon).

  **PAC = Personal Autonomous Construct**

  Provides:
  - **PAC lifecycle**: State management (dormant → active → suspended → archived)
  - **Intent management**: PAC intent definition and execution
  - **Role definitions**: PAC behavioral roles and capabilities
  - **State persistence**: Cross-session PAC memory
  - **Identity binding**: Connection to Thundercore identity kernels

  ## Domain Vector

  Pac → Block → Vine (state → persist → orchestrate)
  
  PAC state flows downstream to Block for persistence and Vine for DAG tracking.

  ## Event Categories

  - `pac.lifecycle.*` - Lifecycle transitions (create, activate, suspend, archive)
  - `pac.intent.*` - Intent events (declare, execute, complete, cancel)
  - `pac.state.*` - State updates and snapshots

  ## Components

  - `Thunderpac.PAC` - Core PAC resource (state container)
  - `Thunderpac.PACRole` - Role definitions and capabilities
  - `Thunderpac.PACIntent` - Intent management
  - `Thunderpac.PACState` - State snapshots for persistence

  ## Reference

  - HC-47 in THUNDERLINE_MASTER_PLAYBOOK.md
  - Pantheon Position: #2 – PAC lifecycle domain
  - Domain Vector: Pac → Block → Vine
  """

  use Ash.Domain,
    extensions: [AshAdmin.Domain],
    otp_app: :thunderline

  admin do
    show? true
  end

  resources do
    resource Thunderline.Thunderpac.Resources.PAC
    resource Thunderline.Thunderpac.Resources.PACRole
    resource Thunderline.Thunderpac.Resources.PACIntent
    resource Thunderline.Thunderpac.Resources.PACState
  end
end
