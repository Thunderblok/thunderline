defmodule Thunderline.Thunderflow.Probing.AttractorSummaryTest do
  # Use DataCase to ensure DB sandbox ownership is properly established
  use Thunderline.DataCase, async: false
  @moduletag :skip

  alias Thunderline.Thunderflow.Resources.{ProbeRun, ProbeLap, ProbeAttractorSummary}
  alias Thunderline.Thunderflow.Probing.{Engine, AttractorService}
  alias Thunderline.Thunderflow.Probing.Workers.ProbeAttractorSummaryWorker

  test "engine run -> laps persisted -> summary worker builds summary -> recompute updates" do
    # Create run
    run =
      Ash.create!(ProbeRun, %{
        provider: "mock",
        model: "gpt-test",
        prompt_path: fixture_prompt(),
        laps: 5,
        samples: 1,
        embedding_dim: 64,
        embedding_ngram: 2,
        condition: "A"
      })

    # Simulate what ProbeRunProcessor does (call Engine + create laps)
    laps =
      Engine.run(%{
        provider: run.provider,
        model: run.model,
        prompt_path: run.prompt_path,
        laps: run.laps,
        samples: run.samples,
        embedding_dim: run.embedding_dim,
        embedding_ngram: run.embedding_ngram,
        condition: run.condition
      })

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
        embedding: l.embedding
      })
    end)

    # Run summary worker
    job = %Oban.Job{args: %{"run_id" => run.id}}
    :ok = ProbeAttractorSummaryWorker.perform(job)

    {:ok, summary} = Ash.read_one(ProbeAttractorSummary, run_id: run.id)
    assert summary.points == 5
    assert is_float(summary.corr_dim)
    assert is_float(summary.lyap)

    # Recompute with different parameters
    {:ok, _} = AttractorService.recompute(run.id, m: 2, tau: 1)
    {:ok, updated} = Ash.read_one(ProbeAttractorSummary, run_id: run.id)
    assert updated.m == 2
  end

  test "telemetry emission" do
    self_pid = self()

    :telemetry.attach_many(
      "attractor-test",
      [[:thunderline, :probe, :attractor_summary]],
      fn event, measurements, metadata, _config ->
        send(self_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    run =
      Ash.create!(ProbeRun, %{
        provider: "mock",
        model: "gpt-test",
        prompt_path: fixture_prompt(),
        laps: 3,
        samples: 1,
        embedding_dim: 64,
        embedding_ngram: 2,
        condition: "B"
      })

    laps =
      Engine.run(%{
        provider: run.provider,
        model: run.model,
        prompt_path: run.prompt_path,
        laps: run.laps,
        samples: run.samples,
        embedding_dim: run.embedding_dim,
        embedding_ngram: run.embedding_ngram,
        condition: run.condition
      })

    Enum.each(laps, fn l ->
      Ash.create!(ProbeLap, %{
        run_id: run.id,
        lap_index: l.lap_index,
        embedding: l.embedding,
        response_preview: l.response_preview,
        char_entropy: l.char_entropy,
        lexical_diversity: l.lexical_diversity,
        repetition_ratio: l.repetition_ratio,
        cosine_to_prev: l.cosine_to_prev,
        elapsed_ms: l.elapsed_ms
      })
    end)

    job = %Oban.Job{args: %{"run_id" => run.id}}
    :ok = Thunderline.Thunderflow.Probing.Workers.ProbeAttractorSummaryWorker.perform(job)

    assert_receive {:telemetry_event, [:thunderline, :probe, :attractor_summary], meas, meta},
                   1000

    assert meta.run_id == run.id
    assert is_number(meas.corr_dim)
  after
    :telemetry.detach("attractor-test")
  end

  defp fixture_prompt do
    path = Path.join(System.tmp_dir!(), "probe_prompt.txt")
    File.write!(path, "Test prompt")
    path
  end
end
