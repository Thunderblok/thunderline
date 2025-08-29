defmodule Thunderline.TOCP.Supervisor do
  @moduledoc """
  Top-level supervisor for the Thunderline Open Circuit Protocol (TOCP) domain.

  This supervisor is feature-flag gated via `:tocp_enabled` (feature key: `:tocp`).
  No runtime logic yet – this is the zero-logic scaffold (HC Orders Θ-01 / 72h scaffold).

  Child specs are declared but commented or minimal until subsequent sprints (Week 1/2).
  Security Flags:
    * presence_secured: when true, control frame signing & replay guards must activate (future logic).
  """
  use Supervisor
  require Logger

  @impl true
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    unless Thunderline.Feature.enabled?(:tocp) do
      Logger.warning("[TOCP] Supervisor started while feature disabled (should not be attached) – noop")
    end

    # Warm config cache & prepare security replay window if presence is secured.
    conf = Thunderline.TOCP.Config.get()
    if conf.security.presence_secured do
      Thunderline.TOCP.Security.Impl.ensure_table()
    end

    children = [
      {Thunderline.TOCP.Config, []},
      # Security replay window pruning when presence security enabled
      (conf.security.presence_secured && {Thunderline.TOCP.Security.Pruner, []}) || nil,
      # Dynamic routing hysteresis and switch tracking
      {Thunderline.TOCP.Routing.HysteresisManager, []},
      {Thunderline.TOCP.Routing.SwitchTracker, []},
      # Telemetry aggregation (security counters consumed by simulator & health endpoints)
      {Thunderline.TOCP.Telemetry.Aggregator, []}
    ] |> Enum.filter(& &1)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
