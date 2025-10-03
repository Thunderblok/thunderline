defmodule Thunderline.Test.Support.FixedLLM do
  @moduledoc """
  Deterministic LangChain chat model used for unit tests.
  """

  @behaviour LangChain.ChatModels.ChatModel

  defstruct response: "Test response", callbacks: []

  alias LangChain.Message

  @impl true
  def call(%__MODULE__{response: response}, _messages, _tools) do
    {:ok, Message.new_assistant!(response)}
  end

  @impl true
  def serialize_config(%__MODULE__{} = model) do
    %{
      "module" => __MODULE__ |> Atom.to_string(),
      "response" => model.response
    }
  end

  @impl true
  def restore_from_map(%{"response" => response}) do
    {:ok, %__MODULE__{response: response}}
  end

  def restore_from_map(_), do: {:error, "Missing response"}
end
