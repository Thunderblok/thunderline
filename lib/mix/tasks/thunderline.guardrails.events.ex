defmodule Mix.Tasks.Thunderline.Guardrails.Events do
  use Mix.Task
  @shortdoc "Fail if publish_event/1 calls are unchecked"

  @moduledoc """
  Scans lib/ for `publish_event(` usage that does not have an accompanying
  pattern match on {:ok, _} or {:error, _} in the surrounding text. This is a
  heuristic; improves safety by banning fire-and-forget silent failures.
  """
  def run(_args) do
    files = Path.wildcard("lib/**/*.ex")
    offenders =
      for f <- files,
          body = File.read!(f),
          String.contains?(body, "publish_event("),
          not (String.contains?(body, "{:ok") and String.contains?(body, "{:error")) do
        f
      end
    if offenders != [] do
      Mix.raise("Unchecked publish_event/1 calls in:\n" <> Enum.join(offenders, "\n"))
    end
  end
end
