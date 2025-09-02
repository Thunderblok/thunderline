defmodule Mix.Tasks.Thunderline.Events.TaxonomyLint do
  use Mix.Task
  @shortdoc "Lint event taxonomy usage in codebase"
  @moduledoc """
  Scans Elixir source files for event names (string literals matching taxonomy pattern)
  and validates against taxonomy constraints.

  This is an initial automated support for HC-03.

  Exit with non‑zero status if any :error severity issues are found unless
  `--no-strict` is passed (then only prints warnings/errors but always exits 0).

  Options:
    --no-strict   Do not fail build on errors (report only)
    --format json Produce JSON output (default: human)
  """
  alias Thunderline.Thunderflow.Events.Linter

  @switches [strict: :boolean, format: :string]
  @default_switches [strict: true, format: "human"]

  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _args, _invalid} = OptionParser.parse(argv, switches: @switches)
    opts = Keyword.merge(@default_switches, opts)

    files = source_files()
    file_contents = Enum.map(files, &{&1, File.read!(&1)})

    issues = Linter.run(file_contents)

    emit_report(issues, opts[:format])

    if opts[:strict] && Enum.any?(issues, & &1.severity == :error) do
      Mix.raise("Event taxonomy lint failed (#{Enum.count(issues, & &1.severity == :error)} errors)")
    end
  end

  defp source_files do
    # Limit to lib/ for now (could expand to test/ optionally)
    Path.wildcard("lib/**/*.ex")
  end

  defp emit_report(issues, "json") do
    IO.puts(Jason.encode!(%{issues: issues, count: length(issues)}, pretty: true))
  end
  defp emit_report(issues, _human) do
    if issues == [] do
      Mix.shell().info("No event taxonomy issues found")
    else
      Mix.shell().info("Event taxonomy issues (#{length(issues)}):")
      Enum.each(issues, fn i ->
        Mix.shell().info("  [#{String.upcase(to_string(i.severity))}] #{i.rule} #{inspect(i.detail)} (#{i.file}:#{i.line})")
      end)
    end
  end
end
