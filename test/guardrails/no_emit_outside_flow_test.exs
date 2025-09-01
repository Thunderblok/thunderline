defmodule Guardrails.NoEmitOutsideFlowTest do
  use ExUnit.Case, async: true

  test "no EventBus.emit outside Flow" do
    hits =
      "lib/thunderline"
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "/thunderflow/"))
      |> Enum.flat_map(&(File.read!(&1) |> String.split("\n")))
      |> Enum.filter(&String.contains?(&1, "EventBus.emit"))

    assert hits == []
  end
end
