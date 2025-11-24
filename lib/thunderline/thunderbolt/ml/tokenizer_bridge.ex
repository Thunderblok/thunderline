defmodule Thunderline.Thunderbolt.ML.TokenizerBridge do
  @moduledoc """
  Bridge to HuggingFace tokenizers via Python for Cerebros models.

  Provides tokenization and detokenization for text-to-token-ids conversion,
  which is required for ONNX model inference.

  ## Configuration

  Configure the tokenizer path in your config:

      config :thunderline, Thunderline.Thunderbolt.ML.TokenizerBridge,
        tokenizer_path: "priv/models/tokenizer",
        max_seq_length: 40,
        pad_token_id: 0

  ## Usage

      # Encode text to token IDs
      {:ok, token_ids} = TokenizerBridge.encode("Hello world")

      # Decode token IDs back to text
      {:ok, text} = TokenizerBridge.decode([1, 2, 3, 4])

      # Encode and pad to max length
      {:ok, padded} = TokenizerBridge.encode_padded("Hello", 40)

  ## Notes

  This module uses Python via Pythonx/Snex for tokenizer operations.
  For production, consider caching tokenizer instances.
  """

  require Logger

  @default_config [
    tokenizer_path: "priv/models/tokenizer",
    max_seq_length: 40,
    pad_token_id: 0
  ]

  @doc """
  Encode text to token IDs.

  ## Parameters

  - `text` - Input text string
  - `opts` - Options:
    - `:tokenizer_path` - Path to tokenizer directory
    - `:add_special_tokens` - Whether to add special tokens (default: false)

  ## Returns

  - `{:ok, token_ids}` - List of integer token IDs
  - `{:error, reason}` - Encoding failed
  """
  @spec encode(String.t(), keyword()) :: {:ok, list(integer())} | {:error, term()}
  def encode(text, opts \\ []) do
    tokenizer_path = Keyword.get(opts, :tokenizer_path, config(:tokenizer_path))
    add_special_tokens = Keyword.get(opts, :add_special_tokens, false)

    python_code = """
    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained("#{tokenizer_path}")
    token_ids = tokenizer.encode("#{escape_string(text)}", add_special_tokens=#{add_special_tokens})
    result = {"status": "ok", "token_ids": token_ids}
    """

    case run_python(python_code) do
      {:ok, %{"status" => "ok", "token_ids" => ids}} ->
        {:ok, ids}

      {:ok, %{"status" => "error", "message" => msg}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("[TokenizerBridge] encode failed: #{inspect(error)}")
      {:error, {:encode_exception, error}}
  end

  @doc """
  Encode text and pad to specified length.

  ## Parameters

  - `text` - Input text string
  - `max_length` - Target sequence length (default from config)
  - `opts` - Additional options

  ## Returns

  - `{:ok, padded_ids}` - List of exactly `max_length` token IDs
  - `{:error, reason}` - Encoding failed
  """
  @spec encode_padded(String.t(), pos_integer(), keyword()) ::
          {:ok, list(integer())} | {:error, term()}
  def encode_padded(text, max_length \\ nil, opts \\ []) do
    max_length = max_length || config(:max_seq_length)
    pad_token_id = Keyword.get(opts, :pad_token_id, config(:pad_token_id))

    case encode(text, opts) do
      {:ok, token_ids} ->
        padded = pad_or_truncate(token_ids, max_length, pad_token_id)
        {:ok, padded}

      error ->
        error
    end
  end

  @doc """
  Decode token IDs to text.

  ## Parameters

  - `token_ids` - List of integer token IDs
  - `opts` - Options:
    - `:tokenizer_path` - Path to tokenizer directory
    - `:skip_special_tokens` - Whether to skip special tokens (default: true)

  ## Returns

  - `{:ok, text}` - Decoded text string
  - `{:error, reason}` - Decoding failed
  """
  @spec decode(list(integer()), keyword()) :: {:ok, String.t()} | {:error, term()}
  def decode(token_ids, opts \\ []) do
    tokenizer_path = Keyword.get(opts, :tokenizer_path, config(:tokenizer_path))
    skip_special = Keyword.get(opts, :skip_special_tokens, true)

    ids_json = Jason.encode!(token_ids)

    python_code = """
    from transformers import AutoTokenizer
    import json
    tokenizer = AutoTokenizer.from_pretrained("#{tokenizer_path}")
    token_ids = json.loads('#{ids_json}')
    text = tokenizer.decode(token_ids, skip_special_tokens=#{skip_special})
    result = {"status": "ok", "text": text}
    """

    case run_python(python_code) do
      {:ok, %{"status" => "ok", "text" => text}} ->
        {:ok, text}

      {:ok, %{"status" => "error", "message" => msg}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("[TokenizerBridge] decode failed: #{inspect(error)}")
      {:error, {:decode_exception, error}}
  end

  @doc """
  Get tokenizer vocabulary size.
  """
  @spec vocab_size(keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def vocab_size(opts \\ []) do
    tokenizer_path = Keyword.get(opts, :tokenizer_path, config(:tokenizer_path))

    python_code = """
    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained("#{tokenizer_path}")
    result = {"status": "ok", "vocab_size": tokenizer.vocab_size}
    """

    case run_python(python_code) do
      {:ok, %{"status" => "ok", "vocab_size" => size}} ->
        {:ok, size}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get special token IDs (pad, eos, bos, etc).
  """
  @spec special_tokens(keyword()) :: {:ok, map()} | {:error, term()}
  def special_tokens(opts \\ []) do
    tokenizer_path = Keyword.get(opts, :tokenizer_path, config(:tokenizer_path))

    python_code = """
    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained("#{tokenizer_path}")
    result = {
        "status": "ok",
        "pad_token_id": tokenizer.pad_token_id,
        "eos_token_id": tokenizer.eos_token_id,
        "bos_token_id": tokenizer.bos_token_id,
        "unk_token_id": tokenizer.unk_token_id
    }
    """

    case run_python(python_code) do
      {:ok, %{"status" => "ok"} = result} ->
        {:ok, Map.drop(result, ["status"])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp pad_or_truncate(token_ids, max_length, pad_token_id) do
    len = length(token_ids)

    cond do
      len == max_length ->
        token_ids

      len > max_length ->
        # Truncate from the left (keep most recent)
        Enum.take(token_ids, -max_length)

      len < max_length ->
        # Pad on the right
        padding = List.duplicate(pad_token_id, max_length - len)
        token_ids ++ padding
    end
  end

  defp run_python(code) do
    # Try Snex first, fallback to System.cmd
    if Code.ensure_loaded?(Snex) do
      run_via_snex(code)
    else
      run_via_system(code)
    end
  end

  defp run_via_snex(code) do
    case Snex.eval(code) do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:ok, other} ->
        {:error, {:unexpected_result, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_via_system(code) do
    # Fallback: run Python via command line
    wrapped_code = """
    import json
    import sys
    try:
        #{code}
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        sys.exit(1)
    """

    case System.cmd("python3", ["-c", wrapped_code], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(String.trim(output)) do
          {:ok, result} -> {:ok, result}
          {:error, _} -> {:error, {:json_decode_failed, output}}
        end

      {output, _code} ->
        {:error, {:python_error, output}}
    end
  end

  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp config(key) do
    Application.get_env(:thunderline, __MODULE__, @default_config)
    |> Keyword.get(key, @default_config[key])
  end
end
