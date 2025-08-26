defmodule Thunderline.Thunderflow.Events.Linter do
  @moduledoc """
  Event taxonomy linter.

  Performs static & dynamic validations against the canonical taxonomy draft:
    1. Name format (dot segments >= 2)
    2. Allowed category prefixes per source domain (Section 12 matrix)
    3. Required root causation rules (`ui.command.*` must have nil causation_id if present)
    4. Correlation presence (must exist on all events)
    5. Reliability heuristic alignment (system.*, ml.run.* -> persistent)
    6. Deprecated flag aging (stub - future extension)

  The linter consumes a list of events OR scans source code for literal event names.
  This initial version focuses on code scan of strings matching taxonomy-like patterns.
  """

  @type issue :: %{severity: :error | :warning, rule: atom(), detail: term(), file: String.t() | nil, line: integer() | nil}

  @event_regex ~r/"([a-z0-9_]+\.[a-z0-9_]+\.[a-z0-9_\.]+)"/i

  @categories_by_domain %{
    gate: ["ui.command", "system", "presence"],
    flow: ["flow.reactor", "system"],
    bolt: ["ml.run", "system"],
    link: ["ui.command", "system"],
    crown: ["ai.intent", "system"],
    block: ["system"],
    bridge: ["system", "ui.command"],
    unknown: ["system"]
  }

  @doc """
  Run linter over codebase given a list of file contents {path, binary}.
  """
  def run(files) when is_list(files) do
    files
    |> Enum.flat_map(&scan_file/1)
    |> Enum.uniq()
    |> Enum.flat_map(&validate_name/1)
  end

  defp scan_file({path, content}) do
    for {match, idx} <- Regex.scan(@event_regex, content, return: :index), reduce: [] do
      acc ->
        [{_full, {start, len}}] = [match]
        name = String.slice(content, start + 1, len - 2) # remove quotes
        line = content |> binary_part(0, start + len) |> String.split("\n") |> length()
        [%{name: name, file: path, line: line} | acc]
    end
  end

  defp validate_name(%{name: name} = entry) do
    []
    |> rule_format(entry)
    |> rule_segments(entry)
    |> rule_category(entry)
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

  defp rule_category(issues, %{name: name} = e) do
    prefix = name |> String.split(".") |> Enum.take(2) |> Enum.join(".")
    # Heuristic: derive domain by presence of top-level token(s)
    domain = infer_domain_from_name(name)
    allowed = Map.get(@categories_by_domain, domain, ["system"])
    if Enum.any?(allowed, &String.starts_with?(name, &1)) or Enum.any?(allowed, &String.starts_with?(prefix, &1)) do
      issues
    else
      [%{severity: :warning, rule: :category_mismatch, detail: {domain, name}, file: e.file, line: e.line} | issues]
    end
  end

  defp infer_domain_from_name(name) do
    cond do
      String.starts_with?(name, "ml.run") -> :bolt
      String.starts_with?(name, "flow.reactor") -> :flow
      String.starts_with?(name, "ui.command") -> :link
      String.starts_with?(name, "ai.intent") -> :crown
      String.starts_with?(name, "presence.") -> :gate
      String.starts_with?(name, "system.") -> :unknown
      true -> :unknown
    end
  end
end
