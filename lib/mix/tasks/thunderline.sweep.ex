defmodule Mix.Tasks.Thunderline.Sweep do
  use Mix.Task

  @shortdoc "Sweep codebase for duplicate Ash resources and non-Ising optimization modules"

  @moduledoc """
  Performs a repository sweep to:
    1) Identify duplicate Ash resource modules by basename (e.g., ModelArtifact in multiple paths)
    2) Flag non-Ising optimization modules for review (keep Ising*, flag others)

  Options:
    --format=<text|json>   Output format (default: text)

  This is a read-only task that prints a report to stdout.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [format: :string])
    format = Keyword.get(opts, :format, "text")

    resources = scan_resources()
    dupes = find_dupes(resources)
    non_ising = find_non_ising_optimizations()

    report = %{
      duplicates: dupes,
      non_ising: non_ising
    }

    case format do
      "json" -> IO.puts(Jason.encode_to_iodata!(report))
      _ -> print_text(report)
    end
  end

  defp scan_resources do
    pattern = Path.join([File.cwd!(), "lib", "**", "*.ex"])
    for file <- Path.wildcard(pattern, match_dot: true),
        {:ok, bin} = File.read(file),
        String.contains?(bin, "use Ash.Resource"),
        do: {file, module_basename(bin)}
  end

  defp module_basename(source) do
    case Regex.run(~r/(?:defmodule\s+)([A-Za-z0-9_.]+)/, source, capture: :all_but_first) do
      [mod] -> mod |> String.split(".") |> List.last()
      _ -> "Unknown"
    end
  end

  defp find_dupes(resources) do
    resources
    |> Enum.group_by(fn {_file, base} -> base end)
    |> Enum.filter(fn {_base, list} -> length(list) > 1 end)
    |> Enum.map(fn {base, list} ->
      %{basename: base, files: Enum.map(list, &elem(&1, 0))}
    end)
  end

  defp find_non_ising_optimizations do
    pattern = Path.join([File.cwd!(), "lib", "thunderline", "thunderbolt", "resources", "*.ex"])
    files = Path.wildcard(pattern)

    files
    |> Enum.filter(fn path -> String.contains?(path, "/ising_") end)
    |> Enum.reject(fn path -> String.contains?(path, "/ising_") end)
    |> Kernel.++(other_opt_modules())
  end

  defp other_opt_modules do
    pattern = Path.join([File.cwd!(), "lib", "thunderline", "thunderbolt", "**", "*.ex"])
    Path.wildcard(pattern)
    |> Enum.filter(fn path ->
      name = Path.basename(path)
      # Flag any optimization or HPO related modules that are not Ising*
      String.match?(name, ~r/(optimization|optimizer|anneal|genetic|bayes|tpe)/i) and
        not String.match?(name, ~r/^ising_/i)
    end)
  end

  defp print_text(%{duplicates: dupes, non_ising: non_ising}) do
    if dupes == [] do
      Mix.shell().info("No duplicate Ash resources found by basename.")
    else
      Mix.shell().info("Duplicate Ash resources detected:")
      Enum.each(dupes, fn %{basename: base, files: files} ->
        Mix.shell().info("  - #{base}:")
        Enum.each(files, &Mix.shell().info("      * #{&1}"))
      end)
    end

    Mix.shell().info("")

    if non_ising == [] do
      Mix.shell().info("No non-Ising optimization modules flagged.")
    else
      Mix.shell().info("Non-Ising optimization modules to review:")
      Enum.each(non_ising, &Mix.shell().info("  - #{&1}"))
    end
  end
end
