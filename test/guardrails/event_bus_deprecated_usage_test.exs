defmodule Thunderline.Guardrails.EventBusDeprecatedUsageTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Guardrail: ensure no new usages of deprecated EventBus.emit*/emit_realtime/emit_cross_domain APIs
  creep back into the codebase outside the sanctioned compatibility wrappers inside
  `Thunderline.EventBus` itself.

  If this test fails, replace the legacy call with construction via `Thunderline.Event.new/1`
  and `Thunderline.EventBus.publish_event/1`.
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

  test "no deprecated EventBus emit* calls outside allowlist" do
    root = Path.expand("../../../", __DIR__)
    lib_path = Path.join(root, "lib/thunderline")

    files =
      lib_path
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, "_test.exs"))

    offenders =
      for file <- files, reduce: [] do
        acc ->
          content = File.read!(file)
          if Enum.any?(@deprecated_patterns, &String.contains?(content, &1)) do
            [{file, :deprecated_calls_found} | acc]
          else
            acc
          end
      end

    assert offenders == [], "Deprecated EventBus emit* usage detected in: #{inspect(offenders)}"
  end
end
