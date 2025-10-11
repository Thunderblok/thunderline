defmodule Mix.Tasks.Thunderline.Events.Lint do
  use Mix.Task
  @shortdoc "Validate event name prefixes against reserved taxonomy"
  @reserved ~w(system ui audit ai reactor flow grid bolt crown block gate)

  @moduledoc """
  Lints Event literals used in code for basic taxonomy compliance.
  Checks:
    - name has at least 2 segments
    - first segment is in reserved/allowed families (@reserved)
    - if literal taxonomy_version/event_version keys appear, they must be positive integers

  Options:
    --format=json | text (default text)
  """
  def run(args) do
    format = if Enum.any?(args, &(&1 == "--format=json")), do: :json, else: :text
    files = Path.wildcard("lib/**/*.ex")

    findings =
      files
      |> Enum.flat_map(&lint_file/1)
      |> Kernel.++(deprecated_emit_findings())

    if findings != [] do
      output(findings, format)
      Mix.raise("Event lint failed with #{length(findings)} issue(s)")
    end
  end

  defp lint_file(path) do
    body = File.read!(path)
    # Find struct literals and capture name + optional versions
    Regex.scan(~r/%Thunderline\.Event\{([^}]*)\}/, body)
    |> Enum.flat_map(fn [full, inner] ->
      name = capture_string(inner, ~r/name:\s*"([^"]+)"/)
      tax_v = capture_int(inner, ~r/taxonomy_version:\s*(\d+)/)
      ev_v = capture_int(inner, ~r/event_version:\s*(\d+)/)

      has_name_field = String.contains?(inner, "name:")

      issues =
        []
        |> maybe_issue(has_name_field and is_nil(name), :missing_name, name)
        |> maybe_issue(is_binary(name) and length(String.split(name, ".")) < 2, :short_name, name)
        |> maybe_issue(is_binary(name) and not allowed_prefix?(name), :bad_prefix, name)
        |> maybe_issue(
          inner =~ ~r/taxonomy_version:/ and (tax_v == nil or tax_v < 1),
          :bad_taxonomy_version,
          inspect(tax_v)
        )
        |> maybe_issue(
          inner =~ ~r/event_version:/ and (ev_v == nil or ev_v < 1),
          :bad_event_version,
          inspect(ev_v)
        )

      Enum.map(issues, fn issue ->
        %{file: path, issue: issue, snippet: String.slice(full, 0, 200)}
      end)
    end)
  end

  defp allowed_prefix?(name) do
    [prefix | _] = String.split(name, ".", parts: 2)
    prefix in @reserved
  end

  defp capture_string(s, regex) do
    case Regex.run(regex, s) do
      [_, v] -> v
      _ -> nil
    end
  end

  defp capture_int(s, regex) do
    case Regex.run(regex, s) do
      [_, v] -> String.to_integer(v)
      _ -> nil
    end
  end

  defp maybe_issue(list, false, _type, _val), do: list
  defp maybe_issue(list, true, type, val), do: [%{type: type, value: val} | list]

  defp output(findings, :json), do: IO.puts(Jason.encode!(findings))

  defp output(findings, :text) do
    Enum.each(findings, fn %{file: f, issue: %{type: t, value: v}} ->
      Mix.shell().error("[event-lint] #{f}: #{t} #{inspect(v)}")
    end)
  end

  defp deprecated_emit_findings do
    case Thunderline.Dev.EventBusLint.check() do
      :ok ->
        []

      {:error, offenders} ->
        Enum.map(offenders, fn path ->
          %{
            file: path,
            issue: %{
              type: :deprecated_emit_helper,
              value: "replace with Thunderline.Thunderflow.EventBus.publish_event/1"
            },
            snippet: nil
          }
        end)
    end
  end
end
