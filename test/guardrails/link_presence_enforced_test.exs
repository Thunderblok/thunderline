defmodule Guardrails.LinkPresenceEnforcedTest do
  use ExUnit.Case, async: true
  @tag :guard
  test "no link mutations without presence enforcer" do
    offenders =
      Path.wildcard("lib/thunderline/thunderlink/**/*.ex")
      |> Enum.flat_map(fn f ->
        body = File.read!(f)
        if Regex.match?(~r/Message\.create\(|join_channel\(|send_message\(/, body) and
             not String.contains?(body, "with_presence(") do
          [f]
        else
          []
        end
      end)

    assert offenders == [], "Presence not enforced in: #{inspect(offenders)}"
  end
end
