#!/usr/bin/env elixir

# Submit a training job with the provided corpus text
# Usage: mix run scripts/submit_training_job.exs

alias Thunderline.Thunderbolt.Resources.TrainingDataset
alias Thunderline.Repo
require Logger

corpus_text = """
Consciousness is the brain modeling itself and the environment through recursive patterns of perception and prediction. Cultures encode meaning through myth, religion, art, and law — these shared stories act as collective operating systems that coordinate millions of people. Economics is the physics of incentives; politics the choreography of power; ethics the ongoing negotiation of how to minimize harm while maximizing flourishing. Modern computation extends human cognition into machines, producing artificial intelligence capable of pattern recognition, autonomous action, and creative synthesis. The future will be shaped by the tension between centralization and decentralization, autonomy and control, biology and silicon. At every scale — physical, psychological, social, cosmic — the same deep principles govern reality: information flows, systems evolve, complexity emerges, and everything seeks equilibrium while simultaneously being pushed away from it by energy, desire, and change.
"""

Logger.info("Creating training dataset from corpus text...")

# Create the dataset using Ash input format (string keys)
dataset_attrs = %{
  "name" => "consciousness_corpus_#{System.system_time(:second)}",
  "description" => "Training corpus on consciousness, culture, and complex systems"
}

case Ash.create(TrainingDataset, dataset_attrs) do
  {:ok, dataset} ->
    Logger.info("✓ Dataset created: #{dataset.id}")

    # Write corpus to CSV file
    csv_path = Path.join(["priv", "training_data", "#{dataset.id}.csv"])
    csv_dir = Path.dirname(csv_path)
    File.mkdir_p!(csv_dir)

    # Split corpus into sentences for training samples
    sentences =
      corpus_text
      |> String.split(~r/[.!?]+\s+/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(String.length(&1) > 10))

    Logger.info("Split corpus into #{length(sentences)} training samples")

    # Create CSV with text and labels
    csv_content =
      ["text,label\n"] ++
      Enum.map(sentences, fn sentence ->
        # Escape quotes and wrap in quotes
        escaped = String.replace(sentence, "\"", "\"\"")
        "\"#{escaped}\",general\n"
      end)

    File.write!(csv_path, csv_content)
    Logger.info("✓ Wrote training data to #{csv_path}")

    # Update dataset status to ready
    case Ash.update(dataset, %{status: :ready, file_path: csv_path}) do
      {:ok, updated_dataset} ->
        Logger.info("✓ Dataset status updated to :ready")

        # Try to enqueue Oban job if enabled
        if Application.get_env(:thunderline, Oban) != false do
          job_attrs = %{
            dataset_id: updated_dataset.id,
            model_type: "general_chat",
            priority: 1,
            config: %{
              "epochs" => 3,
              "batch_size" => 16,
              "learning_rate" => 0.001,
              "enable_upm" => false,
              "enable_mlflow" => true
            }
          }

          case Thunderline.Workers.CerebrosTrainer.new(job_attrs) |> Oban.insert() do
            {:ok, job} ->
              Logger.info("✓ Oban job enqueued: #{job.id}")
              Logger.info("Training job submitted successfully!")
              Logger.info("Dataset ID: #{updated_dataset.id}")
              Logger.info("Job ID: #{job.id}")

            {:error, reason} ->
              Logger.error("✗ Failed to enqueue Oban job: #{inspect(reason)}")
              Logger.info("Dataset created but job not enqueued (Oban may be disabled)")
          end
        else
          Logger.warning("Oban is disabled - job not enqueued")
          Logger.info("Dataset created successfully with ID: #{updated_dataset.id}")
          Logger.info("To process this job, enable Oban with TL_ENABLE_OBAN=1")
        end

      {:error, reason} ->
        Logger.error("✗ Failed to update dataset status: #{inspect(reason)}")
    end

  {:error, reason} ->
    Logger.error("✗ Failed to create dataset: #{inspect(reason)}")
end
