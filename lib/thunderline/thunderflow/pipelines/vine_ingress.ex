defmodule Thunderline.Thunderflow.Pipelines.VineIngress do
  @moduledoc """
  Broadway pipeline ingesting CA rule parse & workflow spec parse commands.

  Source topics (PubSub):
    events:cmd.ca.rule.parse
    events:cmd.workflow.spec.parse

  Message data payload format (sent via EventBus.publish/emit*):
    %{type: :cmd_ca_rule_parse, payload: %{line: "B3/S23", meta: %{...}}}
    %{type: :cmd_workflow_spec_parse, payload: %{spec: "workflow W...", meta: %{...}}}
  """
  use Broadway
  require Logger
  alias Phoenix.PubSub
  alias Thunderline.{CA, Thundervine}
  alias Thunderline.Thundervine.Events

  @pubsub Thunderline.PubSub
  @rule_topic "events:cmd.ca.rule.parse"
  @spec_topic "events:cmd.workflow.spec.parse"

  # Public start helper for supervision tree
  def start_link(opts) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producers: [
        default: [
          module:
            {BroadwayPubSub.Producer,
             [
               pubsub: @pubsub,
               subscription_topics: [@rule_topic, @spec_topic]
             ]},
          stages: 1
        ]
      ],
      processors: [default: [stages: concurrency]],
      batchers: []
    )
  end

  # For tests & manual injection we keep a light process/1 API that synthesizes a Broadway message path.
  def process(map) when is_map(map), do: handle_command(map)

  @impl true
  def handle_message(_processor, %Broadway.Message{data: data} = msg, _context) do
    case handle_command(data) do
      {:ok, _} -> msg
      {:error, reason} -> Broadway.Message.failed(msg, reason)
    end
  end

  defp handle_command(%{type: :cmd_ca_rule_parse, payload: %{line: line} = payload}) do
    meta = Map.get(payload, :meta, %{})

    with {:ok, rule} <- CA.parse_rule(line),
         {:ok, _} <- Events.rule_parsed(rule, meta) do
      {:ok, :rule_committed}
    else
      {:error, e} -> {:error, {:rule_parse_failed, e}}
    end
  end

  defp handle_command(%{type: :cmd_workflow_spec_parse, payload: %{spec: text} = payload}) do
    meta = Map.get(payload, :meta, %{})

    with {:ok, spec} <- Thundervine.SpecParser.parse(text),
         {:ok, _} <- Events.workflow_spec_parsed(spec, meta) do
      {:ok, :workflow_committed}
    else
      {:error, e} -> {:error, {:spec_parse_failed, e}}
    end
  end

  defp handle_command(%{line: _} = legacy) do
    # Backwards compat for older tests
    Map.put(legacy, :type, :cmd_ca_rule_parse) |> handle_command()
  end

  defp handle_command(%{spec: _} = legacy) do
    Map.put(legacy, :type, :cmd_workflow_spec_parse) |> handle_command()
  end

  defp handle_command(other), do: {:error, {:unsupported_command, other}}
end
