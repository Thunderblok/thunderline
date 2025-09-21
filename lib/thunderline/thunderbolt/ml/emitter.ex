defmodule Thunderline.Thunderbolt.ML.Emitter do
  @moduledoc """
  Normalized ML event emitter. Use this to ensure all events follow ml.* taxonomy.
  """
  alias Thunderline.Event

  @spec trial_started(map()) :: Event.t()
  def trial_started(%{trial_id: _} = payload) do
    Event.new!(name: "ml.trial.started", source: :bolt, payload: payload)
  end

  @spec run_metrics(map()) :: Event.t()
  def run_metrics(%{run_id: _, metrics: _} = payload) do
    Event.new!(name: "ml.run.metrics", source: :bolt, payload: payload)
  end

  @spec run_completed(map()) :: Event.t()
  def run_completed(%{run_id: _} = payload) do
    Event.new!(name: "ml.run.completed", source: :bolt, payload: payload)
  end

  @spec artifact_created(map()) :: Event.t()
  def artifact_created(%{artifact_id: _, run_id: _, uri: _, kind: _} = payload) do
    Event.new!(name: "ml.artifact.created", source: :bolt, payload: payload)
  end
end
