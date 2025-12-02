defmodule Thunderline.Evolution.Domain do
  @moduledoc """
  Ash Domain for the Evolution system (HC-Δ-4).

  Manages quality-diversity search using MAP-Elites, maintaining diverse
  elite populations across behavioral niches.

  ## Resources

  - `EliteEntry` - Archive entries for MAP-Elites cells

  ## Integration Points

  - **Thunderpac.TraitsEvolutionJob** - Sources fitness evaluations
  - **Thunderbolt.Cerebros** - Feature extraction for behavior descriptors
  - **Thunderflow.EventBus** - Evolution events for monitoring
  """

  use Ash.Domain,
    otp_app: :thunderline

  resources do
    resource Thunderline.Evolution.Resources.EliteEntry
  end
end
