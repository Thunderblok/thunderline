defmodule Thunderline.Thundercrown.Jido.Actions.DefaultConversation do
  @moduledoc """
  Invoke the default conversation agent to obtain an assistant reply.

  The action delegates to `Thunderline.Thundercrown.Resources.ConversationAgent`
  so that responses flow through AshAI governance (tool access & policy checks).
  """

  use Jido.Action,
    name: "default_conversation",
    description: "Generate a response using the default conversation agent",
    category: "conversation",
    tags: ["conversation", "assistant", "llm"],
    vsn: "1.0.0",
    schema: [
      prompt: [type: :string, required: true],
      history: [type: {:list, :map}, default: []],
      hints: [type: {:list, :string}, default: []],
      persona: [type: :string, required: false]
    ],
    output_schema: [
      reply: [type: :string, required: true],
      metadata: [type: :map, required: true]
    ]

  alias Thunderline.Thundercrown.Resources.ConversationAgent

  @impl true
  def run(params, context) do
    actor = Map.get(context, :actor)
    llm_override = Map.get(context, :llm)

    opts =
      [
        actor: actor,
        authorize?: true,
        context: %{
          llm: llm_override,
          persona: Map.get(params, :persona)
        }
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    args = %{
      prompt: Map.get(params, :prompt),
      history: Map.get(params, :history, []),
      hints: Map.get(params, :hints, [])
    }

    input =
      ConversationAgent
      |> Ash.ActionInput.for_action(:respond, args, opts)

    case Ash.run_action(input) do
      {:ok, reply} ->
        metadata = %{
          history_length: length(args.history),
          persona_applied?: not is_nil(Map.get(params, :persona))
        }

        {:ok, %{reply: reply, metadata: metadata}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
