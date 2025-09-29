defmodule Thunderline.Thundercrown.Jido.Actions.RegisterCoreAgent do
  @moduledoc """
  Register a new Thunderbolt core agent under governance oversight.

  The action delegates to the Ash resource responsible for tracking system agents
  and returns a sanitized representation suitable for MCP clients.
  """

  use Jido.Action,
    name: "register_core_agent",
    description: "Register a Thunderbolt core agent",
    category: "thunderbolt",
    tags: ["agents", "thunderbolt", "registration"],
    vsn: "1.0.0",
    schema: [
      agent_name: [type: :string, required: true],
      agent_type: [type: :string, required: true],
      capabilities: [type: :map, default: %{}]
    ],
    output_schema: [
      agent: [type: :map, required: true]
    ]

  alias Thunderline.Thundercrown.Action
  alias Thunderline.Thunderbolt.Resources.CoreAgent

  @allowed_agent_types ~w(system coordinator worker observer)a

  @impl true
  def run(params, context) do
    actor = Map.get(context, :actor)

    with {:ok, agent_type} <- normalize_agent_type(params.agent_type),
         input <- %{
           agent_name: params.agent_name,
           agent_type: agent_type,
           capabilities: Map.get(params, :capabilities, %{})
         },
         {:ok, agent} <- Action.call(CoreAgent, :register, input, actor: actor, emit?: false) do
      {:ok, %{agent: serialize_agent(agent)}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_agent_type(type) when is_atom(type) do
    if type in @allowed_agent_types do
      {:ok, type}
    else
      {:error, "Unsupported agent_type: #{inspect(type)}"}
    end
  end

  defp normalize_agent_type(type) when is_binary(type) do
    type
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_agent_type()
  rescue
    ArgumentError -> {:error, "Unsupported agent_type: #{inspect(type)}"}
  end

  defp normalize_agent_type(_), do: {:error, "agent_type must be a string or atom"}

  defp serialize_agent(agent) do
    %{
      id: agent.id,
      agent_name: agent.agent_name,
      agent_type: agent.agent_type,
      status: agent.status,
      capabilities: agent.capabilities,
      current_task: agent.current_task,
      last_heartbeat: agent.last_heartbeat
    }
  end
end
