defmodule Mix.Tasks.Thunderline.Ml.Validate do
  @moduledoc """
  Validate Cerebros bridge readiness.

  Runs a suite of checks verifying the `:ml_nas` feature flag, bridge
  configuration, filesystem paths, and python executable accessibility.

      mix thunderline.ml.validate

  Options:

    * `--require-enabled` – treat a disabled bridge config as an error instead of
      a warning.
    * `--json` – emit machine-readable JSON output.
  """
  use Mix.Task

  alias Thunderline.Thunderbolt.CerebrosBridge.Validator

  @shortdoc "Validate Cerebros bridge readiness"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [require_enabled: :boolean, json: :boolean])

    result = Validator.validate(require_enabled?: opts[:require_enabled])

    if opts[:json] do
      emit_json(result)
    else
      emit_table(result)
    end

    case result.status do
      :ok -> :ok
      :warning -> :ok
      :error -> Mix.raise("Cerebros bridge validation failed")
    end
  end

  defp emit_json(result) do
    IO.puts(Jason.encode!(result, pretty: true))
  end

  defp emit_table(%{status: status, checks: checks}) do
    Mix.shell().info(["\n", color_status(status), " Cerebros Bridge Validation", :reset])

    Enum.each(checks, fn %{name: name, status: check_status, message: message, metadata: meta} ->
      indicator = status_indicator(check_status)
      Mix.shell().info(["  ", indicator, " ", format_name(name), ": ", message])

      if meta do
        detail =
          meta
          |> Enum.map(fn {k, v} -> "    • #{k}: #{format_value(v)}" end)
          |> Enum.join("\n")

        if detail != "" do
          Mix.shell().info(detail)
        end
      end
    end)

    Mix.shell().info("")
  end

  defp color_status(:ok), do: IO.ANSI.format([:green, "[OK]"]) |> IO.iodata_to_binary()
  defp color_status(:warning), do: IO.ANSI.format([:yellow, "[WARN]"]) |> IO.iodata_to_binary()
  defp color_status(:error), do: IO.ANSI.format([:red, "[ERROR]"]) |> IO.iodata_to_binary()

  defp status_indicator(:ok), do: IO.ANSI.format([:green, "✔"], true)
  defp status_indicator(:warning), do: IO.ANSI.format([:yellow, "⚠"], true)
  defp status_indicator(:error), do: IO.ANSI.format([:red, "✖"], true)

  defp format_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp format_name(name), do: to_string(name)

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: inspect(value)
end
