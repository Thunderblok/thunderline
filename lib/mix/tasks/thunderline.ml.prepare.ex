defmodule Mix.Tasks.Thunderline.Ml.Prepare do
  @moduledoc """
  Assess local readiness for running the full Cerebros smoke test.

  This task wraps the existing Cerebros bridge validator, adds feature flag and
  Oban queue checks, and emits a consolidated readiness report so operators can
  address any gaps before invoking the smoke workflow.

      mix thunderline.ml.prepare

  Options:

    * `--require-enabled` – treat a disabled bridge config as an error instead
      of a warning (mirrors `mix thunderline.ml.validate`).
    * `--json` – emit machine-readable JSON output.
  """
  use Mix.Task

  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Validator}

  @shortdoc "Check Cerebros smoke test readiness"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [require_enabled: :boolean, json: :boolean])

    require_enabled? = opts[:require_enabled] || false
    validator_result = Validator.validate(require_enabled?: require_enabled?)

    extra_checks =
      [cerebros_feature_flag_check(), client_gate_check(), oban_queue_check()]
      |> Enum.reject(&is_nil/1)

    checks = validator_result.checks ++ extra_checks

    status =
      cond do
        Enum.any?(checks, &(&1.status == :error)) -> :error
        Enum.any?(checks, &(&1.status == :warning)) -> :warning
        true -> :ok
      end

    readiness = %{status: status, checks: checks}

    if opts[:json] do
      IO.puts(Jason.encode!(readiness, pretty: true))
    else
      emit_table(readiness)
      print_next_steps(status)
    end

    case status do
      :ok -> :ok
      :warning -> :ok
      :error -> Mix.raise("Cerebros smoke test readiness failed")
    end
  end

  defp cerebros_feature_flag_check do
    enabled? = Feature.enabled?(:cerebros_bridge, default: false)

    %{
      name: :cerebros_feature_flag,
      status: if(enabled?, do: :ok, else: :warning),
      message:
        if(enabled?,
          do: "Feature flag :cerebros_bridge is enabled",
          else: "Feature flag :cerebros_bridge is disabled"
        ),
      metadata: %{
        remediation:
          "Add :cerebros_bridge to config :thunderline, :features or export CEREBROS_ENABLED=1"
      }
    }
  end

  defp client_gate_check do
    if Client.enabled?() do
      %{
        name: :bridge_gate,
        status: :ok,
        message: "Client.enabled?/0 returned true"
      }
    else
      %{
        name: :bridge_gate,
        status: :error,
        message: "Cerebros bridge client gated off",
        metadata: %{
          remediation: "Ensure :ml_nas feature flag and :cerebros_bridge enabled config"
        }
      }
    end
  end

  defp oban_queue_check do
    case Application.get_env(:thunderline, Oban) do
      nil ->
        %{
          name: :oban_queue,
          status: :warning,
          message: "Oban not configured; queue :ml unavailable",
          metadata: %{
            remediation: "Configure Oban with an :ml queue before running the smoke test"
          }
        }

      config ->
        queues = Keyword.get(config, :queues, [])
        queue_map = normalize_queue_config(queues)

        case Map.get(queue_map, :ml) do
          nil ->
            %{
              name: :oban_queue,
              status: :error,
              message: ":ml queue missing from Oban configuration",
              metadata: %{
                remediation: "Add :ml => [limit: <N>] to config :thunderline, Oban, :queues"
              }
            }

          value ->
            %{
              name: :oban_queue,
              status: :ok,
              message: ":ml queue configured",
              metadata: %{limit: limit_from_queue(value)}
            }
        end
    end
  end

  defp normalize_queue_config(queues) when is_map(queues), do: queues

  defp normalize_queue_config(queues) when is_list(queues) do
    queues
    |> Enum.map(fn
      {queue, opts} when is_atom(queue) -> {queue, opts}
      other -> other
    end)
    |> Enum.reject(fn
      {queue, _opts} when is_atom(queue) -> false
      _ -> true
    end)
    |> Map.new()
  end

  defp normalize_queue_config(_), do: %{}

  defp limit_from_queue(value) when is_integer(value), do: value

  defp limit_from_queue(value) when is_list(value) do
    value
    |> Keyword.get(:limit)
  end

  defp limit_from_queue(_), do: nil

  defp emit_table(%{status: status, checks: checks}) do
    Mix.shell().info(["\n", color_status(status), " Cerebros Smoke Test Readiness", :reset])

    Enum.each(checks, fn check ->
      name = Map.fetch!(check, :name)
      check_status = Map.fetch!(check, :status)
      message = Map.fetch!(check, :message)
      meta = Map.get(check, :metadata)
      indicator = status_indicator(check_status)
      Mix.shell().info(["  ", indicator, " ", format_name(name), ": ", message])

      if meta && meta != %{} do
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

  defp print_next_steps(status) do
    Mix.shell().info("Next steps:")

    Mix.shell().info("  • run mix thunderline.ml.validate --require-enabled")

    Mix.shell().info(
      "  • enqueue a RunWorker job (e.g. via Thunderline.Thunderbolt.CerebrosBridge.Validator.default_spec/0)"
    )

    case status do
      :ok ->
        Mix.shell().info(
          "  • monitor Oban :ml queue and Thunderflow events during the smoke test\n"
        )

      :warning ->
        Mix.shell().info("  • address warnings above before proceeding\n")

      :error ->
        Mix.shell().info(
          "  • resolve errors above; smoke test will fail if prerequisites are unmet\n"
        )
    end
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
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(nil), do: "(unset)"
  defp format_value(value), do: inspect(value)
end
