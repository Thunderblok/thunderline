defmodule Thunderline.Thundercrown.LLM.FixedLLM do
  @moduledoc """
  Deterministic LangChain chat model that returns canned or echo-style responses.

  Useful for environments where no external LLM is configured but agent flows
  still need to run.
  """

  @behaviour LangChain.ChatModels.ChatModel

  alias LangChain.Message
  alias LangChain.LangChainError

  defstruct response: nil, mode: :echo, callbacks: []

  @type mode :: :echo | :static
  @type t :: %__MODULE__{response: String.t() | nil, mode: mode(), callbacks: list()}

  @doc """
  Builds a new fixed LLM model.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl true
  def call(%__MODULE__{} = model, messages, _tools) do
    reply =
      cond do
        is_binary(model.response) and model.response != "" ->
          model.response

        model.mode == :echo ->
          build_echo_reply(messages)

        true ->
          "Default agent channel online."
      end

    {:ok, Message.new_assistant!(reply)}
  end

  @impl true
  def serialize_config(%__MODULE__{} = model) do
    %{
      "module" => __MODULE__ |> Atom.to_string(),
      "response" => model.response,
      "mode" => Atom.to_string(model.mode)
    }
  end

  @impl true
  def restore_from_map(%{"mode" => mode} = map) do
    mode_atom = String.to_existing_atom(mode)

    {:ok,
     %__MODULE__{
       response: Map.get(map, "response"),
       mode: mode_atom
     }}
  rescue
    ArgumentError ->
      {:error, "Invalid mode"}
  end

  def restore_from_map(%{"response" => response}) do
    {:ok, %__MODULE__{response: response}}
  end

  def restore_from_map(_), do: {:error, "Missing response"}

  @doc """
  Returns whether this model should retry on a given error.

  For a fixed/deterministic model, we never need to retry since there are
  no external services that could have transient failures.
  """
  @impl true
  @spec retry_on_fallback?(LangChainError.t()) :: boolean()
  def retry_on_fallback?(_error), do: false

  defp build_echo_reply(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(nil, fn
      %Message{role: :user, content: content} -> sanitize_content(content)
      _ -> nil
    end)
    |> case do
      nil -> "Default agent channel online."
      "" -> "Default agent channel online."
      content -> "Default agent reply: " <> content
    end
  end

  defp sanitize_content(content) when is_binary(content), do: String.trim(content)

  defp sanitize_content(content) when is_list(content) do
    content
    |> Enum.map(&content_part_to_string/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> String.trim()
  end

  defp sanitize_content(_), do: ""

  defp content_part_to_string(%{content: inner}) when is_binary(inner), do: inner
  defp content_part_to_string(%{text: inner}) when is_binary(inner), do: inner
  defp content_part_to_string(_), do: nil
end
