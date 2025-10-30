defmodule ThunderlineWeb.CerebrosJobsJSON do
  @moduledoc """
  JSON rendering for Cerebros job coordination endpoints.
  """

  def job(%{job: job}) do
    %{
      id: job.id,
      training_dataset_id: job.training_dataset_id,
      model_id: job.model_id,
      tokenizer_id: job.tokenizer_id,
      status: job.status,
      hyperparameters: job.hyperparameters,
      metadata: job.metadata,
      phase: job.phase,
      metrics: job.metrics,
      error_message: job.error_message,
      started_at: job.started_at,
      completed_at: job.completed_at,
      checkpoint_urls: job.checkpoint_urls,
      fine_tuned_model: job.fine_tuned_model,
      created_at: job.created_at,
      updated_at: job.updated_at
    }
  end

  def corpus(%{corpus_path: corpus_path, dataset: dataset}) do
    %{
      corpus_path: corpus_path,
      dataset_id: dataset.id,
      dataset_name: dataset.name,
      total_chunks: dataset.total_chunks,
      metadata: dataset.metadata
    }
  end

  def ok(%{message: message}) do
    %{ok: true, message: message}
  end

  def ok(%{}) do
    %{ok: true}
  end

  def error(%{error: error}) when is_binary(error) do
    %{error: error}
  end

  def error(%{error: %Ash.Error.Invalid{} = error}) do
    %{
      error: "Validation failed",
      details: error.errors |> Enum.map(&error_detail/1)
    }
  end

  def error(%{error: error}) do
    %{error: Exception.message(error)}
  end

  defp error_detail(%{message: message, field: field}) when not is_nil(field) do
    %{field: field, message: message}
  end

  defp error_detail(%{message: message}) do
    %{message: message}
  end

  defp error_detail(error) do
    %{message: inspect(error)}
  end
end
