"""
Job Executor: Adapts cerebros_runner_poc.py logic for Thunderline jobs.

This module:
- Extracts the POC's objective() function
- Replaces hard-coded Bible corpus with job's dataset
- Uses job's hyperparameters instead of Optuna suggestions
- Reports progress back to Thunderline
- Logs to MLflow
- Saves checkpoints
"""
import os
import json
import logging
from typing import Dict, Any, Optional
from pathlib import Path

# TensorFlow imports (matching POC)
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
import numpy as np

# MLflow for experiment tracking
import mlflow
import mlflow.keras

logger = logging.getLogger(__name__)


class JobExecutor:
    """Executes training jobs using POC logic."""

    def __init__(self, thunderline_client):
        """
        Initialize job executor.

        Args:
            thunderline_client: ThunderlineClient instance
        """
        self.client = thunderline_client
        self.checkpoint_dir = Path("./checkpoints")
        self.checkpoint_dir.mkdir(exist_ok=True)

    def execute_job(self, job: Dict[str, Any]) -> None:
        """
        Execute training job.

        Args:
            job: Job data from Thunderline
                {
                    "id": "uuid",
                    "training_dataset_id": "uuid",
                    "model_id": "model-name",
                    "hyperparameters": {...},
                    "metadata": {...}
                }

        Raises:
            Exception: If job execution fails
        """
        job_id = job["id"]
        dataset_id = job["training_dataset_id"]
        model_id = job["model_id"]
        hyperparams = job.get("hyperparameters", {})

        logger.info(f"Executing job {job_id}")
        logger.info(f"Model: {model_id}")
        logger.info(f"Hyperparameters: {hyperparams}")

        try:
            # Update status to training
            self.client.update_job_status(job_id, "training")

            # Start MLflow run
            with mlflow.start_run(run_name=f"job-{job_id}"):
                # Log parameters
                mlflow.log_params(hyperparams)
                mlflow.set_tag("job_id", job_id)
                mlflow.set_tag("model_id", model_id)
                mlflow.set_tag("dataset_id", dataset_id)

                # Get corpus path from Thunderline
                corpus_path = self.client.get_corpus_path(dataset_id)
                logger.info(f"Using corpus: {corpus_path}")

                # Load corpus
                text = self._load_corpus(corpus_path)
                logger.info(f"Loaded corpus: {len(text)} characters")

                # Extract hyperparameters (with defaults from POC)
                vocab_size = hyperparams.get("vocab_size", 128)
                embedding_dim = hyperparams.get("embedding_dim", 64)
                rnn_units = hyperparams.get("rnn_units", 512)
                batch_size = hyperparams.get("batch_size", 64)
                seq_length = hyperparams.get("seq_length", 100)
                epochs = hyperparams.get("epochs", 3)
                learning_rate = hyperparams.get("learning_rate", 0.001)

                # Prepare data (matching POC)
                char2idx, idx2char = self._build_vocab(text, vocab_size)
                encoded_text = self._encode_text(text, char2idx)
                dataset = self._create_dataset(
                    encoded_text, seq_length, batch_size
                )

                # Build model (matching POC architecture)
                model = self._build_model(
                    vocab_size=vocab_size,
                    embedding_dim=embedding_dim,
                    rnn_units=rnn_units,
                    batch_size=batch_size,
                    learning_rate=learning_rate,
                )

                # Train with callbacks
                callbacks = self._create_callbacks(job_id, model_id)

                history = model.fit(
                    dataset,
                    epochs=epochs,
                    callbacks=callbacks,
                    verbose=1,
                )

                # Calculate final metrics
                final_loss = history.history["loss"][-1]

                # Calculate perplexity (exp of loss)
                perplexity = np.exp(final_loss)

                # Report metrics to Thunderline
                metrics = {
                    "final_loss": float(final_loss),
                    "perplexity": float(perplexity),
                    "epochs_completed": epochs,
                }

                self.client.update_job_metrics(job_id, metrics)

                # Log to MLflow
                mlflow.log_metrics(metrics)

                # Save final model
                final_model_path = self.checkpoint_dir / f"{job_id}_final.keras"
                model.save(final_model_path)
                mlflow.keras.log_model(model, "model")

                # Add checkpoint to Thunderline
                self.client.add_checkpoint(job_id, str(final_model_path))

                # Update status to completed
                self.client.update_job_status(
                    job_id, "completed", fine_tuned_model=str(final_model_path)
                )

                logger.info(f"Job {job_id} completed successfully")
                logger.info(f"Final metrics: {metrics}")

        except Exception as e:
            logger.error(f"Job {job_id} failed: {e}", exc_info=True)

            # Report failure to Thunderline
            self.client.update_job_status(
                job_id, "failed", error_message=str(e)
            )

            # Re-raise for caller
            raise

    def _load_corpus(self, corpus_path: str) -> str:
        """
        Load corpus from JSONL file.

        Args:
            corpus_path: Path to corpus JSONL file

        Returns:
            Concatenated text from all entries
        """
        texts = []

        with open(corpus_path, "r", encoding="utf-8") as f:
            for line in f:
                entry = json.loads(line)
                texts.append(entry.get("text", ""))

        combined = "\n".join(texts)
        logger.info(f"Loaded {len(texts)} entries from corpus")

        return combined

    def _build_vocab(self, text: str, vocab_size: int):
        """
        Build vocabulary from text.

        Args:
            text: Input text
            vocab_size: Maximum vocabulary size

        Returns:
            (char2idx, idx2char) dicts
        """
        # Get unique characters
        chars = sorted(set(text))

        # Limit to vocab_size
        chars = chars[:vocab_size]

        # Build mappings
        char2idx = {ch: i for i, ch in enumerate(chars)}
        idx2char = {i: ch for i, ch in enumerate(chars)}

        logger.info(f"Built vocabulary: {len(chars)} characters")

        return char2idx, idx2char

    def _encode_text(self, text: str, char2idx: Dict[str, int]) -> np.ndarray:
        """
        Encode text to indices.

        Args:
            text: Input text
            char2idx: Character to index mapping

        Returns:
            Numpy array of indices
        """
        # Filter out unknown characters
        encoded = [char2idx[ch] for ch in text if ch in char2idx]
        return np.array(encoded, dtype=np.int32)

    def _create_dataset(
        self, encoded_text: np.ndarray, seq_length: int, batch_size: int
    ):
        """
        Create TensorFlow dataset from encoded text.

        Args:
            encoded_text: Encoded text array
            seq_length: Sequence length
            batch_size: Batch size

        Returns:
            tf.data.Dataset
        """

        def split_input_target(chunk):
            input_text = chunk[:-1]
            target_text = chunk[1:]
            return input_text, target_text

        # Create sequences
        char_dataset = tf.data.Dataset.from_tensor_slices(encoded_text)

        sequences = char_dataset.batch(seq_length + 1, drop_remainder=True)

        # Split into input/target
        dataset = sequences.map(split_input_target)

        # Batch and prefetch
        dataset = dataset.batch(batch_size, drop_remainder=True)
        dataset = dataset.prefetch(tf.data.AUTOTUNE)

        return dataset

    def _build_model(
        self,
        vocab_size: int,
        embedding_dim: int,
        rnn_units: int,
        batch_size: int,
        learning_rate: float,
    ):
        """
        Build character-level RNN model (matching POC architecture).

        Args:
            vocab_size: Vocabulary size
            embedding_dim: Embedding dimension
            rnn_units: RNN units
            batch_size: Batch size
            learning_rate: Learning rate

        Returns:
            Compiled Keras model
        """
        model = keras.Sequential(
            [
                layers.Embedding(
                    vocab_size, embedding_dim, batch_input_shape=[batch_size, None]
                ),
                layers.LSTM(
                    rnn_units,
                    return_sequences=True,
                    stateful=True,
                    recurrent_initializer="glorot_uniform",
                ),
                layers.Dense(vocab_size),
            ]
        )

        # Compile
        model.compile(
            optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
            loss=keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        )

        logger.info(f"Built model: vocab_size={vocab_size}, embedding_dim={embedding_dim}, rnn_units={rnn_units}")

        return model

    def _create_callbacks(self, job_id: str, model_id: str):
        """
        Create training callbacks.

        Args:
            job_id: Job UUID
            model_id: Model identifier

        Returns:
            List of Keras callbacks
        """
        callbacks = []

        # Checkpoint callback
        checkpoint_path = self.checkpoint_dir / f"{job_id}_epoch_{{epoch:02d}}.keras"

        checkpoint_callback = keras.callbacks.ModelCheckpoint(
            filepath=str(checkpoint_path),
            save_freq="epoch",
            save_best_only=False,
        )

        callbacks.append(checkpoint_callback)

        # Early stopping
        early_stopping = keras.callbacks.EarlyStopping(
            monitor="loss", patience=3, restore_best_weights=True
        )

        callbacks.append(early_stopping)

        # Custom callback to report metrics to Thunderline
        class ThunderlineCallback(keras.callbacks.Callback):
            def __init__(self, job_id, client):
                super().__init__()
                self.job_id = job_id
                self.client = client

            def on_epoch_end(self, epoch, logs=None):
                logs = logs or {}

                # Report metrics
                metrics = {
                    "epoch": epoch + 1,
                    "loss": float(logs.get("loss", 0)),
                    "perplexity": float(np.exp(logs.get("loss", 0))),
                }

                try:
                    self.client.update_job_metrics(self.job_id, metrics, phase=epoch + 1)
                    logger.info(f"Epoch {epoch + 1} metrics: {metrics}")
                except Exception as e:
                    logger.error(f"Failed to report metrics: {e}")

        callbacks.append(ThunderlineCallback(job_id, self.client))

        return callbacks
