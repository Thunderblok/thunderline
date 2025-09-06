defmodule Mix.Tasks.Thunderline.Gc do
  use Mix.Task

  @shortdoc "Garbage-collect logs and artifacts (dry-run by default)"

  @moduledoc """
  Garbage-collect logs and artifacts under the project tree.

  By default, performs a dry run and prints what would be deleted.

  Options:
    --category=<logs|artifacts|all>  Category to clean (default: all)
    --age=<Ns|Nm|Nh|Nd|Nw>           Only delete older than age (default: 7d)
    --force                          Actually delete files (disable dry-run)

  Examples:
      mix thunderline.gc
      mix thunderline.gc --category logs --age 24h
      mix thunderline.gc --category artifacts --age 30d --force
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args,
      strict: [category: :string, age: :string, force: :boolean]
    )

    category =
      case Keyword.get(opts, :category, "all") do
        "logs" -> :logs
        "artifacts" -> :artifacts
        _ -> :all
      end

    age = Keyword.get(opts, :age, "7d")
    dry_run? = not Keyword.get(opts, :force, false)

    cutoff = Thunderline.Maintenance.Cleanup.cutoff_from(age)
    candidates = Thunderline.Maintenance.Cleanup.list_candidates(category, cutoff)

    total_bytes = candidates |> Enum.map(fn {_, s, _} -> s end) |> Enum.sum()
    Mix.shell().info("Found #{length(candidates)} candidates (#{format_bytes(total_bytes)}) older than #{age}")

    Enum.each(candidates, fn {path, size, mtime} ->
      Mix.shell().info("  - #{path} (#{format_bytes(size)}; mtime=#{DateTime.to_iso8601(mtime)})")
    end)

    if dry_run? do
      Mix.shell().info("\nDry run only. Pass --force to delete.")
    else
      Mix.shell().info("\nDeleting...")
      result = Thunderline.Maintenance.Cleanup.delete(candidates, false)
      Mix.shell().info("Deleted #{result.count} files (#{format_bytes(result.bytes)}).")

      Enum.each(result.errors, fn {path, reason} ->
        Mix.shell().error("Failed to delete #{path}: #{inspect(reason)}")
      end)
    end
  end

  defp format_bytes(n) when n < 1024, do: "#{n} B"
  defp format_bytes(n) when n < 1024 * 1024, do: :io_lib.format("~.1f KB", [n / 1024]) |> IO.iodata_to_binary()
  defp format_bytes(n) when n < 1024 * 1024 * 1024, do: :io_lib.format("~.1f MB", [n / (1024 * 1024)]) |> IO.iodata_to_binary()
  defp format_bytes(n), do: :io_lib.format("~.1f GB", [n / (1024 * 1024 * 1024)]) |> IO.iodata_to_binary()
end
