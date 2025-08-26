defmodule Thunderline.ThunderboltModelPersistenceTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.Resources.{ModelRun, ModelArtifact}

  test "create model run and artifact" do
    {:ok, run} = ModelRun.create(%{search_space_version: 1, max_params: 1000, requested_trials: 2, metadata: %{purpose: "test"}})
    assert run.state == :initialized

    {:ok, started} = ModelRun.start(run)
    assert started.state == :running

    {:ok, artifact} = ModelArtifact.create(%{model_run_id: run.id, trial_index: 0, metric: 0.99, params: 42, spec: %{layers: 3}, path: "/tmp/model.bin", metadata: %{acc: 0.99}})
    assert artifact.model_run_id == run.id

    {:ok, completed} = ModelRun.complete(started, %{best_metric: 0.99, completed_trials: 1})
    assert completed.state == :succeeded
  end
end
