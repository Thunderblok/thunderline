defmodule Thunderline.Thunderbolt.CerebrosBridge.NLP do
  @moduledoc """
  Natural Language Processing interface using Spacy via Pythonx.

  Provides named entity recognition, tokenization, sentiment analysis,
  and syntactic parsing capabilities for Thunderline.

  ## Usage

      # Extract named entities
      {:ok, result} = NLP.extract_entities("Apple Inc. was founded by Steve Jobs in Cupertino.")
      # => %{entities: [%{text: "Apple Inc.", label: "ORG"}, ...]}

      # Tokenize text
      {:ok, result} = NLP.tokenize("The quick brown fox jumps.")
      # => %{tokens: [%{text: "The", pos: "DET", lemma: "the"}, ...]}

      # Analyze sentiment (basic)
      {:ok, result} = NLP.analyze_sentiment("This is a great product!")
      # => %{sentiment: "positive", score: 0.75}

      # Full NLP processing
      {:ok, result} = NLP.process("Complex text here...")
      # => %{entities: [...], sentiment: "...", noun_chunks: [...], sentences: [...]}
  """

  require Logger

  @telemetry_base [:cerebros, :nlp]

  # -- Public API ---------------------------------------------------------------

  @doc """
  Extract named entities from text.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")
    * `:timeout_ms` - Operation timeout in milliseconds (default: 10_000)

  ## Returns
    * `{:ok, result}` - Success with entities list
    * `{:error, reason}` - Failure

  ## Example
      {:ok, %{entities: entities}} = NLP.extract_entities("Microsoft bought GitHub in 2018.")
      # entities = [
      #   %{text: "Microsoft", label: "ORG", start: 0, end: 9},
      #   %{text: "GitHub", label: "ORG", start: 17, end: 23},
      #   %{text: "2018", label: "DATE", start: 27, end: 31}
      # ]
  """
  @spec extract_entities(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract_entities(text, opts \\ []) when is_binary(text) do
    call_nlp_function("extract_entities", text, opts)
  end

  @doc """
  Tokenize text with detailed linguistic features.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")
    * `:timeout_ms` - Operation timeout in milliseconds (default: 10_000)

  ## Returns
    * `{:ok, result}` - Success with tokens list
    * `{:error, reason}` - Failure
  """
  @spec tokenize(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def tokenize(text, opts \\ []) when is_binary(text) do
    call_nlp_function("tokenize", text, opts)
  end

  @doc """
  Analyze text sentiment (basic implementation).

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")
    * `:timeout_ms` - Operation timeout in milliseconds (default: 10_000)

  ## Returns
    * `{:ok, result}` - Success with sentiment analysis
    * `{:error, reason}` - Failure
  """
  @spec analyze_sentiment(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_sentiment(text, opts \\ []) when is_binary(text) do
    call_nlp_function("analyze_sentiment", text, opts)
  end

  @doc """
  Analyze syntactic structure of text.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")
    * `:timeout_ms` - Operation timeout in milliseconds (default: 10_000)

  ## Returns
    * `{:ok, result}` - Success with noun chunks and sentences
    * `{:error, reason}` - Failure
  """
  @spec analyze_syntax(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_syntax(text, opts \\ []) when is_binary(text) do
    call_nlp_function("analyze_syntax", text, opts)
  end

  @doc """
  Full NLP processing pipeline.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")
    * `:include_entities` - Include entity extraction (default: true)
    * `:include_tokens` - Include tokenization (default: false, can be verbose)
    * `:include_sentiment` - Include sentiment analysis (default: true)
    * `:include_syntax` - Include syntax analysis (default: true)
    * `:timeout_ms` - Operation timeout in milliseconds (default: 15_000)

  ## Returns
    * `{:ok, result}` - Success with comprehensive NLP analysis
    * `{:error, reason}` - Failure
  """
  @spec process(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def process(text, opts \\ []) when is_binary(text) do
    call_nlp_function("process_text", text, opts)
  end

  @doc """
  Check if NLP service is healthy and available.

  ## Returns
    * `{:ok, health}` - Service is healthy with version info
    * `{:error, reason}` - Service unavailable
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    python_code = """
import nlp_service
result = nlp_service.health_check()
result
"""

    try do
      {result_obj, _} = Pythonx.eval(python_code, %{})
      decoded = Pythonx.decode(result_obj)
      
      case decoded do
        %{"status" => "healthy"} = health ->
          {:ok, health}
        
        %{"status" => "unhealthy"} = health ->
          {:error, {:unhealthy, health}}
        
        other ->
          {:error, {:unexpected_response, other}}
      end
    rescue
      error ->
        {:error, {:nlp_unavailable, error}}
    end
  end

  # -- Internal Helpers ---------------------------------------------------------

  defp call_nlp_function(function_name, text, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, default_timeout(function_name))
    nlp_opts = opts |> Enum.into(%{}) |> Map.delete(:timeout_ms)

    meta = %{function: function_name, text_length: String.length(text)}
    :telemetry.execute(@telemetry_base ++ [:start], %{}, meta)

    t0 = System.monotonic_time()

    task = Task.Supervisor.async_nolink(Thunderline.TaskSupervisor, fn ->
      execute_nlp_call(function_name, text, nlp_opts)
    end)

    result = case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, decoded}} ->
        {:ok, decoded}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, :timeout}
    end

    duration_ms = System.convert_time_unit(System.monotonic_time() - t0, :native, :millisecond)

    case result do
      {:ok, data} ->
        :telemetry.execute(
          @telemetry_base ++ [:stop],
          %{duration_ms: duration_ms},
          Map.put(meta, :ok, true)
        )
        {:ok, data}

      {:error, error} ->
        :telemetry.execute(
          @telemetry_base ++ [:exception],
          %{duration_ms: duration_ms},
          Map.merge(meta, %{error: inspect(error)})
        )
        {:error, error}
    end
  rescue
    error ->
      Logger.error("[CerebrosBridge.NLP] Unexpected error: #{inspect(error)}")
      {:error, {:unexpected_error, error}}
  end

  defp execute_nlp_call(function_name, text, opts) do
    python_code = """
import nlp_service

# text and opts are passed from Elixir via globals
result = nlp_service.#{function_name}(text, opts)
result
"""

    globals = %{
      "text" => text,
      "opts" => normalize_opts(opts)
    }

    {result_obj, _} = Pythonx.eval(python_code, globals)
    decoded = Pythonx.decode(result_obj)

    case decoded do
      %{"status" => "success"} = result ->
        {:ok, result}

      %{"status" => status, "error" => error} ->
        {:error, {status, error}}

      other ->
        {:ok, other}
    end
  rescue
    error ->
      {:error, {:pythonx_call_failed, error}}
  end

  defp normalize_opts(opts) when is_map(opts) do
    Enum.into(opts, %{}, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp normalize_value(atom) when is_atom(atom) and not is_nil(atom) and atom not in [true, false] do
    to_string(atom)
  end

  defp normalize_value(value), do: value

  defp default_timeout("process_text"), do: 15_000
  defp default_timeout("tokenize"), do: 10_000
  defp default_timeout(_), do: 8_000
end
