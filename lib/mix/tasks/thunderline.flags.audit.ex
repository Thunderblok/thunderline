defmodule Mix.Tasks.Thunderline.Flags.Audit do
  @shortdoc "Audit feature flag usage vs configured flags"

  @moduledoc """
  Scans the codebase for `Thunderline.Feature.enabled?/1,2` calls and compares
  against configured flags in `:thunderline, :features`.

  ## Output

  Displays:
    * All configured feature flags with their current values
    * All Feature.enabled?/1,2 calls found in code with locations
    * Warnings for undocumented flags (used in code but not configured)
    * Warnings for unused flags (configured but not referenced in code)

  ## Options

    * `--json` - Output as JSON for CI integration
    * `--strict` - Exit with code 1 if any warnings found

  ## Examples

      mix thunderline.flags.audit
      mix thunderline.flags.audit --strict
      mix thunderline.flags.audit --json

  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean, strict: :boolean])
    json_mode = Keyword.get(opts, :json, false)
    strict_mode = Keyword.get(opts, :strict, false)

    # Start minimum apps needed to read config
    Application.ensure_all_started(:logger)

    configured_flags = get_configured_flags()
    code_usages = scan_code_usages()

    used_flags = code_usages |> Enum.map(& &1.flag) |> Enum.uniq()
    configured_flag_names = Map.keys(configured_flags)

    undocumented = used_flags -- configured_flag_names
    unused = configured_flag_names -- used_flags

    result = %{
      configured: configured_flags,
      usages: code_usages,
      undocumented: undocumented,
      unused: unused,
      summary: %{
        configured_count: map_size(configured_flags),
        usage_count: length(code_usages),
        unique_flags_used: length(used_flags),
        undocumented_count: length(undocumented),
        unused_count: length(unused)
      }
    }

    if json_mode do
      IO.puts(Jason.encode!(result, pretty: true))
    else
      print_report(result)
    end

    if strict_mode and (length(undocumented) > 0 or length(unused) > 0) do
      System.halt(1)
    end
  end

  defp get_configured_flags do
    # Read from config files - mix tasks don't have app started by default
    configs =
      ["config/config.exs", "config/dev.exs", "config/prod.exs", "config/test.exs"]
      |> Enum.filter(&File.exists?/1)
      |> Enum.flat_map(&extract_flags_from_config/1)
      |> Enum.reduce(%{}, fn {flag, value, source}, acc ->
        Map.update(acc, flag, %{value: value, sources: [source]}, fn existing ->
          %{existing | sources: [source | existing.sources]}
        end)
      end)

    configs
  end

  defp extract_flags_from_config(path) do
    content = File.read!(path)

    # Match patterns like: config :thunderline, :features, key: value, ...
    regex = ~r/config\s+:thunderline,\s*:features,\s*([^\n]+(?:\n\s+[^c\n][^\n]*)*)/

    case Regex.run(regex, content) do
      [_, flags_str] ->
        # Parse keyword-like syntax: flag: value, flag2: value2
        ~r/(\w+):\s*(true|false)/
        |> Regex.scan(flags_str)
        |> Enum.map(fn [_, flag, value] ->
          {String.to_atom(flag), value == "true", path}
        end)

      nil ->
        []
    end
  end

  defp scan_code_usages do
    lib_path = Path.join(File.cwd!(), "lib")
    this_file = "lib/mix/tasks/thunderline.flags.audit.ex"

    lib_path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&(Path.relative_to_cwd(&1) == this_file))
    |> Enum.flat_map(&scan_file/1)
    |> Enum.sort_by(& &1.flag)
  end

  defp scan_file(path) do
    content = File.read!(path)
    relative_path = Path.relative_to_cwd(path)

    # Match Feature.enabled?(:flag) or Feature.enabled?(:flag, opts)
    # Also match Thunderline.Feature.enabled?
    regex = ~r/(?:Thunderline\.)?Feature\.enabled\?\(:([\w]+)/

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      Regex.scan(regex, line)
      |> Enum.map(fn [_full, flag] ->
        %{
          flag: String.to_atom(flag),
          file: relative_path,
          line: line_num,
          context: String.trim(line)
        }
      end)
    end)
  end

  defp print_report(result) do
    IO.puts("\n" <> String.duplicate("═", 60))
    IO.puts("  ⚡ THUNDERLINE FEATURE FLAG AUDIT")
    IO.puts(String.duplicate("═", 60))

    # Configured flags section
    IO.puts("\n📋 CONFIGURED FLAGS (#{result.summary.configured_count}):")
    IO.puts(String.duplicate("─", 40))

    if map_size(result.configured) == 0 do
      IO.puts("  (none found)")
    else
      result.configured
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.each(fn {flag, info} ->
        status = if info.value, do: "✅", else: "❌"
        sources = info.sources |> Enum.map(&Path.basename/1) |> Enum.join(", ")
        IO.puts("  #{status} :#{flag} => #{info.value}  (#{sources})")
      end)
    end

    # Usage section
    IO.puts("\n🔍 CODE USAGES (#{result.summary.usage_count} calls, #{result.summary.unique_flags_used} unique flags):")
    IO.puts(String.duplicate("─", 40))

    if length(result.usages) == 0 do
      IO.puts("  (no usages found)")
    else
      result.usages
      |> Enum.group_by(& &1.flag)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.each(fn {flag, usages} ->
        IO.puts("  :#{flag} (#{length(usages)} usages):")

        usages
        |> Enum.take(5)
        |> Enum.each(fn usage ->
          IO.puts("    └─ #{usage.file}:#{usage.line}")
        end)

        remaining = length(usages) - 5

        if remaining > 0 do
          IO.puts("    └─ ... and #{remaining} more")
        end
      end)
    end

    # Warnings section
    has_warnings = length(result.undocumented) > 0 or length(result.unused) > 0

    if has_warnings do
      IO.puts("\n⚠️  WARNINGS:")
      IO.puts(String.duplicate("─", 40))

      if length(result.undocumented) > 0 do
        IO.puts("  🚨 UNDOCUMENTED FLAGS (used in code but not in config):")

        Enum.each(result.undocumented, fn flag ->
          IO.puts("    • :#{flag}")
        end)
      end

      if length(result.unused) > 0 do
        IO.puts("  💤 UNUSED FLAGS (in config but not referenced in code):")

        Enum.each(result.unused, fn flag ->
          IO.puts("    • :#{flag}")
        end)
      end
    else
      IO.puts("\n✨ No warnings - all flags accounted for!")
    end

    IO.puts("\n" <> String.duplicate("═", 60) <> "\n")
  end
end
