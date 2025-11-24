defmodule Thunderline.Thunderbolt.ML.CerebrosGenerator do
  @moduledoc """
  Text generation using CerebrosNotGPT ONNX models.

  Provides complete text generation pipeline:
  1. Tokenize input prompt
  2. Run ONNX inference to get next-token logits
  3. Apply sampling strategy (greedy, temperature, top-k, top-p)
  4. Repeat until max tokens or EOS
  5. Decode tokens back to text

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.ML.CerebrosGenerator,
        model_path: "priv/models/cerebros.onnx",
        tokenizer_path: "priv/models/tokenizer",
        max_seq_length: 40,
        default_max_tokens: 50

  ## Usage

      # Simple generation
      {:ok, text} = CerebrosGenerator.generate("In the beginning")

      # With options
      {:ok, text} = CerebrosGenerator.generate("Hello",
        max_tokens: 100,
        temperature: 0.8,
        top_k: 50,
        top_p: 0.95
      )

      # Greedy (deterministic)
      {:ok, text} = CerebrosGenerator.generate_greedy("Test prompt")

  """

  require Logger

  alias Thunderline.Thunderbolt.Resources.OnnxInference
  alias Thunderline.Thunderbolt.ML.TokenizerBridge

  @default_config [
    model_path: "priv/models/cerebros.onnx",
    tokenizer_path: "priv/models/tokenizer",
    max_seq_length: 40,
    default_max_tokens: 50,
    vocabulary_size: 49152,
    pad_token_id: 0
  ]

  @type generation_opts :: [
          max_tokens: pos_integer(),
          temperature: float(),
          top_k: pos_integer(),
          top_p: float(),
          repetition_penalty: float(),
          presence_penalty: float(),
          frequency_penalty: float(),
          model_path: String.t(),
          tokenizer_path: String.t()
        ]

  @doc """
  Generate text continuation from a prompt.

  ## Parameters

  - `prompt` - Input text to continue
  - `opts` - Generation options:
    - `:max_tokens` - Maximum new tokens to generate (default: 50)
    - `:temperature` - Sampling temperature (default: 0.7)
    - `:top_k` - Top-k sampling parameter (default: 50)
    - `:top_p` - Top-p (nucleus) sampling parameter (default: 0.95)
    - `:repetition_penalty` - Penalty for repeated tokens (default: 1.2)
    - `:model_path` - Path to ONNX model
    - `:tokenizer_path` - Path to tokenizer

  ## Returns

  - `{:ok, generated_text}` - Full text including prompt and generation
  - `{:error, reason}` - Generation failed

  ## Examples

      {:ok, text} = CerebrosGenerator.generate("Once upon a time")
      # => "Once upon a time there was a great king who..."

      {:ok, text} = CerebrosGenerator.generate("The meaning of life is",
        temperature: 0.9,
        max_tokens: 100
      )

  """
  @spec generate(String.t(), generation_opts()) :: {:ok, String.t()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, config(:default_max_tokens))
    temperature = Keyword.get(opts, :temperature, 0.7)
    top_k = Keyword.get(opts, :top_k, 50)
    top_p = Keyword.get(opts, :top_p, 0.95)
    repetition_penalty = Keyword.get(opts, :repetition_penalty, 1.2)
    model_path = Keyword.get(opts, :model_path, config(:model_path))
    tokenizer_path = Keyword.get(opts, :tokenizer_path, config(:tokenizer_path))
    max_seq_length = config(:max_seq_length)
    pad_token_id = config(:pad_token_id)

    start_time = System.monotonic_time(:millisecond)

    :telemetry.execute(
      [:thunderline, :cerebros, :generate, :start],
      %{system_time: System.system_time()},
      %{prompt_length: String.length(prompt), max_tokens: max_tokens}
    )

    with {:ok, token_ids} <- TokenizerBridge.encode(prompt, tokenizer_path: tokenizer_path),
         {:ok, generated_ids} <-
           generate_tokens(
             token_ids,
             model_path,
             max_tokens,
             max_seq_length,
             pad_token_id,
             %{
               temperature: temperature,
               top_k: top_k,
               top_p: top_p,
               repetition_penalty: repetition_penalty
             }
           ),
         {:ok, text} <- TokenizerBridge.decode(generated_ids, tokenizer_path: tokenizer_path) do
      duration_ms = System.monotonic_time(:millisecond) - start_time
      tokens_generated = length(generated_ids) - length(token_ids)

      :telemetry.execute(
        [:thunderline, :cerebros, :generate, :stop],
        %{duration_ms: duration_ms, tokens_generated: tokens_generated},
        %{prompt_length: String.length(prompt)}
      )

      Logger.debug(
        "[CerebrosGenerator] Generated #{tokens_generated} tokens in #{duration_ms}ms"
      )

      {:ok, text}
    else
      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:thunderline, :cerebros, :generate, :error],
          %{duration_ms: duration_ms},
          %{error: reason}
        )

        Logger.error("[CerebrosGenerator] Generation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Generate text using greedy decoding (deterministic).

  Always selects the highest probability token at each step.
  Good for factual/deterministic outputs.
  """
  @spec generate_greedy(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_greedy(prompt, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:temperature, 1.0)
      |> Keyword.put(:top_k, 1)
      |> Keyword.put(:top_p, 1.0)

    generate(prompt, opts)
  end

  @doc """
  Generate text with creative sampling.

  Uses higher temperature and broader sampling for more creative outputs.
  """
  @spec generate_creative(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_creative(prompt, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:temperature, 0.9)
      |> Keyword.put_new(:top_k, 100)
      |> Keyword.put_new(:top_p, 0.98)

    generate(prompt, opts)
  end

  # Private implementation

  defp generate_tokens(
         token_ids,
         model_path,
         max_tokens,
         max_seq_length,
         pad_token_id,
         sampling_opts
       ) do
    Enum.reduce_while(1..max_tokens, {:ok, token_ids}, fn _i, {:ok, acc} ->
      case generate_next_token(acc, model_path, max_seq_length, pad_token_id, sampling_opts) do
        {:ok, ^pad_token_id} ->
          # EOS reached
          {:halt, {:ok, acc}}

        {:ok, next_token} ->
          {:cont, {:ok, acc ++ [next_token]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp generate_next_token(token_ids, model_path, max_seq_length, pad_token_id, sampling_opts) do
    # Pad/truncate to max_seq_length
    padded = pad_or_truncate(token_ids, max_seq_length, pad_token_id)

    # Run ONNX inference
    with {:ok, result} <- OnnxInference.infer(model_path, %{data: [padded]}, %{}) do
      # Get logits (shape: [1, vocab_size])
      logits = result.predictions |> List.first()

      # Apply repetition penalty
      logits = apply_repetition_penalty(logits, token_ids, sampling_opts.repetition_penalty)

      # Sample next token
      next_token = sample_token(logits, sampling_opts)

      {:ok, next_token}
    end
  end

  defp pad_or_truncate(token_ids, max_length, pad_token_id) do
    len = length(token_ids)

    cond do
      len == max_length ->
        token_ids

      len > max_length ->
        Enum.take(token_ids, -max_length)

      len < max_length ->
        token_ids ++ List.duplicate(pad_token_id, max_length - len)
    end
  end

  defp apply_repetition_penalty(logits, token_ids, penalty) when penalty == 1.0, do: logits

  defp apply_repetition_penalty(logits, token_ids, penalty) do
    unique_tokens = Enum.uniq(token_ids)

    logits
    |> Enum.with_index()
    |> Enum.map(fn {logit, idx} ->
      if idx in unique_tokens do
        if logit > 0, do: logit / penalty, else: logit * penalty
      else
        logit
      end
    end)
  end

  defp sample_token(logits, %{temperature: temp, top_k: top_k, top_p: top_p}) do
    # Apply temperature
    scaled = Enum.map(logits, &(&1 / temp))

    # Compute probabilities
    probs = softmax(scaled)

    # Apply top-k
    probs =
      if top_k > 0 do
        apply_top_k(probs, top_k)
      else
        probs
      end

    # Apply top-p (nucleus sampling)
    probs =
      if top_p < 1.0 do
        apply_top_p(probs, top_p)
      else
        probs
      end

    # Renormalize
    sum = Enum.sum(probs)

    probs =
      if sum > 0 do
        Enum.map(probs, &(&1 / sum))
      else
        # Fallback to uniform
        List.duplicate(1.0 / length(probs), length(probs))
      end

    # Sample from distribution
    sample_from_distribution(probs)
  end

  defp softmax(logits) do
    max_val = Enum.max(logits)
    exp_vals = Enum.map(logits, &:math.exp(&1 - max_val))
    sum_exp = Enum.sum(exp_vals)
    Enum.map(exp_vals, &(&1 / sum_exp))
  end

  defp apply_top_k(probs, k) do
    indexed = Enum.with_index(probs)
    sorted = Enum.sort_by(indexed, fn {p, _} -> -p end)
    top_indices = sorted |> Enum.take(k) |> Enum.map(fn {_, i} -> i end) |> MapSet.new()

    Enum.with_index(probs)
    |> Enum.map(fn {p, i} ->
      if MapSet.member?(top_indices, i), do: p, else: 0.0
    end)
  end

  defp apply_top_p(probs, p) do
    indexed = Enum.with_index(probs)
    sorted = Enum.sort_by(indexed, fn {prob, _} -> -prob end)

    {_, cumsum_indices} =
      Enum.reduce_while(sorted, {0.0, []}, fn {prob, idx}, {cumsum, indices} ->
        new_cumsum = cumsum + prob

        if cumsum < p do
          {:cont, {new_cumsum, [idx | indices]}}
        else
          {:halt, {new_cumsum, indices}}
        end
      end)

    keep_set = MapSet.new(cumsum_indices)

    Enum.with_index(probs)
    |> Enum.map(fn {prob, i} ->
      if MapSet.member?(keep_set, i), do: prob, else: 0.0
    end)
  end

  defp sample_from_distribution(probs) do
    # Generate random number between 0 and 1
    random = :rand.uniform()

    # Find the index where cumulative probability exceeds random
    {_, index} =
      Enum.reduce_while(Enum.with_index(probs), 0.0, fn {prob, idx}, cumsum ->
        new_cumsum = cumsum + prob

        if new_cumsum >= random do
          {:halt, {new_cumsum, idx}}
        else
          {:cont, new_cumsum}
        end
      end)

    # Handle edge case where we didn't find an index
    case index do
      idx when is_integer(idx) -> idx
      _ -> Enum.find_index(probs, &(&1 > 0)) || 0
    end
  end

  defp config(key) do
    Application.get_env(:thunderline, __MODULE__, @default_config)
    |> Keyword.get(key, @default_config[key])
  end
end
