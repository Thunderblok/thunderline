defmodule ThunderlineWeb.AutoMLController do
  @moduledoc """
  HTTP API for Auto-ML Driver.

  Endpoints:
  - POST /api/hpo/studies - Create HPO study
  - POST /api/hpo/trials/tell - Report trial results
  - GET /api/hpo/studies/:id/status - Get study status
  - POST /api/datasets/register - Register dataset
  """

  use ThunderlineWeb, :controller
  require Logger
  alias Thunderline.Thunderbolt.{AutoMLDriver, DatasetManager}

  # POST /api/hpo/studies
  def create_study(conn, params) do
    Logger.info("[AutoMLController] Creating HPO study: #{inspect(params)}")

    case AutoMLDriver.create_study(params) do
      {:ok, study_id} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          study_id: study_id,
          message: "HPO study created successfully"
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  # POST /api/hpo/trials/tell
  def tell_result(conn, params) do
    study_id = params["study_id"]
    trial_id = params["trial_id"]
    objective = params["objective"]
    artifact = params["artifact"]

    case AutoMLDriver.tell_result(study_id, trial_id, objective, artifact) do
      :ok ->
        json(conn, %{success: true, message: "Trial result recorded"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  # GET /api/hpo/studies/:id/status
  def get_study_status(conn, %{"id" => study_id}) do
    case AutoMLDriver.get_study_status(study_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Study not found"})

      study ->
        json(conn, %{
          success: true,
          study: %{
            id: study.id,
            name: study.name,
            status: study.status,
            trials_completed: study.trials_completed,
            trials_running: study.trials_running,
            total_trials: study.n_trials,
            best_trial: study.best_trial,
            created_at: study.created_at
          }
        })
    end
  end

  # POST /api/datasets/register
  def register_dataset(conn, params) do
    Logger.info("[AutoMLController] Registering dataset: #{inspect(params)}")

    # DatasetManager.create_phase1_dataset/1 currently always returns {:ok, _, _}
    {:ok, dataset_id, actual_samples} =
      DatasetManager.create_phase1_dataset(
        target_samples: params["samples"] || 10_000,
        max_context_length: params["max_context_length"] || 512
      )

    conn
    |> put_status(:created)
    |> json(%{
      success: true,
      dataset_id: dataset_id,
      samples: actual_samples,
      message: "Dataset registered successfully"
    })
  end

  # POST /api/datasets/clean - Clean raw text samples
  def clean_samples(conn, params) do
    samples = params["samples"] || []
    max_length = params["max_context_length"] || 512

    cleaned =
      Enum.map(samples, fn sample ->
        cleaned_text = DatasetManager.preprocess_sample(sample["text"], max_length)

        %{
          original: sample["text"],
          cleaned: cleaned_text,
          length_chars: String.length(cleaned_text),
          # Rough approximation
          length_tokens: div(String.length(cleaned_text), 4)
        }
      end)

    json(conn, %{
      success: true,
      samples: cleaned,
      total_processed: length(cleaned)
    })
  end
end
