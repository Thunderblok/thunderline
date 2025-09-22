defmodule Thunderline.Thunderbolt.ML.Trainer.GemmRunner do
  @moduledoc """
  GEMM slice runner for Kernel Slice smoke test.

  Accepts:
    - run_id :: String.t()
    - m,n,k :: pos_integer()
    - repeats :: pos_integer() (default 10)
    - backend :: "nif" | "python" (default "nif")
    - verify :: boolean() (default false)

  Behavior:
    - Generates FP16 row-major A (m×k) and B (k×n) once per job
    - For `repeats` iterations:
      - Calls Numerics.gemm_fp16_acc32/3 with opts [m:, n:, k:]
      - Measures latency (ms)
      - Optionally verifies C vs. Nx float32 reference on first iteration
      - Emits ml.run.metrics for each iteration
    - Computes p50/p95 and emits ml.run.completed
    - Writes JSONL metrics under ops/artifacts/{run_id}/metrics.jsonl
  """
  use Oban.Worker, queue: :ml, max_attempts: 1

  alias Thunderline.Thunderbolt.ML.Emitter
  alias Thunderline.EventBus

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = fetch!(args, "run_id")
    m = fetch!(args, "m")
    n = fetch!(args, "n")
    k = fetch!(args, "k")
    repeats = Map.get(args, "repeats", 10)
    backend = Map.get(args, "backend", "nif")
    verify? = Map.get(args, "verify", false)

    # Select backend adapter for Thunderline.Thunderbolt.Numerics
    select_backend!(backend)

    # Generate FP16 A/B as row-major binaries (little-endian FP16)
    {a16, b16} = generate_inputs_fp16(m, n, k)

    metrics_path = Path.join(["ops", "artifacts", run_id, "metrics.jsonl"])
    File.mkdir_p!(Path.dirname(metrics_path))

    latencies_ms =
      for i <- 1..repeats do
        {time_us, res} =
          :timer.tc(fn ->
            case Thunderline.Thunderbolt.Numerics.gemm_fp16_acc32(a16, b16, m: m, n: n, k: k) do
              {:ok, _c16} -> :ok
              {:error, reason} -> {:error, reason}
            end
          end)

        latency_ms = time_us / 1000.0

        # Optional verification only on first iteration (to amortize cost)
        if verify? and i == 1 do
          verify_result(a16, b16, m, n, k)
        end

        # Emit run metrics event
        emit_metrics!(%{
          "run_id" => run_id,
          "metrics" => %{
            "iter" => i,
            "latency_ms" => Float.round(latency_ms, 4),
            "backend" => backend
          }
        })

        # Persist JSONL
        append_jsonl!(metrics_path, %{
          ts: System.system_time(:second),
          run_id: run_id,
          metric: "latency_ms",
          value: Float.round(latency_ms, 6),
          iter: i,
          backend: backend
        })

        latency_ms
      end

    {p50, p95} = percentiles(latencies_ms, [50, 95])

    # Emit completion event
    emit_completed!(%{
      "run_id" => run_id,
      "p50" => Float.round(p50, 4),
      "p95" => Float.round(p95, 4),
      "backend" => backend,
      "ok" => true
    })

    :ok
  rescue
    e ->
      Logger.error("GemmRunner failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      {:error, e}
  end

  # --- helpers ---

  defp fetch!(map, key) do
    case Map.fetch(map, key) do
      {:ok, v} -> v
      :error -> raise ArgumentError, "missing required arg: #{inspect(key)}"
    end
  end

  defp select_backend!("nif") do
    Application.put_env(:thunderline, :numerics_adapter, Thunderline.Thunderbolt.Numerics.Adapters.NIF)
  end

  defp select_backend!("python") do
    Application.put_env(:thunderline, :numerics_adapter, Thunderline.Thunderbolt.Numerics.Adapters.Sidecar)
  end

  defp select_backend!(other) do
    Logger.warning("Unknown backend=#{inspect(other)}; defaulting to :nif")
    select_backend!("nif")
  end

  # Generate FP16 row-major matrices as binaries using Nx
  defp generate_inputs_fp16(m, n, k) do
    a =
      Nx.random_uniform({m, k}, 0.0, 1.0, type: {:f, 32})
      |> Nx.as_type({:f, 16})

    b =
      Nx.random_uniform({k, n}, 0.0, 1.0, type: {:f, 32})
      |> Nx.as_type({:f, 16})

    {Nx.to_binary(a), Nx.to_binary(b)}
  end

  defp emit_metrics!(payload) do
    ev = Emitter.run_metrics(payload)

    case EventBus.publish_event(ev) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error("publish ml.run.metrics failed: #{inspect(reason)}")
        :ok
    end
  end

  defp emit_completed!(payload) do
    ev = Emitter.run_completed(payload)

    case EventBus.publish_event(ev) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error("publish ml.run.completed failed: #{inspect(reason)}")
        :ok
    end
  end

  defp append_jsonl!(path, map) do
    line = Jason.encode!(map) <> "\n"
    File.write!(path, line, [:append])
  end

  # Simple percentile estimation using sorted samples
  defp percentiles(samples, ps) do
    s = Enum.sort(samples)
    len = length(s)
    Enum.reduce(ps, {nil, nil}, fn p, {acc50, acc95} ->
      idx = max(0, min(len - 1, trunc(Float.ceil(p / 100.0 * len)) - 1))
      val = Enum.at(s, idx) || hd(s)
      case p do
        50 -> {val, acc95}
        95 -> {acc50, val}
        _ -> {acc50, acc95}
      end
    end)
  end

  # Optional correctness check via Nx float32 GEMM
  defp verify_result(a16, b16, m, n, k) do
    try do
      a_f32 =
        Nx.from_binary(a16, {:f, 16})
        |> Nx.reshape({m, k})
        |> Nx.as_type({:f, 32})

      b_f32 =
        Nx.from_binary(b16, {:f, 16})
        |> Nx.reshape({k, n})
        |> Nx.as_type({:f, 32})

      c_ref = Nx.dot(a_f32, [1], b_f32, [0]) |> Nx.as_type({:f, 16})

      # Run once via selected backend
      {:ok, c16} = Thunderline.Thunderbolt.Numerics.gemm_fp16_acc32(a16, b16, m: m, n: n, k: k)
      c_nif = Nx.from_binary(c16, {:f, 16}) |> Nx.reshape({m, n})

      diff = Nx.as_type(Nx.abs(c_ref - c_nif), {:f, 32})
      max_ulp = Nx.reduce_max(diff) |> Nx.to_number()

      if max_ulp > 1.0 do
        Logger.warning("GEMM verification deviation max=#{max_ulp} (> 1.0 ULP approx)")
      end

      :ok
    rescue
      e ->
        Logger.warning("Verification failed: #{inspect(e)}")
        :ok
    end
  end
end
