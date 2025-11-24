#!/usr/bin/env elixir
# Submit Real Cerebros Training Job with Dataset
# Usage: Run this in IEx connected to your Phoenix server
#
# iex --sname test --remsh thunderline@$(hostname -s)
# Then: Code.require_file("scripts/submit_real_training.exs")

alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
alias Thunderline.Thunderbolt.Domain

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("🚀 Cerebros Real Training Job Submission")
IO.puts(String.duplicate("=", 80) <> "\n")

# Step 1: Create dataset
IO.puts("📦 Step 1: Creating training dataset...")

{:ok, dataset} = TrainingDataset.create(%{
  name: "Shakespeare Corpus - Real Training #{System.system_time(:second)}",
  description: "Production training run with Shakespeare text corpus"
}, domain: Domain)

IO.puts("✓ Dataset created: #{dataset.id}")

# Step 2: Simulate document collection (mimics real workflow)
IO.puts("\n📊 Step 2: Simulating document collection stages...")

{:ok, dataset} = dataset
  |> Ash.Changeset.for_update(:update, %{
    stage_1_count: 25,
    stage_2_count: 20,
    stage_3_count: 18,
    stage_4_count: 15,
    total_chunks: 5000
  })
  |> Ash.update(domain: Domain)

IO.puts("✓ Document collection stats updated")

# Step 3: Freeze dataset for training
IO.puts("\n❄️  Step 3: Freezing dataset...")

{:ok, dataset} = TrainingDataset.freeze(dataset, domain: Domain)

IO.puts("✓ Dataset frozen (status: #{dataset.status})")

# Step 4: Create corpus file with substantial Shakespeare text
IO.puts("\n📝 Step 4: Creating training corpus...")

corpus_path = "/tmp/shakespeare_corpus_#{System.system_time(:second)}.jsonl"

corpus_content = """
{"text": "To be, or not to be, that is the question"}
{"text": "Whether 'tis nobler in the mind to suffer"}
{"text": "The slings and arrows of outrageous fortune"}
{"text": "Or to take arms against a sea of troubles"}
{"text": "And by opposing end them. To die—to sleep"}
{"text": "No more; and by a sleep to say we end"}
{"text": "The heart-ache and the thousand natural shocks"}
{"text": "That flesh is heir to: 'tis a consummation"}
{"text": "Devoutly to be wish'd. To die, to sleep"}
{"text": "To sleep, perchance to dream—ay, there's the rub"}
{"text": "For in that sleep of death what dreams may come"}
{"text": "When we have shuffled off this mortal coil"}
{"text": "Must give us pause—there's the respect"}
{"text": "That makes calamity of so long life"}
{"text": "For who would bear the whips and scorns of time"}
{"text": "The oppressor's wrong, the proud man's contumely"}
{"text": "The pangs of despised love, the law's delay"}
{"text": "The insolence of office, and the spurns"}
{"text": "That patient merit of th'unworthy takes"}
{"text": "When he himself might his quietus make"}
{"text": "With a bare bodkin? Who would fardels bear"}
{"text": "To grunt and sweat under a weary life"}
{"text": "But that the dread of something after death"}
{"text": "The undiscovered country, from whose bourn"}
{"text": "No traveller returns, puzzles the will"}
{"text": "And makes us rather bear those ills we have"}
{"text": "Than fly to others that we know not of"}
{"text": "Thus conscience doth make cowards of us all"}
{"text": "And thus the native hue of resolution"}
{"text": "Is sicklied o'er with the pale cast of thought"}
{"text": "And enterprises of great pith and moment"}
{"text": "With this regard their currents turn awry"}
{"text": "And lose the name of action"}
{"text": "All the world's a stage"}
{"text": "And all the men and women merely players"}
{"text": "They have their exits and their entrances"}
{"text": "And one man in his time plays many parts"}
{"text": "His acts being seven ages"}
{"text": "At first the infant, mewling and puking in the nurse's arms"}
{"text": "Then the whining schoolboy, with his satchel"}
{"text": "And shining morning face, creeping like snail"}
{"text": "Unwillingly to school"}
{"text": "Friends, Romans, countrymen, lend me your ears"}
{"text": "I come to bury Caesar, not to praise him"}
{"text": "The evil that men do lives after them"}
{"text": "The good is oft interred with their bones"}
{"text": "So let it be with Caesar"}
{"text": "The noble Brutus hath told you Caesar was ambitious"}
{"text": "If it were so, it was a grievous fault"}
{"text": "And grievously hath Caesar answered it"}
"""

File.write!(corpus_path, corpus_content)
line_count = corpus_content |> String.split("\n") |> Enum.reject(&(&1 == "")) |> length()
IO.puts("✓ Corpus file created: #{corpus_path}")
IO.puts("  Lines: #{line_count}")

# Step 5: Set corpus path on dataset
IO.puts("\n🔗 Step 5: Linking corpus to dataset...")

{:ok, dataset} = TrainingDataset.set_corpus_path(dataset, corpus_path, domain: Domain)

IO.puts("✓ Corpus path set")

# Step 6: Create training job with realistic hyperparameters
IO.puts("\n🎯 Step 6: Creating training job...")

{:ok, job} = CerebrosTrainingJob.create(%{
  training_dataset_id: dataset.id,
  model_id: "gpt-4o-mini",
  hyperparameters: %{
    "n_epochs" => 5,
    "batch_size" => 64,
    "learning_rate" => 0.001,
    "seq_length" => 128,
    "embedding_dim" => 256,
    "rnn_units" => 512,
    "vocab_size" => 128,
    "optimizer" => "adam"
  },
  metadata: %{
    "experiment_name" => "shakespeare-production-run",
    "run_name" => "run-#{System.system_time(:second)}",
    "description" => "Real training run with Shakespeare corpus",
    "model_architecture" => "character-level RNN"
  }
}, domain: Domain)

IO.puts("✓ Training job created successfully!")

# Display summary
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("✅ Job Submission Complete!")
IO.puts(String.duplicate("=", 80))
IO.puts("")
IO.puts("📋 Job Details:")
IO.puts("  Dataset ID:      #{dataset.id}")
IO.puts("  Job ID:          #{job.id}")
IO.puts("  Job Status:      #{job.status}")
IO.puts("  Corpus Path:     #{corpus_path}")
IO.puts("  Model ID:        #{job.model_id}")
IO.puts("  Training Lines:  #{line_count}")
IO.puts("")
IO.puts("⚙️  Hyperparameters:")
IO.puts("  Epochs:          #{job.hyperparameters["n_epochs"]}")
IO.puts("  Batch Size:      #{job.hyperparameters["batch_size"]}")
IO.puts("  Learning Rate:   #{job.hyperparameters["learning_rate"]}")
IO.puts("  Sequence Length: #{job.hyperparameters["seq_length"]}")
IO.puts("  Embedding Dim:   #{job.hyperparameters["embedding_dim"]}")
IO.puts("  RNN Units:       #{job.hyperparameters["rnn_units"]}")
IO.puts("  Vocab Size:      #{job.hyperparameters["vocab_size"]}")
IO.puts("")
IO.puts("🔍 Next Steps:")
IO.puts("")
IO.puts("  1. Ensure Cerebros service is running:")
IO.puts("     cd thunderhelm/cerebros_service")
IO.puts("     source venv/bin/activate")
IO.puts("     export THUNDERLINE_API_URL=http://localhost:5001")
IO.puts("     export MLFLOW_TRACKING_URI=http://localhost:5000")
IO.puts("     python cerebros_service.py")
IO.puts("")
IO.puts("  2. Monitor job status:")
IO.puts("     http://localhost:5001/cerebros")
IO.puts("")
IO.puts("  3. Check MLflow experiments:")
IO.puts("     http://localhost:5000")
IO.puts("")
IO.puts("  4. View Oban queue:")
IO.puts("     http://localhost:5001/dev/dashboard (select Oban tab)")
IO.puts("")
IO.puts(String.duplicate("=", 80) <> "\n")

# Return job for further inspection
job
