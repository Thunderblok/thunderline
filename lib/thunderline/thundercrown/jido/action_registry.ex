defmodule Thunderline.Thundercrown.Jido.ActionRegistry do
  @moduledoc """
  Governance-curated registry of Jido actions exposed through Thundercrown.AgentRunner.

  The registry provides a whitelist of allowed tool identifiers and the corresponding
  `Jido.Action` implementation modules. It keeps the mapping centralized so policy
  reviews can audit which capabilities are reachable via MCP.
  """

  @type tool_name :: String.t()
  @type action_module :: module()

  @registry %{
    "default_conversation" => Thunderline.Thundercrown.Jido.Actions.DefaultConversation,
    "list_available_zones" => Thunderline.Thundercrown.Jido.Actions.ListAvailableZones,
    "register_core_agent" => Thunderline.Thundercrown.Jido.Actions.RegisterCoreAgent
  }

  @spec resolve(tool_name()) :: {:ok, action_module()} | {:error, :unknown_tool}
  def resolve(tool) when is_binary(tool) do
    case Map.fetch(@registry, tool) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_tool}
    end
  end

  def resolve(tool) when is_atom(tool), do: resolve(to_string(tool))

  @spec tools() :: [tool_name()]
  def tools, do: Map.keys(@registry)
end
