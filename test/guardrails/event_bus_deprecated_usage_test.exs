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
    ~r/Thunderline\.EventBus\.emit_realtime\(/,
    ~r/Thunderline\.EventBus\.emit_cross_domain\(/,
    ~r/Thunderline\.EventBus\.emit\(/,
    ~r/Thunderline\.EventBus\.broadcast_via_eventbus\(/,
    ~r/Thunderline\.EventBus\.legacy_broadcast\(/,
    ~r/\bEventBus\.emit_realtime\(/,
    ~r/\bEventBus\.emit_cross_domain\(/,
    ~r/\bEventBus\.emit\(/,
    ~r/\blegacy_broadcast\(/,
    ~r/\bbroadcast_via_eventbus\(/
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
          if Enum.any?(@deprecated_patterns, &Regex.match?(&1, content)) do
            [{file, :deprecated_calls_found} | acc]
          else
            acc
          end
      end

    assert offenders == [], "Deprecated EventBus emit* usage detected in: #{inspect(offenders)}"
  end
end
