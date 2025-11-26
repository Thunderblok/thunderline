# Quick Paste Training Job Submission
# Copy and paste this entire block into your IEx session

alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
alias Thunderline.Thunderbolt.Domain

# Create dataset
dataset = Ash.create!(TrainingDataset, %{
  name: "Shakespeare #{System.system_time(:second)}",
  description: "Real training run"
})

# Freeze it
dataset = Ash.update!(dataset, :freeze)

# Create corpus
corpus_path = "/tmp/shakespeare_#{System.system_time(:second)}.jsonl"
File.write!(corpus_path, """
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
""")

# Link corpus to dataset
dataset = Ash.update!(dataset, :set_corpus_path, %{corpus_path: corpus_path})

# Create training job
job = Ash.create!(CerebrosTrainingJob, %{
  training_dataset_id: dataset.id,
  model_id: "gpt-4o-mini",
  hyperparameters: %{
    "n_epochs" => 5,
    "batch_size" => 64,
    "learning_rate" => 0.001,
    "seq_length" => 128,
    "embedding_dim" => 256,
    "rnn_units" => 512,
    "vocab_size" => 128
  },
  metadata: %{
    "experiment_name" => "shakespeare-production",
    "run_name" => "run-#{System.system_time(:second)}"
  }
})

IO.puts("\n✅ JOB CREATED!")
IO.puts("Dataset ID: #{dataset.id}")
IO.puts("Job ID: #{job.id}")
IO.puts("Status: #{job.status}")
IO.puts("Corpus: #{corpus_path}")
IO.puts("\n🔍 Monitor at:")
IO.puts("  Cerebros: http://localhost:5001/cerebros")
IO.puts("  MLflow:   http://localhost:5000")
IO.puts("")

job
