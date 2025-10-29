# Test script: Load baseline model from HuggingFace and create Cerebros training job
#
# This demonstrates:
# 1. Loading a baseline model from HuggingFace using Bumblebee
# 2. Creating a CerebrosTrainingJob with our imported dataset
# 3. Showing the workflow to send to Cerebros service
#
# Usage: mix run scripts/test_baseline_model.exs

alias Thunderline.Thunderbolt.Domain
alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("CEREBROS TRAINING JOB TEST - Baseline Model + CSV Dataset")
IO.puts(String.duplicate("=", 70) <> "\n")

# Step 1: Find our imported dataset
IO.puts("📦 Step 1: Loading imported dataset...")

datasets = Domain.list_training_datasets!(
  query: [filter: [name: "test_gutenberg_sample"]],
  authorize?: false
)

case datasets do
  [] ->
    IO.puts("❌ Dataset 'test_gutenberg_sample' not found!")
    IO.puts("   Run: mix run scripts/test_import.exs first")
    System.halt(1)

  [dataset | _] ->
    IO.puts("✅ Dataset loaded:")
    IO.puts("   ID: #{dataset.id}")
    IO.puts("   Name: #{dataset.name}")
    IO.puts("   Status: #{dataset.status}")
    IO.puts("   Corpus: #{dataset.corpus_path}")
    IO.puts("")

    # Step 2: Load a baseline model from HuggingFace
    IO.puts("🤖 Step 2: Loading baseline model from HuggingFace...")
    IO.puts("   Model: gpt2 (124M params, small for testing)")
    IO.puts("")

    # Note: Bumblebee will download the model on first use (~500MB)
    # It's cached in ~/.cache/huggingface for future runs
    try do
      {:ok, model_info} = Bumblebee.load_model({:hf, "gpt2"})
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "gpt2"})
      {:ok, _generation_config} = Bumblebee.load_generation_config({:hf, "gpt2"})

      IO.puts("✅ Model loaded successfully!")
      IO.puts("   Architecture: #{model_info.spec.architecture}")
      IO.puts("   Hidden size: #{model_info.spec.hidden_size}")
      IO.puts("   Num layers: #{model_info.spec.num_blocks}")
      IO.puts("   Vocab size: #{model_info.spec.vocab_size}")
      IO.puts("")

      # Step 3: Create a Cerebros training job
      IO.puts("🚀 Step 3: Creating Cerebros training job...")

      job_params = %{
        training_dataset_id: dataset.id,
        model_id: "gpt2",
        hyperparameters: %{
          base_model: "gpt2",
          learning_rate: 0.0001,
          batch_size: 8,
          epochs: 3,
          max_seq_length: 512
        },
        metadata: %{
          model_source: "huggingface",
          model_repo: "gpt2",
          test_run: true
        }
      }

      case Domain.create_training_job(job_params, authorize?: false) do
        {:ok, job} ->
          IO.puts("✅ Training job created successfully!")
          IO.puts("")
          IO.puts("📋 Job Details:")
          IO.puts("   Job ID: #{job.id}")
          IO.puts("   Status: #{job.status}")
          IO.puts("   Model: #{job.model_id}")
          IO.puts("   Dataset: #{dataset.name}")
          IO.puts("")

          # Step 4: Show what happens next
          IO.puts("📝 Next Steps:")
          IO.puts("")
          IO.puts("   1. Freeze the dataset:")
          IO.puts("      Domain.freeze_dataset(dataset)")
          IO.puts("")
          IO.puts("   2. Start the training job:")
          IO.puts("      Domain.start_job(job)")
          IO.puts("      # This transitions status: queued -> training")
          IO.puts("")
          IO.puts("   3. Send to Cerebros service:")
          IO.puts("      # Oban worker will:")
          IO.puts("      # - Load corpus JSONL")
          IO.puts("      # - POST to Cerebros /train endpoint")
          IO.puts("      # - Poll for phase updates (1-4)")
          IO.puts("      # - Download checkpoints")
          IO.puts("")
          IO.puts("   4. Load fine-tuned model:")
          IO.puts("      Thunderline.Thunderbolt.CerebrosModel.load_checkpoint(job.id)")
          IO.puts("      # Loads checkpoint into Nx/Bumblebee for inference")
          IO.puts("")

          # Step 5: Show corpus preview
          IO.puts("📄 Training Corpus Preview:")
          IO.puts("")

          if dataset.corpus_path && File.exists?(dataset.corpus_path) do
            lines =
              dataset.corpus_path
              |> File.stream!()
              |> Enum.take(3)

            lines
            |> Enum.with_index(1)
            |> Enum.each(fn {line, idx} ->
              case Jason.decode(line) do
                {:ok, entry} ->
                  text = String.slice(entry["text"], 0..100)
                  metadata = entry["metadata"]

                  IO.puts("   Entry #{idx}:")
                  IO.puts("     Text: #{text}...")
                  IO.puts("     Title: #{metadata["title"]}")
                  IO.puts("     Author: #{metadata["author"]}")
                  IO.puts("")

                {:error, _} ->
                  IO.puts("   Entry #{idx}: [parse error]")
              end
            end)
          end

          # Step 6: Summary
          IO.puts(String.duplicate("=", 70))
          IO.puts("✅ TEST SUCCESSFUL - Ready for Cerebros Training!")
          IO.puts(String.duplicate("=", 70))
          IO.puts("")
          IO.puts("🎯 What We Have:")
          IO.puts("   ✓ Baseline model loaded from HuggingFace (GPT-2)")
          IO.puts("   ✓ Training dataset with 5 literary samples")
          IO.puts("   ✓ Training job created and linked")
          IO.puts("   ✓ Corpus in JSONL format with metadata")
          IO.puts("")
          IO.puts("🔥 What Cerebros Will Do:")
          IO.puts("   1. Fine-tune GPT-2 on literary corpus")
          IO.puts("   2. Generate 4 progressive checkpoints")
          IO.puts("   3. Return ONNX/Keras models for inference")
          IO.puts("   4. Track metrics (loss, perplexity, etc.)")
          IO.puts("")
          IO.puts("🚀 To Actually Run Training:")
          IO.puts("   1. Ensure Cerebros service is running (localhost:8000)")
          IO.puts("   2. Freeze dataset: Domain.freeze_dataset(dataset)")
          IO.puts("   3. Start job: Domain.start_job(job)")
          IO.puts("   4. Oban worker will handle the rest automatically")
          IO.puts("")

        {:error, error} ->
          IO.puts("❌ Failed to create training job:")
          IO.inspect(error, pretty: true)
          System.halt(1)
      end
    rescue
      e ->
        IO.puts("❌ Failed to load model:")
        IO.puts("   #{Exception.message(e)}")
        IO.puts("")
        IO.puts("💡 This might happen if:")
        IO.puts("   - First time loading (model needs to download)")
        IO.puts("   - No internet connection")
        IO.puts("   - HuggingFace is down")
        IO.puts("")
        IO.puts("   The model (~500MB) will be cached in:")
        IO.puts("   ~/.cache/huggingface/hub/")
        System.halt(1)
    end
end
