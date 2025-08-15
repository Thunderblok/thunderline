#!/usr/bin/env elixir

# Broadway Migration Script for Thunderline
# This script helps migrate scattered PubSub.broadcast calls to EventBus.emit patterns

defmodule BroadwayMigrationScript do
  @moduledoc """
  Automated migration script to replace scattered PubSub.broadcast calls
  with structured EventBus.emit calls for Broadway pipeline processing.

  Usage:
    elixir broadway_migration.exs --dry-run  # Preview changes
    elixir broadway_migration.exs --apply    # Apply changes
  """

  def run(args) do
    case args do
      ["--dry-run"] -> run_migration(dry_run: true)
      ["--apply"] -> run_migration(dry_run: false)
      _ ->
        IO.puts("Usage: elixir broadway_migration.exs [--dry-run|--apply]")
        System.halt(1)
    end
  end

  def run_migration(opts) do
    dry_run = Keyword.get(opts, :dry_run, true)

    IO.puts("\n=== Broadway Migration Analysis ===")
    IO.puts("Dry run: #{dry_run}")

    # Find all Elixir files with PubSub.broadcast calls
    files_to_migrate = find_files_with_pubsub_broadcasts()

    IO.puts("\nFound #{length(files_to_migrate)} files with PubSub.broadcast calls:")

    total_replacements = 0

    for file_path <- files_to_migrate do
      IO.puts("\n--- Analyzing #{file_path} ---")

      case analyze_and_migrate_file(file_path, dry_run) do
        {:ok, replacements} when replacements > 0 ->
          IO.puts("  ✅ #{replacements} broadcasts migrated")
          total_replacements = total_replacements + replacements

        {:ok, 0} ->
          IO.puts("  ⚪ No migrations needed")

        {:error, reason} ->
          IO.puts("  ❌ Error: #{reason}")
      end
    end

    IO.puts("\n=== Migration Summary ===")
    IO.puts("Total files analyzed: #{length(files_to_migrate)}")
    IO.puts("Total broadcasts migrated: #{total_replacements}")

    if dry_run do
      IO.puts("\n🔍 This was a dry run. Use --apply to make changes.")
    else
      IO.puts("\n✅ Migration completed! Broadway pipelines now handle events.")
      IO.puts("Next steps:")
      IO.puts("1. Run tests to verify functionality")
      IO.puts("2. Monitor Broadway pipeline performance")
      IO.puts("3. Tune pipeline parameters based on load")
    end
  end

  defp find_files_with_pubsub_broadcasts do
    {output, 0} = System.cmd("grep", [
      "-r",
      "-l",
      "--include=*.ex",
      "PubSub\\.broadcast\\|Phoenix\\.PubSub\\.broadcast",
      "lib/"
    ], cd: "/home/mo/Thunderline")

    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.contains?(&1, "thunderflow/pipelines/")) # Skip our Broadway pipelines
    |> Enum.reject(&String.contains?(&1, "event_bus.ex")) # Skip EventBus itself
  end

  defp analyze_and_migrate_file(file_path, dry_run) do
    full_path = Path.join("/home/mo/Thunderline", file_path)

    case File.read(full_path) do
      {:ok, content} ->
        {new_content, replacements} = migrate_pubsub_calls(content, file_path)

        if replacements > 0 and not dry_run do
          case File.write(full_path, new_content) do
            :ok -> {:ok, replacements}
            {:error, reason} -> {:error, "Failed to write: #{reason}"}
          end
        else
          {:ok, replacements}
        end

      {:error, reason} ->
        {:error, "Failed to read: #{reason}"}
    end
  end

  defp migrate_pubsub_calls(content, file_path) do
    lines = String.split(content, "\n")
    {migrated_lines, replacements} = migrate_lines(lines, file_path, 0, [])

    new_content = Enum.join(migrated_lines, "\n")
    {new_content, replacements}
  end

  defp migrate_lines([], _file_path, replacements, acc) do
    {Enum.reverse(acc), replacements}
  end

  defp migrate_lines([line | rest], file_path, replacements, acc) do
    case migrate_line(line, file_path) do
      {:migrated, new_line} ->
        IO.puts("    📝 #{String.trim(line)}")
        IO.puts("    ➡️  #{String.trim(new_line)}")
        migrate_lines(rest, file_path, replacements + 1, [new_line | acc])

      {:unchanged, line} ->
        migrate_lines(rest, file_path, replacements, [line | acc])
    end
  end

  defp migrate_line(line, file_path) do
    cond do
      # Match: Phoenix.PubSub.broadcast(Thunderline.PubSub, topic, payload)
      String.contains?(line, "Phoenix.PubSub.broadcast(Thunderline.PubSub,") ->
        new_line = replace_phoenix_pubsub_pattern(line, file_path)
        {:migrated, new_line}

      # Match: PubSub.broadcast(pubsub, topic, payload)
      String.contains?(line, "PubSub.broadcast(") ->
        new_line = replace_pubsub_pattern(line, file_path)
        {:migrated, new_line}

      true ->
        {:unchanged, line}
    end
  end

  defp replace_phoenix_pubsub_pattern(line, file_path) do
    # Extract indentation
    indentation = String.duplicate(" ", String.length(line) - String.length(String.trim_leading(line)))

    domain = extract_domain_from_path(file_path)

    # Replace Phoenix.PubSub.broadcast with EventBus call
    line
    |> String.replace(
      ~r/Phoenix\.PubSub\.broadcast\(Thunderline\.PubSub,\s*([^,]+),\s*(.+)\)/,
      "Thunderline.EventBus.emit(:#{domain}_event, %{topic: \\1, payload: \\2, source: \"#{domain}\"})"
    )
  end

  defp replace_pubsub_pattern(line, file_path) do
    # Extract indentation
    indentation = String.duplicate(" ", String.length(line) - String.length(String.trim_leading(line)))

    domain = extract_domain_from_path(file_path)

    # Replace PubSub.broadcast with EventBus call
    line
    |> String.replace(
      ~r/PubSub\.broadcast\(([^,]+),\s*([^,]+),\s*(.+)\)/,
      "Thunderline.EventBus.emit(:#{domain}_event, %{topic: \\2, payload: \\3, source: \"#{domain}\"})"
    )
  end

  defp extract_domain_from_path(file_path) do
    cond do
      String.contains?(file_path, "thunderchief") -> "thunderchief"
      String.contains?(file_path, "thundercom") -> "thundercom"
      String.contains?(file_path, "thunderblock") -> "thunderblock"
      String.contains?(file_path, "thundergrid") -> "thundergrid"
      String.contains?(file_path, "thunderbridge") -> "thunderbridge"
      String.contains?(file_path, "thunderbolt") -> "thunderbolt"
      String.contains?(file_path, "thunderlink") -> "thunderlink"
      String.contains?(file_path, "thunderlane") -> "thunderlane"
      String.contains?(file_path, "thundervault") -> "thundervault"
      true -> "thunderline"
    end
  end
end

# Run the script
case System.argv() do
  args -> BroadwayMigrationScript.run(args)
end
