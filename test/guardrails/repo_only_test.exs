defmodule Thunderline.Guardrails.RepoOnlyTest do
  use ExUnit.Case, async: true
  test "no direct Repo calls outside Block (allowing resource repo declarations & application supervision)" do
    offenders =
      "lib/thunderline"
      |> Path.join("**/*.ex")
      |> Path.wildcard()
  |> Enum.reject(&String.contains?(&1, "/thunderblock/"))
      |> Enum.flat_map(fn path ->
        File.read!(path)
        |> String.split("\n")
        |> Enum.map(&{path, &1})
      end)
      |> Enum.filter(fn {path, line} ->
        String.contains?(line, "Repo.") and
          not String.match?(line, ~r/\brepo\s+Thunderline\.Repo\b/) and
          not String.contains?(path, "/application.ex") and
          not String.contains?(path, "/dev/")
      end)
      |> Enum.map(fn {p, l} -> p <> ":" <> l end)

    assert offenders == []
  end
end
