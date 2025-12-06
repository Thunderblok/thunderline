defmodule Thunderline.Thunderforge.Compiler do
  @moduledoc """
  ThunderDSL Compiler — Orchestration entrypoint for the compilation pipeline.

  Coordinates:
  1. Lexing (source → tokens)
  2. Parsing (tokens → IR)
  3. Validation (IR → validated IR)
  4. Optimization (optional IR transforms)
  5. Encoding (IR → runtime configs)

  ## Usage

      # Full compilation
      {:ok, config} = Compiler.compile("automaton :my_ca do ... end")

      # Parse only (for inspection)
      {:ok, ir} = Compiler.parse("automaton :my_ca do ... end")

      # Compile with options
      {:ok, config} = Compiler.compile(source, target: :thunderbolt, optimize: true)

  ## Telemetry

  Emits telemetry events for each compilation stage:
  - `[:thunderforge, :compile, :start]`
  - `[:thunderforge, :compile, :stop]`
  - `[:thunderforge, :lex, :stop]`
  - `[:thunderforge, :parse, :stop]`
  - `[:thunderforge, :validate, :stop]`
  - `[:thunderforge, :encode, :stop]`
  """

  require Logger

  alias Thunderline.Thunderforge.{Lex, Parser, IR, Encoder}

  @type compile_opts :: [
          target: :thunderbolt | :thundercore | :thunderflow | :all,
          validate: boolean(),
          optimize: boolean()
        ]

  @doc """
  Compile ThunderDSL source to runtime configuration.

  ## Options

  - `:target` - Which domain configs to generate (default: `:all`)
  - `:validate` - Run validation pass (default: `true`)
  - `:optimize` - Run optimization pass (default: `true`)

  ## Returns

  - `{:ok, config}` - Compilation succeeded
  - `{:error, {:lex_error, details}}` - Lexer failed
  - `{:error, {:parse_error, details}}` - Parser failed
  - `{:error, {:validation_error, reasons}}` - Validation failed
  - `{:error, {:encode_error, details}}` - Encoding failed
  """
  @spec compile(String.t(), compile_opts()) :: {:ok, map()} | {:error, term()}
  def compile(source, opts \\ []) when is_binary(source) do
    start_time = System.monotonic_time()

    emit_telemetry(:start, %{source_size: byte_size(source)})

    result =
      with {:ok, tokens} <- lex(source),
           {:ok, ir} <- parse(tokens),
           :ok <- maybe_validate(ir, opts),
           ir <- maybe_optimize(ir, opts),
           {:ok, config} <- encode(ir, opts) do
        {:ok, config}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, config} ->
        emit_telemetry(:stop, %{duration: duration, success: true})
        {:ok, config}

      {:error, reason} ->
        emit_telemetry(:stop, %{duration: duration, success: false, error: reason})
        {:error, reason}
    end
  end

  @doc """
  Parse ThunderDSL source to IR without encoding.

  Useful for inspection and debugging.
  """
  @spec parse(String.t() | [tuple()]) :: {:ok, IR.Automaton.t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    with {:ok, tokens} <- lex(source) do
      parse(tokens)
    end
  end

  def parse(tokens) when is_list(tokens) do
    start_time = System.monotonic_time()

    result = Parser.parse(tokens)

    duration = System.monotonic_time() - start_time
    emit_telemetry(:parse, %{duration: duration, token_count: length(tokens)})

    case result do
      {:ok, ir} -> {:ok, ir}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Lex ThunderDSL source into tokens.
  """
  @spec lex(String.t()) :: {:ok, [tuple()]} | {:error, term()}
  def lex(source) when is_binary(source) do
    start_time = System.monotonic_time()

    result = Lex.tokenize(source)

    duration = System.monotonic_time() - start_time
    emit_telemetry(:lex, %{duration: duration, source_size: byte_size(source)})

    case result do
      {:ok, tokens} -> {:ok, tokens}
      {:error, reason} -> {:error, {:lex_error, reason}}
    end
  end

  @doc """
  Validate IR for correctness.
  """
  @spec validate(IR.Automaton.t()) :: :ok | {:error, term()}
  def validate(%IR.Automaton{} = ir) do
    start_time = System.monotonic_time()

    result = IR.validate(ir)

    duration = System.monotonic_time() - start_time
    emit_telemetry(:validate, %{duration: duration})

    case result do
      :ok -> :ok
      {:error, reasons} -> {:error, {:validation_error, reasons}}
    end
  end

  @doc """
  Encode IR to runtime configuration.
  """
  @spec encode(IR.Automaton.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def encode(%IR.Automaton{} = ir, opts \\ []) do
    start_time = System.monotonic_time()

    result = Encoder.encode(ir, opts)

    duration = System.monotonic_time() - start_time
    emit_telemetry(:encode, %{duration: duration, target: Keyword.get(opts, :target, :all)})

    case result do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end

  @doc """
  Compile from Elixir DSL form (macro-based).

  Allows defining automata using Elixir syntax:

      Compiler.from_dsl do
        automaton :my_ca do
          type :ca
          rule do
            born [3]
            survive [2, 3]
          end
        end
      end
  """
  defmacro from_dsl(do: block) do
    # This is a placeholder for future macro-based DSL
    # For now, we just return the block as-is
    quote do
      # TODO: Implement macro DSL expansion
      {:dsl, unquote(Macro.escape(block))}
    end
  end

  @doc """
  Quick compile helper for simple CA rules in B/S notation.

  ## Example

      {:ok, config} = Compiler.quick_ca(:game_of_life, "B3/S23")
  """
  @spec quick_ca(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def quick_ca(name, rule_string, opts \\ []) do
    # Parse B#/S# notation
    case parse_bs_notation(rule_string) do
      {:ok, born, survive} ->
        source = """
        automaton #{inspect(name)} do
          type :ca
          neighborhood :moore
          states [:dead, :alive]

          rule do
            born #{inspect(born)}
            survive #{inspect(survive)}
          end

          metrics do
            emit :clustering
            emit :entropy
          end
        end
        """

        compile(source, opts)

      {:error, reason} ->
        {:error, {:invalid_rule_string, reason}}
    end
  end

  # Parse B3/S23 notation
  defp parse_bs_notation(str) when is_binary(str) do
    str = String.upcase(str)

    case Regex.run(~r/B(\d*)\/?S(\d*)/, str, capture: :all_but_first) do
      [born_str, survive_str] ->
        born = born_str |> String.graphemes() |> Enum.map(&String.to_integer/1)
        survive = survive_str |> String.graphemes() |> Enum.map(&String.to_integer/1)
        {:ok, born, survive}

      nil ->
        {:error, "expected B#/S# format"}
    end
  end

  # Conditional validation
  defp maybe_validate(ir, opts) do
    if Keyword.get(opts, :validate, true) do
      validate(ir)
    else
      :ok
    end
  end

  # Conditional optimization (placeholder for future optimizations)
  defp maybe_optimize(ir, opts) do
    if Keyword.get(opts, :optimize, true) do
      optimize(ir)
    else
      ir
    end
  end

  # Optimization pass (placeholder)
  defp optimize(%IR.Automaton{} = ir) do
    # Future optimizations:
    # - Dead code elimination in rule definitions
    # - Metric deduplication
    # - Binding validation and optimization
    ir
  end

  # Telemetry emission
  defp emit_telemetry(stage, metadata) do
    :telemetry.execute(
      [:thunderforge, :compile, stage],
      %{system_time: System.system_time()},
      metadata
    )
  rescue
    # Telemetry might not be available in all contexts
    _ -> :ok
  end
end
