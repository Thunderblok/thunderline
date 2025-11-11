defmodule Thunderline.Thunderbolt.CerebrosBridge.NLP do
  @moduledoc """
  Natural Language Processing interface using Spacy via subprocess + JSON.

  Provides named entity recognition, tokenization, sentiment analysis,
  and syntactic parsing capabilities for Thunderline.

  Uses simple subprocess communication instead of Pythonx to avoid msgpack serialization issues.

  ## Usage

      # Extract named entities
      {:ok, result} = NLP.extract_entities("Apple Inc. was founded by Steve Jobs in Cupertino.")
      # => %{"entities" => [%{"text" => "Apple Inc.", "label" => "ORG"}, ...]}

      # Tokenize text
      {:ok, result} = NLP.tokenize("The quick brown fox jumps.")
      # => %{"tokens" => [%{"text" => "The", "pos" => "DET", "lemma" => "the"}, ...]}

      # Analyze sentiment (basic)
      {:ok, result} = NLP.analyze_sentiment("This is a great product!")
      # => %{"sentiment" => "positive", "score" => 0.75}

      # Full NLP processing
      {:ok, result} = NLP.process("Complex text here...")
      # => %{"entities" => [...], "sentiment" => "...", "noun_chunks" => [...]}
  """

  require Logger

  @python_path "python3.13"
  @script_path Path.join("thunderhelm", "nlp_cli.py")

  # -- Public API ---------------------------------------------------------------

  @doc """
  Extract named entities from text.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")

  ## Returns
    * `{:ok, result}` - Success with entities list
    * `{:error, reason}` - Failure

  ## Example
      {:ok, result} = NLP.extract_entities("Microsoft bought GitHub in 2018.")
      # result["entities"] = [
      #   %{"text" => "Microsoft", "label" => "ORG", "start" => 0, "end" => 9},
      #   %{"text" => "GitHub", "label" => "ORG", "start" => 17, "end" => 23},
      #   %{"text" => "2018", "label" => "DATE", "start" => 27, "end" => 31}
      # ]
  """
  @spec extract_entities(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract_entities(text, opts \\ []) when is_binary(text) do
    call_python("extract_entities", [text, Enum.into(opts, %{})])
  end

  @doc """
  Tokenize text with detailed linguistic features.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")

  ## Returns
    * `{:ok, result}` - Success with tokens list
    * `{:error, reason}` - Failure
  """
  @spec tokenize(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def tokenize(text, opts \\ []) when is_binary(text) do
    call_python("tokenize", [text, Enum.into(opts, %{})])
  end

  @doc """
  Analyze text sentiment (basic implementation).

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")

  ## Returns
    * `{:ok, result}` - Success with sentiment analysis
    * `{:error, reason}` - Failure
  """
  @spec analyze_sentiment(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_sentiment(text, opts \\ []) when is_binary(text) do
    call_python("analyze_sentiment", [text, Enum.into(opts, %{})])
  end

  @doc """
  Analyze syntactic structure of text.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")

  ## Returns
    * `{:ok, result}` - Success with noun chunks and sentences
    * `{:error, reason}` - Failure
  """
  @spec analyze_syntax(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_syntax(text, opts \\ []) when is_binary(text) do
    call_python("analyze_syntax", [text, Enum.into(opts, %{})])
  end

  @doc """
  Full NLP processing pipeline.

  ## Options
    * `:model_name` - Spacy model to use (default: "en_core_web_sm")
    * `:include_entities` - Include entity extraction (default: true)
    * `:include_tokens` - Include tokenization (default: false)
    * `:include_sentiment` - Include sentiment analysis (default: true)
    * `:include_syntax` - Include syntax analysis (default: true)

  ## Returns
    * `{:ok, result}` - Success with comprehensive NLP analysis
    * `{:error, reason}` - Failure
  """
  @spec process(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def process(text, opts \\ []) when is_binary(text) do
    call_python("process_text", [text, Enum.into(opts, %{})])
  end

  # -- Internal Helpers ---------------------------------------------------------

  defp call_python(function, args) do
    request = Jason.encode!(%{function: function, args: args})
    
    Logger.debug("NLP Request: #{request}")

    # Spawn Python process
    python_cmd = System.find_executable(@python_path)
    Logger.debug("Python executable: #{inspect(python_cmd)}")
    Logger.debug("Script path: #{@script_path}")
    Logger.debug("Working dir: #{File.cwd!()}")
    
    port = Port.open({:spawn_executable, python_cmd}, [
      :binary,
      :exit_status,
      {:args, [@script_path]},
      {:cd, File.cwd!()},
      :stderr_to_stdout
    ])
    
    Logger.debug("Port opened: #{inspect(port)}")

    # Send request to stdin (with newline for readline())
    Port.command(port, request <> "\n")
    Logger.debug("Request sent to port")
    
    # Receive output and exit code
    # Note: Port will auto-close when the Python process exits
    receive_output(port, "", nil)
  end

  defp receive_output(port, output, exit_code) do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("Received data from port: #{inspect(data)}")
        # Accumulate output
        receive_output(port, output <> data, exit_code)

      {^port, {:exit_status, code}} ->
        Logger.debug("Received exit status: #{code}, output: #{inspect(output)}")
        # Process exited, check if we have all the output
        if output != "" do
          # Process the result immediately
          process_result(output, code)
        else
          # Wait a bit for any remaining output
          receive_output(port, output, code)
        end
    after
      5000 ->
        Logger.warning("Timeout in receive_output. Exit code: #{inspect(exit_code)}, Output: #{inspect(output)}")
        # Timeout after 5 seconds
        if exit_code != nil do
          # We have exit code, process what we got
          process_result(output, exit_code)
        else
          {:error, {:timeout, output}}
        end
    end
  end

  defp process_result(output, exit_code) do
    case exit_code do
      0 ->
        # Extract JSON line from output (last line starting with '{')
        # Python may output INFO logs before the JSON response
        json_line = 
          output
          |> String.split("\n")
          |> Enum.reverse()
          |> Enum.find("", fn line -> 
            String.starts_with?(String.trim(line), "{")
          end)
        
        if json_line == "" do
          {:error, {:no_json_found, output}}
        else
          case Jason.decode(json_line) do
            {:ok, %{"error" => error}} ->
              {:error, error}
            {:ok, result} ->
              {:ok, result}
            {:error, reason} ->
              {:error, {:json_decode_failed, reason, output}}
          end
        end

      code ->
        Logger.error("[NLP] Python script failed (exit #{code}): #{output}")
        {:error, {:python_failed, code, output}}
    end
  end
end
