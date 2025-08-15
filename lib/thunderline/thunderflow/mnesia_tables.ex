defmodule Thunderflow.CrossDomainEvents do
  @moduledoc """
  Mnesia table for storing cross-domain events.
  """

  use Memento.Table,
    attributes: [
      :id,
      :data,
      :created_at,
      :status,
      :attempts,
      :pipeline_type,
      :priority,
      :from_domain,
      :to_domain
    ],
    index: [:status, :pipeline_type, :priority, :created_at, :from_domain, :to_domain],
    type: :ordered_set
end

defmodule Thunderflow.RealTimeEvents do
  @moduledoc """
  Mnesia table for storing real-time events.
  """

  use Memento.Table,
    attributes: [
      :id,
      :data,
      :created_at,
      :status,
      :attempts,
      :pipeline_type,
      :priority,
      :event_type,
      :latency_requirement
    ],
    index: [:status, :pipeline_type, :priority, :created_at, :event_type, :latency_requirement],
    type: :ordered_set
end
