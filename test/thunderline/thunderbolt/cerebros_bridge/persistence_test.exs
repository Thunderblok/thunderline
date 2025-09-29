defmodule Thunderline.Thunderbolt.CerebrosBridge.PersistenceTest do
  use Thunderline.DataCase, async: false

  alias Ash
  alias Ash.Query
  require Ash.Query
  alias Thunderline.Thunderbolt.CerebrosBridge.{Contracts, Persistence, Validator}
  alias Thunderline.Thunderbolt.ML.ModelArtifact
  alias Thunderline.Thunderbolt.Resources.{ModelRun, ModelTrial}

  describe "record_run_finalized/3" do
    setup do
      _ =
        Ecto.Adapters.SQL.query!(
          Thunderline.Repo,
          """
          CREATE TABLE IF NOT EXISTS cerebros_model_trials (
            id uuid PRIMARY KEY,
            model_run_id uuid NOT NULL,
            trial_id text NOT NULL,
            candidate_id text,
            status text,
            metrics jsonb DEFAULT '{}'::jsonb,
            parameters jsonb DEFAULT '{}'::jsonb,
            artifact_uri text,
            duration_ms integer,
            rank integer,
            warnings jsonb DEFAULT '[]'::jsonb,
            pulse_id text,
            bridge_payload jsonb DEFAULT '{}'::jsonb,
            inserted_at timestamp without time zone NOT NULL DEFAULT NOW(),
            updated_at timestamp without time zone NOT NULL DEFAULT NOW()
          )
          """
        )

      _ =
        Ecto.Adapters.SQL.query!(
          Thunderline.Repo,
          "ALTER TABLE cerebros_model_runs ADD COLUMN IF NOT EXISTS run_id text"
        )

      _ =
        Ecto.Adapters.SQL.query!(
          Thunderline.Repo,
          "ALTER TABLE cerebros_model_runs ADD COLUMN IF NOT EXISTS bridge_payload jsonb DEFAULT '{}'::jsonb"
        )

      _ =
        Ecto.Adapters.SQL.query!(
          Thunderline.Repo,
          "ALTER TABLE cerebros_model_runs ADD COLUMN IF NOT EXISTS bridge_result jsonb DEFAULT '{}'::jsonb"
        )

      spec_id = Ecto.UUID.generate()

      spec =
        Validator.default_spec()
        |> Map.put("spec_id", spec_id)

      run_id = Ecto.UUID.generate()
      run_uuid = Ecto.UUID.generate()
      {:ok, run_uuid_bin} = Ecto.UUID.dump(run_uuid)

      _ =
        Ecto.Adapters.SQL.query!(
          Thunderline.Repo,
          "INSERT INTO cerebros_model_runs (id, state, search_space_version, max_params, requested_trials, completed_trials, metadata, run_id, inserted_at, updated_at) VALUES ($1::uuid, $2, $3, $4, $5, $6, '{}'::jsonb, $7, NOW(), NOW())",
          [run_uuid_bin, "initialized", 1, 2_000_000, 4, 0, run_id]
        )

      {:ok, %ModelRun{} = run} =
        ModelRun
        |> Query.filter(id == ^run_uuid)
        |> Ash.read_one()

      start_contract = %Contracts.RunStartedV1{
        run_id: run_id,
        pulse_id: nil,
        budget: %{},
        parameters: %{},
        tau: nil,
        correlation_id: run_id,
        timestamp: DateTime.utc_now(),
        extra: %{}
      }

      :ok =
        Persistence.record_run_started(
          start_contract,
          %{returncode: 0, duration_ms: 5, stdout_excerpt: "starting"},
          spec
        )

      {:ok, %ModelRun{} = reloaded_run} =
        ModelRun
        |> Query.filter(id == ^run_uuid)
        |> Ash.read_one()

      %{spec: spec, run: reloaded_run, run_id: run_id, spec_id: spec_id}
    end

    test "persists artifacts referenced in finalize contract", %{
      spec: spec,
      run: run,
      run_id: run_id,
      spec_id: spec_id
    } do
      trial_contract = %Contracts.TrialReportedV1{
        trial_id: "trial-1",
        run_id: run_id,
        pulse_id: nil,
        candidate_id: "cand-1",
        status: :succeeded,
        metrics: %{accuracy: 0.91},
        parameters: %{depth: 18},
        artifact_uri: "s3://thunderline/artifacts/run-1/trial-1.pt",
        duration_ms: 1234,
        rank: 1,
        warnings: []
      }

      :ok =
        Persistence.record_trial_reported(
          trial_contract,
          %{metrics: %{accuracy: 0.91}, duration_ms: 1200},
          spec
        )

      artifact_checksum = :crypto.hash(:sha256, "trial-1.pt") |> Base.encode16(case: :lower)

      artifact_refs = [
        %{
          "uri" => "s3://thunderline/artifacts/run-1/best.pt",
          "checksum" => artifact_checksum,
          "bytes" => "2048"
        }
      ]

      finalize_contract = %Contracts.RunFinalizedV1{
        run_id: run_id,
        pulse_id: nil,
        status: :succeeded,
        metrics: %{accuracy: 0.93},
        best_trial_id: "trial-1",
        duration_ms: 2_400,
        returncode: 0,
        artifact_refs: artifact_refs,
        warnings: [],
        stdout_excerpt: "done",
        payload: %{result: %{artifact_refs: artifact_refs}}
      }

      :ok =
        Persistence.record_run_finalized(
          finalize_contract,
          %{returncode: 0, duration_ms: 2_400, parsed: %{artifact_refs: artifact_refs}},
          spec
        )

      {:ok, %ModelRun{} = refreshed} =
        ModelRun
        |> Query.filter(id == ^run.id)
        |> Ash.read_one()

      assert refreshed.state == :succeeded
      assert refreshed.completed_trials == 1
      assert refreshed.best_metric == 0.93

      {:ok, %ModelTrial{} = stored_trial} =
        ModelTrial
        |> Query.filter(model_run_id == ^run.id)
        |> Ash.read_one()

      assert stored_trial.trial_id == "trial-1"
      assert stored_trial.artifact_uri == "s3://thunderline/artifacts/run-1/trial-1.pt"

      {:ok, %ModelArtifact{} = artifact} =
        ModelArtifact
        |> Query.filter(checksum == ^artifact_checksum)
        |> Ash.read_one()

      assert artifact.uri == "s3://thunderline/artifacts/run-1/best.pt"
      assert artifact.bytes == 2048
      assert artifact.spec_id == spec_id
      assert artifact.model_run_id == run.id
      assert artifact.semver == "0.1.0"

      # Running finalize again with the same artifact should not duplicate rows.
      :ok =
        Persistence.record_run_finalized(
          finalize_contract,
          %{returncode: 0, duration_ms: 2_400, parsed: %{artifact_refs: artifact_refs}},
          spec
        )

      {:ok, artifacts} =
        ModelArtifact
        |> Query.filter(model_run_id == ^run.id)
        |> Ash.read()

      assert Enum.count(artifacts) == 1
    end
  end
end
