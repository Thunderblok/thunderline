defmodule Thunderline.Thundercrown.AgentRunnerTest do
  use Thunderline.DataCase, async: false

  import Ash.Query

  alias Ash.Changeset
  alias Thunderline.Thunderbolt.Resources.CoreAgent
  alias Thunderline.Thundergrid.Resources.Zone
  alias Thunderline.Thundercrown.Resources.AgentRunner

  @actor %{role: :system, tenant_id: "tenant-1"}

  describe "run/2" do
    test "list_available_zones returns active zones" do
      {:ok, _zone} =
        Zone
        |> Changeset.for_create(:spawn_zone, %{q: 1, r: 2, aspect: :neutral, max_agents: 5})
        |> Ash.create()

      {:ok, %{result: %{zones: zones}}} =
        AgentRunner.run("list_available_zones", "{}", actor: @actor)

      assert length(zones) == 1
      assert Enum.any?(zones, fn zone -> zone[:coordinates] == %{q: 1, r: 2} end)
    end

    test "register_core_agent creates an agent" do
      prompt =
        %{
          "agent_name" => "relay-001",
          "agent_type" => "system",
          "capabilities" => %{"routing" => true}
        }
        |> Jason.encode!()

      {:ok, %{result: %{agent: agent}}} =
        AgentRunner.run("register_core_agent", prompt, actor: @actor)

      assert agent.agent_name == "relay-001"
      assert agent.agent_type == :system

      {:ok, stored_agent} =
        CoreAgent
        |> filter(agent_name == "relay-001")
        |> Ash.read_one()

      assert stored_agent.agent_name == "relay-001"
    end

    test "unknown tool returns error" do
  assert {:error, %Ash.Error.Unknown{} = error} =
       AgentRunner.run("invalid_tool", "{}", actor: @actor)

  assert Exception.message(error) =~ "unknown_tool"
    end

    test "malformed prompt returns error" do
  assert {:error, reason} = AgentRunner.run("list_available_zones", "not-json", actor: @actor)
  assert Exception.message(reason) =~ "Unable to decode prompt"
    end
  end
end
