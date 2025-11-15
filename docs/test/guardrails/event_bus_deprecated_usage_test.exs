defmodule Thunderline.Guardrails.EventBusDeprecatedUsageTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Guardrail: ensure no new usages of deprecated EventBus.emit*/emit_realtime/emit_cross_domain APIs
  creep back into the codebase outside the sanctioned compatibility wrappers inside
  `Thunderline.EventBus` itself.

  If this test fails, replace the legacy call with construction via `Thunderline.Event.new/1`
  and `Thunderline.EventBus.publish_event/1`.
  """

  test "no deprecated EventBus emit* calls outside allowlist" do
    case Thunderline.Dev.EventBusLint.check() do
      :ok ->
        assert true

      {:error, offenders} ->
        flunk("Deprecated EventBus emit* usage detected in: #{inspect(offenders)}")
    end
  end
end
