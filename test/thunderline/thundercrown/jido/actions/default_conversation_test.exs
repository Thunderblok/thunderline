defmodule Thunderline.Thundercrown.Jido.Actions.DefaultConversationTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercrown.LLM.FixedLLM
  alias Thunderline.Thundercrown.Jido.Actions.DefaultConversation
  alias AshAi.Actions.Prompt.Adapter.Raw, as: RawAdapter

  @actor %{role: :owner, tenant_id: "tenant-1"}

  test "run delegates to conversation agent" do
    params = %{prompt: "hello"}
    context = %{actor: @actor, llm: %FixedLLM{response: "ok"}, adapter: RawAdapter}

    assert {:ok, %{reply: "ok", metadata: %{history_length: 0}}} =
             DefaultConversation.run(params, context)
  end

  test "metadata notes persona usage" do
    params = %{prompt: "hello", persona: "Joyful"}
    context = %{actor: @actor, llm: %FixedLLM{response: "ok"}, adapter: RawAdapter}

    assert {:ok, %{metadata: %{persona_applied?: true}}} =
             DefaultConversation.run(params, context)
  end
end
