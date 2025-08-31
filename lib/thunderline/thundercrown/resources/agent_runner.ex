defmodule Thunderline.Thundercrown.Resources.AgentRunner do
  @moduledoc "Run approved Jido/AshAI tools under ThunderCrown governance."
  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  code_interface do
    define :run, args: [:tool, :prompt]
  end

  actions do
    defaults []

    action :run do
      argument :tool, :string, allow_nil?: false
      argument :prompt, :string, allow_nil?: false

      run fn _input, %{arguments: %{tool: tool, prompt: prompt}} ->
        # TODO: Gate with ThunderGate policy and actual AshAI/Jido invocation
        corr = Thunderline.UUID.v7()
        emit("ui.command.agent.requested", %{tool: tool, prompt: String.slice(prompt, 0, 120), correlation_id: corr})
        # Simulate token/stream id
        {:ok, %{stream_id: "ai-" <> String.slice(corr, 0, 8), correlation_id: corr}}
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :stream_id, :string, public?: true
    attribute :correlation_id, :string, public?: true
  end

  policies do
    policy action(:run) do
      authorize_if expr(actor(:role) in [:owner, :steward, :system])
      authorize_if expr(not is_nil(actor(:tenant_id)))
    end
  end

  defp emit(name, payload) do
    with {:ok, ev} <- Thunderline.Event.new(name: name, source: :crown, payload: payload) do
      _ = Task.start(fn -> Thunderline.EventBus.emit(ev) end)
    end
  end
end
