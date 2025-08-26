defmodule Mix.Tasks.Thunderline.Actions.Export do
  use Mix.Task
  @shortdoc "Export Thunderline action/tool metadata (JSON)"
  @moduledoc """
  Scans configured Ash domains for create/update/destroy/read actions and emits a
  machine-consumable JSON file (default: tmp/tools.json).

  This is an initial skeleton to satisfy HC roadmap (Action -> Tool layer).
  Future improvements:
    * Argument/return schema derivation (JSON Schema) using resource DSL
    * Filtering sensitive actions via allow/deny lists
    * Version tagging & diffing
  """
  def run(args) do
    Mix.Task.run("app.start")
    path = Keyword.get(parse_args(args), :out, "tmp/tools.json")
    domains = Application.get_env(:thunderline, :ash_domains, [])

    tools =
      domains
      |> Enum.flat_map(&actions_for_domain/1)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{generated_at: DateTime.utc_now(), tools: tools}, pretty: true))
    Mix.shell().info("Exported #{length(tools)} tools to #{path}")
  end

  defp parse_args(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [out: :string])
    opts
  end

  defp actions_for_domain(domain) do
    resources = Ash.Domain.Info.resources(domain)
    for resource <- resources, action <- Ash.Resource.Info.actions(resource) do
      %{
        name: tool_name(resource, action),
        resource: inspect(resource),
        action: action.name,
        type: action.type,
        description: action.description,
        accepts: Enum.map(action.accept || [], &to_string/1),
        arguments: Enum.map(action.arguments || [], & &1.name),
        metadata: %{domain: inspect(domain), version: 1}
      }
    end
  end

  defp tool_name(resource, action) do
    [resource |> Module.split() |> List.last() |> Macro.underscore(), to_string(action.name)]
    |> Enum.join(".")
  end
end
