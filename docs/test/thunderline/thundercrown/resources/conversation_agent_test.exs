defmodule Thunderline.Thundercrown.Resources.ConversationAgentTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercrown.LLM.FixedLLM
  alias Thunderline.Thundercrown.Resources.ConversationAgent
  alias AshAi.Actions.Prompt.Adapter.Raw, as: RawAdapter

  @actor %{role: :owner, tenant_id: "tenant-1"}

  test "system_prompt defaults to governance guidance" do
    assert ConversationAgent.system_prompt(nil) =~ "default conversation agent"
  end

  test "system_prompt appends persona guidance" do
    prompt = ConversationAgent.system_prompt("Act like a cheerful assistant")
    assert prompt =~ "Persona guidance"
    assert prompt =~ "cheerful assistant"
  end

  test "build_prompt_messages transforms history" do
    input =
      ConversationAgent
      |> Ash.ActionInput.for_action(
        :respond,
        %{
          prompt: "Hello",
          history: [%{role: "user", content: "hi"}, %{role: "assistant", content: "hey"}],
          hints: ["Use precise tone"],
          persona: "Formal"
        },
        actor: @actor
      )

    messages = ConversationAgent.build_prompt_messages(input, %{persona: "Formal"})
    roles = Enum.map(messages, & &1.role)

    assert [:system, :user, :assistant, :user] = roles
  end

  test "respond uses provided llm override" do
    llm = %FixedLLM{response: "Test reply"}

    input =
      ConversationAgent
      |> Ash.ActionInput.for_action(:respond, %{prompt: "hello"},
        actor: @actor,
        context: %{llm: llm, adapter: RawAdapter}
      )

    assert {:ok, "Test reply"} = Ash.run_action(input)
  end
end
