defmodule Thunderline.Thunderforge.Domain do
  @moduledoc """
  Thunderforge Domain — The Blacksmith Domain (#11 in Pantheon)

  Compilers, lexers, parsers, encoders, and learning tools.
  Where we shape code, data, and models before they enter the lattice.

  ## Responsibilities

  - ThunderDSL compilation pipeline
  - Rule and automata configuration
  - Hyperparameter optimization
  - Model training integration

  ## Event Categories

  - `forge.compile.*` - Compilation events
  - `forge.learn.*` - Learning/tuning events
  - `forge.validate.*` - Validation events

  ## Components

  - `Thunderforge.Compiler` - DSL compilation orchestration
  - `Thunderforge.Lex` - Tokenization
  - `Thunderforge.Parser` - AST construction
  - `Thunderforge.Encoder` - Config generation
  - `Thunderforge.Learn` - HPO and rule fitting

  ## Reference

  - HC Orders: Operation TIGER LATTICE
  - THUNDERDSL_SPECIFICATION.md
  """

  use Ash.Domain,
    extensions: [AshAdmin.Domain],
    otp_app: :thunderline

  admin do
    show? true
  end

  # Resources will be added as we build persistent artifacts
  # For now, Thunderforge is primarily a functional module domain
  resources do
    # Future: CompiledArtifact, RuleDefinition, OptimizationRun
  end
end
