defmodule Thunderline.Thunderflow.Jobs.DomainProcessor do
  @moduledoc """
  DomainProcessor bridges canonical %Thunderline.Event{} batches into concrete work.

  Responsibilities:
  - Gate ml.* actions through Stone (policy) before side effects
  - Enqueue ML trainer work when a trial starts
  - Surface golden-signal telemetry for routed/denied/unknown events

  It is used by EventPipeline via `maybe_domain_processor/1` to transform a
  generic job map like `%{"event" => ev, "domain" => "thunderbolt"}` into an
  Oban job changeset.
  """

  use Oban.Worker, queue: :domain_events, max_attempts: 3

  require Logger

  alias Thunderline.Stone
  alias Thunderline.Thunderbolt.ML.Trainer.RunWorker
  alias Thunderline.Thunderbolt.ML.Trainer.GemmRunner

  @tele_base [:thunderline, :domain_processor]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => ev}}) when is_map(ev) do
    action = ev["action"] || ev[:action] || ""
    :telemetry.execute(@tele_base ++ [:routed], %{count: 1}, %{action: action})

    case action do
      "ml.trial.started" ->
        handle_trial_started(ev)

      "ml.run.metrics" ->
        handle_run_metrics(ev)

      "ml.run.completed" ->
        handle_run_completed(ev)

      "ml.artifact.created" ->
        handle_artifact_created(ev)

      other ->
        Logger.debug("DomainProcessor: unhandled action=#{inspect(other)}")
        :ok
    end
  rescue
    e ->
      Logger.error("DomainProcessor crashed: #{Exception.format(:error, e, __STACKTRACE__)}")
      :telemetry.execute(@tele_base ++ [:error], %{count: 1}, %{error: inspect(e)})
      {:error, e}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: other}) do
    Logger.warning("DomainProcessor received unexpected args: #{inspect(other)}")
    :ok
  end

  # --- handlers ---

  defp handle_trial_started(ev) do
    payload = ev["payload"] || ev[:payload] || %{}
    run_id = payload["run_id"] || payload[:run_id] || safe_uuid()
    trial_id = payload["trial_id"] || payload[:trial_id]

    case Stone.allow?(:trial_start, ev) do
      :ok ->
        meta = %{run_id: run_id, trial_id: trial_id}
        :telemetry.execute(@tele_base ++ [:ml, :trial, :allowed], %{}, meta)

        # Enqueue specific trainer based on kernel selection; otherwise fall back.
        kernel = get_in(payload, ["kernel"]) || get_in(payload, [:kernel])
        backend = get_in(payload, ["backend"]) || get_in(payload, [:backend]) || "nif"
        m = get_in(payload, ["m"]) || get_in(payload, [:m])
        n = get_in(payload, ["n"]) || get_in(payload, [:n])
        k = get_in(payload, ["k"]) || get_in(payload, [:k])
        repeats = get_in(payload, ["repeats"]) || get_in(payload, [:repeats]) || 10
        verify? = get_in(payload, ["verify"]) || get_in(payload, [:verify]) || false

        enqueue_result =
          case kernel do
            "gemm_fp16_acc32" ->
              if Code.ensure_loaded?(GemmRunner) and is_integer(m) and is_integer(n) and is_integer(k) do
                args = %{
                  "run_id" => run_id,
                  "m" => m,
                  "n" => n,
                  "k" => k,
                  "repeats" => repeats,
                  "backend" => backend,
                  "verify" => verify?
                }

                GemmRunner.new(args) |> Oban.insert()
              else
                {:error, :invalid_kernel_args}
              end

            _ ->
              if Code.ensure_loaded?(RunWorker) do
                RunWorker.new(%{"run_id" => run_id}) |> Oban.insert()
              else
                {:error, :no_trainer}
              end
          end

        case enqueue_result do
          {:ok, _job} ->
            :telemetry.execute(@tele_base ++ [:ml, :trial, :enqueued], %{}, meta)
            :ok

          {:error, reason} ->
            Logger.error("Failed to enqueue trainer for run_id=#{run_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :denied} ->
        :telemetry.execute(@tele_base ++ [:ml, :trial, :denied], %{}, %{trial_id: trial_id})
        Logger.warning("Stone denied trial_start for trial_id=#{inspect(trial_id)}")
        # Deny without retrying
        {:discard, :denied}
    end
  end

  defp handle_run_metrics(ev) do
    payload = ev["payload"] || %{}
    :telemetry.execute(@tele_base ++ [:ml, :run, :metrics], %{count: 1}, Map.take(payload, ["run_id", "metrics"]))
    :ok
  end

  defp handle_run_completed(ev) do
    payload = ev["payload"] || %{}
    :telemetry.execute(@tele_base ++ [:ml, :run, :completed], %{}, Map.take(payload, ["run_id", "status"]))
    :ok
  end

  defp handle_artifact_created(ev) do
    payload = ev["payload"] || %{}
    :telemetry.execute(@tele_base ++ [:ml, :artifact, :created], %{}, Map.take(payload, ["artifact_id", "run_id", "uri", "kind"]))
    :ok
  end

  defp safe_uuid do
    if Code.ensure_loaded?(Thunderline.UUID) and function_exported?(Thunderline.UUID, :v7, 0) do
      Thunderline.UUID.v7()
    else
      Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    end
  end
end
