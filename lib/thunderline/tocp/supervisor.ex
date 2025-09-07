defmodule Thunderline.TOCP.Supervisor do
  @moduledoc """
  Top-level supervisor for the Thunderline Open Circuit Protocol (TOCP) domain.

  This supervisor is feature-flag gated via `:tocp_enabled` (feature key: `:tocp`).
  No runtime logic yet – this is the zero-logic scaffold (HC Orders Θ-01 / 72h scaffold).

  Child specs are declared but commented or minimal until subsequent sprints (Week 1/2).
  Security Flags:
    * presence_secured: when true, control frame signing & replay guards must activate (future logic).

  Note: For callers under the Thunderlink namespace, prefer starting
  `Thunderline.Thunderlink.Transport.Supervisor` which delegates to this
  module. This allows us to gradually roll TOCP components under the
  Thunderlink umbrella without breaking existing code.
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    unless Thunderline.Feature.enabled?(:tocp) do
      Logger.warning("[TOCP] Supervisor started while feature disabled (should not be attached) – noop")
    end

    # Warm config cache & prepare security replay window if presence is secured.
    conf = Thunderline.Thunderlink.Transport.Config.get()
    if conf.security.presence_secured do
      Thunderline.Thunderlink.Transport.Security.Impl.ensure_table()
    end

    children = [
      # Security replay window pruning when presence security enabled
      (conf.security.presence_secured && {Thunderline.Thunderlink.Transport.Security.Pruner, []}) || nil,
      # Dynamic routing hysteresis and switch tracking
      {Thunderline.Thunderlink.Transport.Routing.HysteresisManager, []},
      {Thunderline.Thunderlink.Transport.Routing.SwitchTracker, []},
      # Telemetry aggregation (security counters consumed by simulator & health endpoints)
      {Thunderline.Thunderlink.Transport.Telemetry.Aggregator, []}
    ] |> Enum.filter(& &1)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
