defmodule Mix.Tasks.Thunderline.Ml.Smoke do
  use Mix.Task
  @shortdoc "Emit a demo ml.* event sequence from a TrialSpec YAML"
  @moduledoc """
  Emits a minimal end-to-end ML event sequence using the unified taxonomy:

    - ml.trial.started
    - ml.run.metrics (N times)
    - ml.run.completed

  Reads a TrialSpec-style YAML (see ops/templates/trial_spec.yaml) to populate payload fields.
  By default, generates fresh trial_id/run_id unless provided via CLI options.

  Examples

      mix thunderline.ml.smoke
      mix thunderline.ml.smoke --spec ops/templates/trial_spec.yaml
      mix thunderline.ml.smoke --metrics 5 --sleep 250
      mix thunderline.ml.smoke --trial-id 11111111-1111-1111-1111-111111111111

  Options
  - --spec: Path to TrialSpec YAML (default: ops/templates/trial_spec.yaml)
  - --metrics: Number of metrics events to emit (default: 5)
  - --sleep: Milliseconds to sleep between metrics events (default: 200)
  - --trial-id: Override trial_id (default: generated UUID)
  - --run-id: Override run_id (default: generated UUID)
  """

  @default_spec "ops/templates/trial_spec.yaml"
  @default_metrics 5
  @default_sleep_ms 200

  @impl true
  def run(argv) do
    Mix.Task.run("app.start", [])
    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        switches: [
          spec: :string,
          metrics: :integer,
          sleep: :integer,
          "trial-id": :string,
          "run-id": :string
        ]
      )

    spec_path = opts[:spec] || @default_spec
    metrics_n = opts[:metrics] || @default_metrics
    sleep_ms = opts[:sleep] || @default_sleep_ms

    with {:ok, spec} <- load_yaml(spec_path) do
      trial_id = opts[:"trial-id"] || take(spec, ["trial_id"]) || uuid()
      run_id = opts[:"run-id"] || take(spec, ["run_id"]) || uuid()

      dataset_ref =
        take(spec, ["dataset_ref"]) ||
          take(spec, ["dataset", "ref"]) ||
          "demo://dataset/sample"

      params =
        take(spec, ["search_space"]) ||
          %{"lr" => 1.0e-3, "batch_size" => 8, "epochs" => 1}

      # Kernel slice fields (defaults for GEMM smoke)
      kernel = take(spec, ["kernel"]) || "gemm_fp16_acc32"
      backend = take(spec, ["backend"]) || "nif"
      m = to_int(take(spec, ["m"]) || 512)
      n = to_int(take(spec, ["n"]) || 512)
      k = to_int(take(spec, ["k"]) || 512)
      repeats = to_int(take(spec, ["repeats"]) || 10)
      verify = take(spec, ["verify"]) || false

      trial_payload = %{
        trial_id: trial_id,
        run_id: run_id,
        dataset_ref: dataset_ref,
        params: params,
        kernel: kernel,
        backend: backend,
        m: m,
        n: n,
        k: k,
        repeats: repeats,
        verify: verify
      }

      IO.puts("[smoke] Emitting ml.trial.started trial_id=#{trial_id} run_id=#{run_id}")
      emit_started!(trial_payload)

      Enum.each(1..metrics_n, fn i ->
        metrics = %{
          "step" => i,
          "accuracy" => Float.round(0.60 + :rand.uniform() * 0.35, 4),
          "loss" => Float.round(1.50 - :rand.uniform() * 1.25, 5)
        }

        IO.puts("[smoke] Emitting ml.run.metrics step=#{i} accuracy=#{metrics["accuracy"]}")
        emit_metrics!(%{run_id: run_id, metrics: metrics})
        Process.sleep(sleep_ms)
      end)

      IO.puts("[smoke] Emitting ml.run.completed run_id=#{run_id}")
      emit_completed!(%{run_id: run_id, status: "ok"})

      IO.puts("""
      [smoke] Done.

      Next:
        - Watch Broadway/Oban logs for DomainProcessor routing, DLQ/idempotency, and golden-signal telemetry:
            [:thunderline, :domain_processor, ...]
            [:thunderline, :pipeline, :domain_events, ...]
            [:thunderline, :event, :dedup]
            [:thunderline, :pipeline, :dlq]
        - If OTLP is configured (OTEL endpoint), verify spans/metrics arrive in your backend.
      """)

      :ok
    else
      {:error, reason} ->
        Mix.raise("Failed to load spec #{spec_path}: #{inspect(reason)}")
    end
  end

  defp emit_started!(payload) do
    ev = Thunderline.Thunderbolt.ML.Emitter.trial_started(payload)
    publish!(ev)
  end

  defp emit_metrics!(payload) do
    ev = Thunderline.Thunderbolt.ML.Emitter.run_metrics(payload)
    publish!(ev)
  end

  defp emit_completed!(payload) do
    ev = Thunderline.Thunderbolt.ML.Emitter.run_completed(payload)
    publish!(ev)
  end

  defp publish!(%Thunderline.Event{} = ev) do
    case Thunderline.EventBus.publish_event(ev) do
      {:ok, _ev} -> :ok
      {:error, reason} -> Mix.raise("publish_event failed: #{inspect(reason)}")
    end
  end

  defp load_yaml(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case YamlElixir.read_from_string(content) do
            {:ok, doc} when is_map(doc) -> {:ok, doc}
            {:ok, other} -> {:ok, %{"_raw" => other}}
            {:error, err} -> {:error, {:yaml_parse_error, err}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, %{}}
    end
  end

  # Get nested value from a map via list of keys (string keys)
  defp take(nil, _ks), do: nil
  defp take(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, map, fn k, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, k) -> {:cont, Map.get(acc, k)}
        true -> {:halt, nil}
      end
    end)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> raise ArgumentError, "invalid integer value: #{inspect(v)}"
    end
  end

  defp uuid do
    if Code.ensure_loaded?(Thunderline.UUID) and function_exported?(Thunderline.UUID, :v7, 0) do
      Thunderline.UUID.v7()
    else
      Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    end
  end
end
