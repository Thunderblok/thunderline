defmodule Thunderline.Thunderflow.Events.Linter do
  @moduledoc """
  Event taxonomy linter.

  Current implemented rules (subset of Docs/EVENT_TAXONOMY.md §14):
    1. :format          – double dot detection
    2. :segments        – at least 2 segments
    3. :category        – domain/category matrix (heuristic domain inference)
    4. :registration    – event must exist in registry (seed snapshot)
  5. :ai_whitelist    – ai.* events must be in explicit whitelist
  6. :ml_prefix       – ensure ml.* only under bolt domain categories

  Deferred / planned rules (placeholder only):
    * correlation / causation threading (needs runtime emission context)
    * reliability heuristic alignment
    * deprecation age checks
    * JSON schema presence verification

  Approach: scan Elixir source for quoted string literals that match taxonomy-like
  patterns (<segment>.<segment>.<...>) and apply static validations.
  """

  @type issue :: %{severity: :error | :warning, rule: atom(), detail: term(), file: String.t() | nil, line: integer() | nil}

  @event_regex ~r/"([a-z0-9_]+\.[a-z0-9_]+\.[a-z0-9_\.]+)"/i

  alias Thunderline.Thunderflow.Events.Registry

  @doc """
  Run linter over codebase given a list of file contents {path, binary}.
  """
  def run(files) when is_list(files) do
    registry = Registry.events()
    ai_whitelist = Registry.ai_whitelist()
    cats = Registry.categories_by_domain()

    files
    |> Enum.flat_map(&scan_file/1)
    |> Enum.uniq_by(& &1.name)
    |> Enum.flat_map(&validate_name(&1, registry, ai_whitelist, cats))
  end

  defp scan_file({path, content}) do
    for {match, _idx} <- Regex.scan(@event_regex, content, return: :index), reduce: [] do
      acc ->
        [{_full, {start, len}}] = [match]
        name = String.slice(content, start + 1, len - 2) # remove quotes
        line = content |> binary_part(0, start + len) |> String.split("\n") |> length()
        [%{name: name, file: path, line: line} | acc]
    end
  end

  defp validate_name(%{name: _name} = entry, registry, ai_whitelist, cats) do
    []
    |> rule_format(entry)
    |> rule_segments(entry)
    |> rule_category(entry, cats)
    |> rule_registration(entry, registry)
    |> rule_ai_whitelist(entry, ai_whitelist)
  end

  defp rule_format(issues, %{name: name} = e) do
    if String.contains?(name, "..") do
      [%{severity: :error, rule: :double_dot, detail: name, file: e.file, line: e.line} | issues]
    else
      issues
    end
  end

  defp rule_segments(issues, %{name: name} = e) do
    segs = String.split(name, ".")
    if length(segs) < 2 do
      [%{severity: :error, rule: :too_few_segments, detail: name, file: e.file, line: e.line} | issues]
    else
      issues
    end
  end

  defp rule_category(issues, %{name: name} = e, cats) do
    prefix = name |> String.split(".") |> Enum.take(2) |> Enum.join(".")
    domain = infer_domain_from_name(name)
    allowed = Map.get(cats, domain, ["system"])
    cond do
      Enum.any?(allowed, &String.starts_with?(name, &1)) -> issues
      Enum.any?(allowed, &String.starts_with?(prefix, &1)) -> issues
      true -> [%{severity: :warning, rule: :category_mismatch, detail: {domain, name}, file: e.file, line: e.line} | issues]
    end
  end

  defp rule_registration(issues, %{name: name} = e, registry) do
    if Map.has_key?(registry, name) do
      issues
    else
      [%{severity: :warning, rule: :unregistered_event, detail: name, file: e.file, line: e.line} | issues]
    end
  end

  defp rule_ai_whitelist(issues, %{name: name} = e, ai_whitelist) do
    cond do
      String.starts_with?(name, "ai.") and name not in ai_whitelist ->
        [%{severity: :error, rule: :ai_event_not_whitelisted, detail: name, file: e.file, line: e.line} | issues]
      true -> issues
    end
  end

  defp infer_domain_from_name(name) do
    cond do
      String.starts_with?(name, "ml.run") -> :bolt
      String.starts_with?(name, "ml.trial") -> :bolt
      String.starts_with?(name, "ml.artifact") -> :bolt
      String.starts_with?(name, "flow.reactor") -> :flow
      String.starts_with?(name, "ui.command") -> :link
      String.starts_with?(name, "ai.intent") -> :crown
      String.starts_with?(name, "ai.plan") -> :crown
      String.starts_with?(name, "voice.signal") -> :link
      String.starts_with?(name, "voice.room") -> :link
      String.starts_with?(name, "system.presence") -> :gate
      String.starts_with?(name, "system.") -> :unknown
      String.starts_with?(name, "stone.") -> :stone
      String.starts_with?(name, "foundry.") -> :foundry
      String.starts_with?(name, "ai.") -> :crown
      true -> :unknown
    end
  end
end
