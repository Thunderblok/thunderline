defmodule Thunderline.Thundercrown.Jido.Actions.DefaultConversationTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Test.Support.FixedLLM
  alias Thunderline.Thundercrown.Jido.Actions.DefaultConversation

  @actor %{role: :owner, tenant_id: "tenant-1"}

  test "run delegates to conversation agent" do
    params = %{prompt: "hello"}
    context = %{actor: @actor, llm: %FixedLLM{response: "ok"}}

    assert {:ok, %{reply: "ok", metadata: %{history_length: 0}}} =
             DefaultConversation.run(params, context)
  end

  test "metadata notes persona usage" do
    params = %{prompt: "hello", persona: "Joyful"}
    context = %{actor: @actor, llm: %FixedLLM{response: "ok"}}

    assert {:ok, %{metadata: %{persona_applied?: true}}} =
             DefaultConversation.run(params, context)
  end
end
