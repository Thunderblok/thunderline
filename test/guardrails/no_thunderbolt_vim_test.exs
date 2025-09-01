defmodule Guardrails.NoThunderboltVIMTest do
  use ExUnit.Case, async: true

  test "no Thunderbolt VIM wrappers" do
    hits =
      "lib/thunderline"
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&(File.read!(&1) |> String.split("\n")))
      |> Enum.filter(&String.contains?(&1, "Thunderline.Thunderbolt.VIM"))

    assert hits == []
  end
end
