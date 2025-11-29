defmodule Thunderline.Thunderwall.Domain do
  @moduledoc """
  Thunderwall Domain - System boundary, decay, GC, and entropy sink.

  Thunderwall is the 12th domain in the Pantheon, representing the system's
  final destination for expired, rejected, or archived data. It is the
  counterpart to Thundercore - while Core is the origin of time, Wall is
  where time-expired entities go to rest.

  ## Responsibilities

  - **Decay Processing**: Archive expired resources with configurable retention
  - **Overflow Handling**: Manage reject streams from other domains
  - **Entropy Metrics**: Track system decay and resource turnover
  - **GC Scheduling**: Coordinate garbage collection across domains

  ## Domain Position

  Wall is #12 in the Pantheon cycle, receiving:
  - Expired PACs from Thunderpac
  - Stale events from Thunderflow
  - Orphaned data from Thunderblock
  - Failed saga states from Thundercrown

  ## Events

  - `wall.decay.*` - Resource decay events
  - `wall.archive.*` - Archival events
  - `wall.gc.*` - Garbage collection events
  - `wall.overflow.*` - Overflow/reject events
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Thunderline.Thunderwall.Resources.DecayRecord
    resource Thunderline.Thunderwall.Resources.ArchiveEntry
  end

  authorization do
    authorize :by_default
    require_actor? false
  end
end
