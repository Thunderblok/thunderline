defmodule Thunderline.Thunderbolt.LaneCouplingPipeline do
  @moduledoc """
  Stub implementation of LaneCouplingPipeline.

  Referenced by lane coupling resource for lifecycle events. Replace with
  Broadway/GenStage pipeline orchestration as needed.
  """
  require Logger

  def initialize_coupling(coupling) do
    Logger.debug("[LaneCouplingPipeline] initialize #{coupling.id}")
    :ok
  end

  def reconfigure_coupling(coupling) do
    Logger.debug("[LaneCouplingPipeline] reconfigure #{coupling.id}")
    :ok
  end

  def activate_coupling(id) do
    Logger.debug("[LaneCouplingPipeline] activate #{id}")
    :ok
  end

  def deactivate_coupling(id) do
    Logger.debug("[LaneCouplingPipeline] deactivate #{id}")
    :ok
  end
end
