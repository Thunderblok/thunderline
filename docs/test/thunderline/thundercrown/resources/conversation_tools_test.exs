defmodule Thunderline.Thundercrown.Resources.ConversationToolsTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercrown.Resources.ConversationTools

  @actor %{role: :owner, tenant_id: "tenant-1"}

  test "context_snapshot returns feature and environment data" do
    input =
      ConversationTools
      |> Ash.ActionInput.for_action(:context_snapshot, %{}, actor: @actor)

    assert {:ok, result} = Ash.run_action(input)
    assert is_binary(result.timestamp_iso8601)
    assert Map.has_key?(result, :feature_flags)
    assert Map.has_key?(result, :environment)
    assert Map.has_key?(result, :cerebros_enabled?)
    assert Map.get(result, :actor_role) == :owner
  end

  test "run_digest limits run count" do
    limit = 2

    input =
      ConversationTools
      |> Ash.ActionInput.for_action(:run_digest, %{limit: limit}, actor: @actor)

    assert {:ok, result} = Ash.run_action(input)
    assert Map.has_key?(result, :runs)
    assert is_list(result.runs)
    assert length(result.runs) <= limit
  end
end
