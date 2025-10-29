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
    - correlation_id should be explicitly provided for better traceability (warning)

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

    warnings =
      files
      |> lint_event_new_calls()

    if findings != [] do
      output(findings, format)
      Mix.raise("Event lint failed with #{length(findings)} issue(s)")
    end

    if warnings != [] do
      output_warnings(warnings, format)

      Mix.shell().info(
        "\n[event-lint] #{length(warnings)} warning(s) - Consider explicitly providing correlation_id for better traceability"
      )
    end
  end

  defp lint_file(path) do
    body = File.read!(path)
    # Find struct literals and capture name + optional versions
    # Skip empty struct literals (type annotations like %Thunderline.Event{})
    # Skip documentation examples with ... ellipsis
    Regex.scan(~r/%Thunderline\.Event\{([^}]+)\}/, body)
    |> Enum.flat_map(fn [full, inner] ->
      # Skip if:
      # - inner is empty/whitespace (type annotation)
      # - contains ... (doc example)
      # - contains `type:` but no `name:` (likely legacy doc example)
      # - full match contains iex> (doc test)
      is_doc_example =
        String.trim(inner) == "" ||
          String.contains?(inner, "...") ||
          String.contains?(full, "iex>") ||
          (String.contains?(inner, "type:") && !String.contains?(inner, "name:"))

      if is_doc_example do
        []
      else
        name = capture_string(inner, ~r/name:\s*"([^"]+)"/)
        tax_v = capture_int(inner, ~r/taxonomy_version:\s*(\d+)/)
        ev_v = capture_int(inner, ~r/event_version:\s*(\d+)/)

        issues =
          []
          |> maybe_issue(name == nil, :missing_name, name)
          |> maybe_issue(name != nil && length(String.split(name, ".")) < 2, :short_name, name)
          |> maybe_issue(name != nil && not allowed_prefix?(name), :bad_prefix, name)
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
      end
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

  defp output_warnings(warnings, :json), do: IO.puts(Jason.encode!(warnings))

  defp output_warnings(warnings, :text) do
    Enum.each(warnings, fn %{file: f} ->
      Mix.shell().info("[event-lint:warning] #{f}: missing explicit correlation_id")
    end)
  end

  defp lint_event_new_calls(files) do
    files
    |> Enum.flat_map(fn path ->
      body = File.read!(path)

      # Match Thunderline.Event.new(...) calls
      Regex.scan(~r/Thunderline\.Event\.new[!]?\s*\(([^)]+)\)/, body)
      |> Enum.flat_map(fn [full_match, args] ->
        # Check if correlation_id is explicitly provided
        has_correlation_id =
          String.contains?(args, "correlation_id:") ||
            String.contains?(args, ":correlation_id")

        if has_correlation_id do
          []
        else
          [
            %{
              file: path,
              issue: %{
                type: :missing_explicit_correlation_id,
                value: "Consider explicitly providing correlation_id for better traceability"
              },
              snippet: String.slice(full_match, 0, 100)
            }
          ]
        end
      end)
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
