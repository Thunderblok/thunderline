defmodule Mix.Tasks.Thunderline.Events.Lint do
  use Mix.Task
  @shortdoc "Validate event name prefixes against reserved taxonomy"
  @reserved ~w(system link flow grid bolt crown block gate)

  @moduledoc """
  Lints event struct literals to ensure names use only approved prefixes.
  Looks for `%Thunderline.Event{name: "..."}` patterns. Extend reserved list as taxonomy evolves.
  """
  def run(_args) do
    files = Path.wildcard("lib/**/*.ex")
    bad =
      files
      |> Enum.flat_map(fn f ->
        body = File.read!(f)
        Regex.scan(~r/%Thunderline\.Event\{[^}]*name:\s*"([^"]+)"/, body)
        |> Enum.flat_map(fn [_, name] ->
          [prefix | _] = String.split(name, ".", parts: 2)
          if prefix in @reserved, do: [], else: [{f, name}]
        end)
      end)
    if bad != [] do
      Mix.raise("Invalid event names:\n" <> Enum.map_join(bad, "\n", fn {f,n} -> "#{f}: #{n}" end))
    end
  end
end
