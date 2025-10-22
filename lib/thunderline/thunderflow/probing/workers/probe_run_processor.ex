defmodule Thunderline.Thunderflow.Probing.Workers.ProbeRunProcessor do
  @moduledoc "Oban worker that executes a ProbeRun by generating ProbeLap records."
  use Oban.Worker, queue: :probe, max_attempts: 1
  require Logger
  alias Thunderline.Thunderflow.Probing.Engine
  alias Thunderline.Thunderflow.Resources.{ProbeRun, ProbeLap}
  alias Thunderline.Thunderflow.IntrinsicReward
  alias Thunderline.{Event, EventBus, Feature}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    Logger.info("[ProbeRunProcessor] Starting probe run #{run_id}")

    case Ash.get(ProbeRun, run_id) do
      {:ok, run} ->
        execute(run)

      {:error, err} ->
        Logger.error("[ProbeRunProcessor] Run not found #{run_id} err=#{inspect(err)}")
    end

    :ok
  end

  defp execute(run) do
    spec = %{
      provider: run.provider,
      model: run.model,
      prompt_path: run.prompt_path,
      laps: run.laps,
      samples: run.samples,
      embedding_dim: run.embedding_dim,
      embedding_ngram: run.embedding_ngram,
      condition: run.condition || "A"
    }

    Ash.update!(run, %{status: :running, started_at: DateTime.utc_now()}, action: :update_status)

    laps = Engine.run(spec)

    Enum.each(laps, fn l ->
      Ash.create!(ProbeLap, %{
        run_id: run.id,
        lap_index: l.lap_index,
        response_preview: l.response_preview,
        char_entropy: l.char_entropy,
        lexical_diversity: l.lexical_diversity,
        repetition_ratio: l.repetition_ratio,
        cosine_to_prev: l.cosine_to_prev,
        elapsed_ms: l.elapsed_ms,
        embedding: l.embedding,
        js_divergence_vs_baseline: Map.get(l, :js_divergence_vs_baseline),
        topk_overlap_vs_baseline: Map.get(l, :topk_overlap_vs_baseline)
      })
    end)

    # Compute intrinsic reward (IGPO) - gated by :reward_signal feature flag
    intrinsic_reward =
      IntrinsicReward.compute_reward(laps, %{
        run_id: run.id,
        provider: run.provider,
        model: run.model
      })

    Logger.debug(
      "[ProbeRunProcessor] Computed intrinsic_reward=#{intrinsic_reward} for run=#{run.id}"
    )

    Ash.update!(
      run,
      %{
        status: :completed,
        completed_at: DateTime.utc_now(),
        intrinsic_reward: intrinsic_reward
      },
      action: :update_status
    )

    # Emit event with reward data (IGPO)
    if Feature.enabled?(:reward_signal) do
      with {:ok, event} <-
             Event.new(
               "flow.probe.run.completed",
               %{
                 run_id: run.id,
                 status: :completed,
                 laps_count: length(laps),
                 intrinsic_reward: intrinsic_reward
               },
               source: :flow,
               meta: %{
                 provider: run.provider,
                 model: run.model,
                 samples: run.samples,
                 embedding_dim: run.embedding_dim
               }
             ),
           {:ok, _} <- EventBus.publish_event(event) do
        Logger.debug(
          "[ProbeRunProcessor] Published flow.probe.run.completed event for run=#{run.id}"
        )
      else
        {:error, reason} ->
          Logger.warning(
            "[ProbeRunProcessor] Failed to publish event for run=#{run.id}: #{inspect(reason)}"
          )
      end
    end

    # Emit telemetry for reward metrics (IGPO)
    if Feature.enabled?(:reward_signal) do
      duration_ms =
        case run.started_at do
          nil -> 0
          started -> DateTime.diff(DateTime.utc_now(), started, :millisecond)
        end

      :telemetry.execute(
        [:thunderline, :flow, :probe, :reward],
        %{count: 1, intrinsic_reward: intrinsic_reward},
        %{
          run_id: run.id,
          provider: run.provider,
          model: run.model,
          success?: true,
          laps_count: length(laps),
          duration_ms: duration_ms
        }
      )
    end

    # Enqueue attractor summary computation
    %{
      run_id: run.id,
      m: run.attractor_m,
      tau: run.attractor_tau,
      min_points: run.attractor_min_points
    }
    |> Thunderline.Thunderflow.Probing.Workers.ProbeAttractorSummaryWorker.new()
    |> Oban.insert()
  rescue
    error ->
      Logger.error("[ProbeRunProcessor] failure run=#{run.id} error=#{Exception.message(error)}")
      Ash.update!(run, %{status: :error, error_message: Exception.message(error)}, action: :fail)
  end
end
