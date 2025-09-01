defmodule Thunderline.Thunderlink.NoPolicyInLinkTest do
  use ExUnit.Case, async: true
  test "no policy usage in Link domain" do
    hits =
      "lib/thunderline/thunderlink"
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.map(&{path, &1})
      end)
      |> Enum.filter(fn {_path, line} -> String.contains?(line, "Policy.") end)
      |> Enum.map(fn {path, line} -> {path, line} end)
    assert hits == []
  end
end
