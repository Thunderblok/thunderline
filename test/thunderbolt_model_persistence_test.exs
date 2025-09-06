defmodule Thunderline.ThunderboltModelPersistenceTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.Resources.ModelRun
  alias Thunderline.Thunderbolt.ML.ModelArtifact

  test "create model run and artifact" do
    {:ok, run} = ModelRun.create(%{search_space_version: 1, max_params: 1000, requested_trials: 2, metadata: %{purpose: "test"}})
    assert run.state == :initialized

    {:ok, started} = ModelRun.start(run)
    assert started.state == :running

  {:ok, artifact} = ModelArtifact.create(%{spec_id: Ecto.UUID.generate(), model_run_id: run.id, uri: "/tmp/model.bin", checksum: "abc123", bytes: 123, semver: "0.1.0"})
  assert artifact.model_run_id == run.id

    {:ok, completed} = ModelRun.complete(started, %{best_metric: 0.99, completed_trials: 1})
    assert completed.state == :succeeded
  end
end
