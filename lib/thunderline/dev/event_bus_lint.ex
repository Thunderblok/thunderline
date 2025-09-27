defmodule Thunderline.Dev.EventBusLint do
  @moduledoc """
  Source-level lint that forbids usage of deprecated `EventBus.emit*` helpers outside
  Thunderflow. Enforced via `mix thunderline.events.lint` and guardrail tests.
  """

  @deprecated_patterns [
    "Thunderline.EventBus.emit_realtime(",
    "Thunderline.EventBus.emit_cross_domain(",
    "Thunderline.EventBus.emit(",
    "Thunderline.EventBus.broadcast_via_eventbus(",
    "Thunderline.EventBus.legacy_broadcast(",
    "EventBus.emit_realtime(",
    "EventBus.emit_cross_domain(",
    "EventBus.emit(",
    "legacy_broadcast(",
    "broadcast_via_eventbus("
  ]

  @allowlist_paths [
    "lib/thunderline/dev/event_bus_lint.ex",
    "lib/thunderline/thunderflow/event_bus.ex"
  ]

  @doc """
  Returns `:ok` when the tree is clean or `{:error, offenders}` with offending paths.
  """
  @spec check(Path.t()) :: :ok | {:error, list(Path.t())}
  def check(root \\ source_root()) do
    files =
      root
      |> Path.join("lib/thunderline/**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, "_test.exs"))

    offenders =
      Enum.reduce(files, [], fn file, acc ->
        if allowlisted?(root, file) do
          acc
        else
          content = File.read!(file)

          if Enum.any?(@deprecated_patterns, &String.contains?(content, &1)) do
            [file | acc]
          else
            acc
          end
        end
      end)

    case offenders do
      [] -> :ok
      _ -> {:error, Enum.sort(offenders)}
    end
  end

  defp source_root do
    Path.expand("../../..", __DIR__)
  end

  defp allowlisted?(root, path) do
    rel = Path.relative_to(path, root)
    rel in @allowlist_paths
  end
end
