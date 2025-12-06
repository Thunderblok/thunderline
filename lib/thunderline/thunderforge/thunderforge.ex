defmodule Thunderline.Thunderforge do
  @moduledoc """
  Thunderforge — The Blacksmith Domain (#11 in Pantheon)

  Compilers, lexers, parsers, encoders, and learning tools.
  Where we shape code, data, and models before they enter the lattice.

  ## Submodules

  - `Thunderforge.Lex` — NimbleParsec grammars for ThunderDSL
  - `Thunderforge.Parser` — Builds IR AST from tokens
  - `Thunderforge.IR` — Intermediate representation structs
  - `Thunderforge.Encoder` — Turns IR into Thunderbolt/Thundercore configs
  - `Thunderforge.Compiler` — Orchestration entrypoint
  - `Thunderforge.Learn` — Tuning, HPO, rule fitting (absorbed from Thunderlearn)
  - `Thunderforge.Somatic` — Embeddings and affective tagging

  ## ThunderDSL v0.1

  A minimal DSL for configuring automata:

      automaton :my_ca do
        type :ca
        neighborhood :moore
        states [:dead, :alive]

        rule do
          born [3]
          survive [2, 3]
        end

        metrics do
          emit :clustering
          emit :entropy
        end

        bind :input, "thunderflow.events.sensor"
        bind :output, "thunderflow.events.state"
      end

  ## Compilation Pipeline

  1. Text → Tokens via `Thunderforge.Lex`
  2. Tokens → IR via `Thunderforge.Parser`
  3. IR → Runtime Configs via `Thunderforge.Encoder`
  4. Validation & Optimization in `Thunderforge.Compiler`

  ## Reference

  - THUNDERDSL_SPECIFICATION.md for full language spec
  - HC Orders: Operation TIGER LATTICE
  """

  alias Thunderline.Thunderforge.{Compiler, Learn}

  @doc """
  Compile ThunderDSL source to automata configuration.

  Returns `{:ok, config}` or `{:error, reason}`.

  ## Options

  - `:target` - Target backend (`:thunderbolt`, `:thundercore`, `:all`)
  - `:validate` - Run validation pass (default: true)
  - `:optimize` - Run optimization pass (default: true)

  ## Examples

      iex> Thunderforge.compile("automaton :test do type :ca end")
      {:ok, %{type: :ca, ...}}
  """
  @spec compile(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate compile(source, opts \\ []), to: Compiler

  @doc """
  Parse ThunderDSL source to IR without encoding.

  Useful for inspection and debugging.
  """
  @spec parse(String.t()) :: {:ok, struct()} | {:error, term()}
  defdelegate parse(source), to: Compiler

  @doc """
  Tune automata rules using hyperparameter optimization.

  Delegates to `Thunderforge.Learn.tune/3`.
  """
  @spec tune(map(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate tune(rule_config, training_data, opts \\ []), to: Learn
end
