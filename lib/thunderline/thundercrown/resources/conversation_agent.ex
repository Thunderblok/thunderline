defmodule Thunderline.Thundercrown.Resources.ConversationAgent do
  @moduledoc """
  Default conversational interface exposed through Thundercrown.

  The resource wraps `AshAi.Actions.prompt/2` so LLMs can generate a reply while
  having structured access to governance-approved tools. It intentionally keeps
  the return value as a simple string response so callers can stream or render
  the assistant output directly in the UI.
  """

  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  alias AshAi.Actions.Prompt
  alias Ash.Resource.Actions.Implementation.Context, as: ImplContext

  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message

  @type history_entry :: %{required(:role) => String.t(), required(:content) => String.t()}

  @default_tools [:conversation_context, :conversation_run_digest, :run_agent]

  code_interface do
    define :respond, args: [:prompt], action: :respond
  end

  actions do
    defaults []

    action :respond, :string do
      argument :prompt, :string, allow_nil?: false
      argument :history, {:array, :map}, default: []
      argument :hints, {:array, :string}, default: []
      argument :persona, :string, allow_nil?: true

      run fn input, context ->
        runtime_context = combined_context(input, context)

        llm = select_llm(input, runtime_context)
        adapter = select_adapter(llm, runtime_context)

        prompt_opts =
          [
            llm: llm,
            tools: @default_tools,
            prompt: &__MODULE__.build_prompt_messages/2
          ]
          |> maybe_put_adapter(adapter)

        adjusted_context =
          context
          |> ensure_source_context()
          |> merge_source_context(runtime_context)

        Prompt.run(input, prompt_opts, adjusted_context)
      end
    end
  end

  policies do
    policy action(:respond) do
      authorize_if expr(^actor(:role) in [:owner, :steward, :system])
      authorize_if expr(not is_nil(actor(:tenant_id)))
    end
  end

  attributes do
    uuid_primary_key :id
  end

  @doc false
  @spec select_llm(Ash.ActionInput.t(), map()) :: LangChain.ChatModels.ChatModel.t()
  def select_llm(%Ash.ActionInput{context: %{llm: override}}, _context) when not is_nil(override),
    do: override

  def select_llm(_input, %{llm: override}) when not is_nil(override), do: override

  def select_llm(_input, _context) do
    model = Application.get_env(:thunderline, :conversation_llm, %{})

    ChatOpenAI.new!(
      model
      |> Map.put_new(:model, "gpt-4o")
      |> Map.put_new(:stream, false)
    )
  end

  @doc false
  @spec select_adapter(term(), map()) :: nil | module() | {module(), Keyword.t()}
  def select_adapter(_llm, %{adapter: adapter}) when not is_nil(adapter), do: adapter
  def select_adapter(_llm, %{llm_adapter: adapter}) when not is_nil(adapter), do: adapter
  def select_adapter(_llm, _context), do: nil

  @doc false
  @spec build_prompt_messages(Ash.ActionInput.t(), map()) :: [Message.t()]
  def build_prompt_messages(input, context) do
    args = Map.get(input, :arguments, %{})
    prompt = Map.get(args, :prompt)
    history = Map.get(args, :history, [])
    hints = Map.get(args, :hints, [])

    persona =
      Map.get(args, :persona) ||
        context_persona(context)

    system_prompt =
      persona
      |> system_prompt()
      |> Message.new_system!()

    history_messages = Enum.flat_map(history, &coerce_history_entry/1)

    user_message =
      [prompt | hints]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")
      |> Message.new_user!()

    [system_prompt | history_messages] ++ [user_message]
  end

  defp combined_context(%Ash.ActionInput{context: ctx}, %ImplContext{source_context: source}) do
    Map.new(source || %{})
    |> Map.merge(Map.new(ctx || %{}))
  end

  defp ensure_source_context(%ImplContext{source_context: nil} = context),
    do: %{context | source_context: %{}}

  defp ensure_source_context(context), do: context

  defp merge_source_context(%ImplContext{} = context, runtime_context) do
    passthrough_context = Map.drop(Map.new(runtime_context), [:llm, :adapter, :llm_adapter])
    merged_source = Map.merge(context.source_context, passthrough_context)
    %{context | source_context: merged_source}
  end

  defp maybe_put_adapter(opts, nil), do: opts
  defp maybe_put_adapter(opts, adapter), do: Keyword.put(opts, :adapter, adapter)

  defp context_persona(%ImplContext{source_context: source}) when is_map(source),
    do: Map.get(source, :persona)

  defp context_persona(context) when is_map(context), do: Map.get(context, :persona)
  defp context_persona(_), do: nil

  @doc false
  @spec system_prompt(nil | String.t()) :: String.t()
  def system_prompt(nil) do
    """
    You are Thunderline's default conversation agent. Provide concise, accurate
    answers grounded in the supplied context and system tools. Use the available
    tools when you need up-to-date feature flags or Cerebros run data. Mention
    when a tool call influences your answer.
    """
  end

  def system_prompt(persona) when is_binary(persona) do
    base = system_prompt(nil)
    persona_block = "Persona guidance: #{String.trim(persona)}"
    base <> "\n\n" <> persona_block
  end

  defp coerce_history_entry(%{"role" => role, "content" => content}) do
    coerce_history_entry(%{role: role, content: content})
  end

  defp coerce_history_entry(%{role: role, content: content}) when is_binary(role) do
    case String.downcase(role) do
      "user" -> [Message.new_user!(content)]
      "assistant" -> [Message.new_assistant!(content)]
      _ -> []
    end
  end

  defp coerce_history_entry(%{role: :user, content: content}), do: [Message.new_user!(content)]

  defp coerce_history_entry(%{role: :assistant, content: content}),
    do: [Message.new_assistant!(content)]

  defp coerce_history_entry(_), do: []
end
