defmodule Thunderline.Thunderforge.IR do
  @moduledoc """
  Intermediate Representation structs for ThunderDSL.

  These structs represent parsed ThunderDSL in a normalized form
  that can be validated, optimized, and encoded to runtime configs.

  ## IR Hierarchy

  - `IR.Automaton` — Top-level automaton definition
  - `IR.Rule` — Update rule specification
  - `IR.Metrics` — Side-quest metrics to emit
  - `IR.Binding` — IO stream bindings
  - `IR.NCAConfig` — Neural CA specific configuration
  - `IR.IsingConfig` — Ising machine specific configuration
  """

  # Define leaf nodes first (no dependencies on other IR nodes)

  defmodule Rule do
    @moduledoc "CA/NCA update rule IR node"

    @type t :: %__MODULE__{
            born: [non_neg_integer()],
            survive: [non_neg_integer()],
            update_fn: atom() | nil,
            rule_module: module() | nil,
            reversible: boolean(),
            ternary: boolean(),
            metadata: map()
          }

    defstruct born: [],
              survive: [],
              update_fn: nil,
              rule_module: nil,
              reversible: false,
              ternary: false,
              metadata: %{}
  end

  defmodule NCAConfig do
    @moduledoc "Neural Cellular Automaton configuration"

    @type t :: %__MODULE__{
            perception: atom(),
            update_rule: module(),
            hidden_channels: pos_integer(),
            cell_fire_rate: float(),
            step_size: float(),
            living_threshold: float(),
            metadata: map()
          }

    defstruct perception: :sobel,
              update_rule: nil,
              hidden_channels: 16,
              cell_fire_rate: 0.5,
              step_size: 1.0,
              living_threshold: 0.1,
              metadata: %{}
  end

  defmodule IsingConfig do
    @moduledoc "Ising machine configuration"

    @type t :: %__MODULE__{
            algorithm: :metropolis | :annealing | :parallel_tempering,
            temperature: float(),
            coupling_strength: float(),
            external_field: float(),
            schedule: atom() | nil,
            num_replicas: pos_integer(),
            metadata: map()
          }

    defstruct algorithm: :metropolis,
              temperature: 1.0,
              coupling_strength: 1.0,
              external_field: 0.0,
              schedule: :exponential,
              num_replicas: 1,
              metadata: %{}
  end

  defmodule Metrics do
    @moduledoc "Side-quest metrics configuration"

    @type metric_type ::
            :clustering
            | :entropy
            | :divergence
            | :sortedness
            | :phi_phase
            | :sigma_flow
            | :lambda_sensitivity
            | :healing_rate
            | :custom

    @type t :: %__MODULE__{
            emit: [metric_type()],
            sample_rate: pos_integer(),
            buffer_size: pos_integer(),
            custom_fns: [{atom(), function()}],
            metadata: map()
          }

    defstruct emit: [],
              sample_rate: 1,
              buffer_size: 100,
              custom_fns: [],
              metadata: %{}
  end

  defmodule Binding do
    @moduledoc "IO stream binding IR node"

    @type direction :: :input | :output | :bidirectional

    @type t :: %__MODULE__{
            direction: direction(),
            name: atom(),
            stream: String.t(),
            transform: atom() | nil,
            metadata: map()
          }

    defstruct direction: :input,
              name: nil,
              stream: nil,
              transform: nil,
              metadata: %{}
  end

  # Now define Automaton which depends on the above modules

  defmodule Automaton do
    @moduledoc "Top-level automaton IR node"

    alias Thunderline.Thunderforge.IR.{Rule, NCAConfig, IsingConfig, Metrics, Binding}

    @type automaton_type :: :ca | :nca | :ising | :hybrid
    @type neighborhood :: :moore | :von_neumann | :extended_moore | :custom

    @type t :: %__MODULE__{
            name: atom(),
            type: automaton_type(),
            neighborhood: neighborhood(),
            states: [atom()] | {:ternary, :neg | :zero | :pos} | {:continuous, float(), float()},
            dimensions: pos_integer(),
            rule: Rule.t() | nil,
            nca_config: NCAConfig.t() | nil,
            ising_config: IsingConfig.t() | nil,
            metrics: Metrics.t() | nil,
            bindings: [Binding.t()],
            metadata: map()
          }

    defstruct name: nil,
              type: :ca,
              neighborhood: :moore,
              states: [:dead, :alive],
              dimensions: 2,
              rule: nil,
              nca_config: nil,
              ising_config: nil,
              metrics: nil,
              bindings: [],
              metadata: %{}
  end

  # Convenience aliases for use in this module
  alias __MODULE__.{Automaton, Rule, NCAConfig, IsingConfig, Metrics, Binding}

  @doc """
  Create a new Automaton IR node.
  """
  @spec automaton(atom(), keyword()) :: Automaton.t()
  def automaton(name, opts \\ []) do
    %Automaton{
      name: name,
      type: Keyword.get(opts, :type, :ca),
      neighborhood: Keyword.get(opts, :neighborhood, :moore),
      states: Keyword.get(opts, :states, [:dead, :alive]),
      dimensions: Keyword.get(opts, :dimensions, 2),
      metrics: %Metrics{},
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a new Rule IR node for classic CA.
  """
  @spec rule(keyword()) :: Rule.t()
  def rule(opts \\ []) do
    %Rule{
      born: Keyword.get(opts, :born, []),
      survive: Keyword.get(opts, :survive, []),
      update_fn: Keyword.get(opts, :update_fn),
      rule_module: Keyword.get(opts, :rule_module),
      reversible: Keyword.get(opts, :reversible, false),
      ternary: Keyword.get(opts, :ternary, false)
    }
  end

  @doc """
  Create a new Metrics IR node.
  """
  @spec metrics(keyword()) :: Metrics.t()
  def metrics(opts \\ []) do
    %Metrics{
      emit: Keyword.get(opts, :emit, []),
      sample_rate: Keyword.get(opts, :sample_rate, 1),
      buffer_size: Keyword.get(opts, :buffer_size, 100)
    }
  end

  @doc """
  Create a new Binding IR node.
  """
  @spec binding(direction :: atom(), name :: atom(), stream :: String.t(), keyword()) ::
          Binding.t()
  def binding(direction, name, stream, opts \\ []) do
    %Binding{
      direction: direction,
      name: name,
      stream: stream,
      transform: Keyword.get(opts, :transform)
    }
  end

  @doc """
  Create a new NCAConfig IR node.
  """
  @spec nca_config(keyword()) :: NCAConfig.t()
  def nca_config(opts \\ []) do
    %NCAConfig{
      perception: Keyword.get(opts, :perception, :sobel),
      update_rule: Keyword.get(opts, :update_rule),
      hidden_channels: Keyword.get(opts, :hidden_channels, 16),
      cell_fire_rate: Keyword.get(opts, :cell_fire_rate, 0.5),
      step_size: Keyword.get(opts, :step_size, 1.0),
      living_threshold: Keyword.get(opts, :living_threshold, 0.1)
    }
  end

  @doc """
  Create a new IsingConfig IR node.
  """
  @spec ising_config(keyword()) :: IsingConfig.t()
  def ising_config(opts \\ []) do
    %IsingConfig{
      algorithm: Keyword.get(opts, :algorithm, :metropolis),
      temperature: Keyword.get(opts, :temperature, 1.0),
      coupling_strength: Keyword.get(opts, :coupling_strength, 1.0),
      external_field: Keyword.get(opts, :external_field, 0.0),
      schedule: Keyword.get(opts, :schedule, :exponential),
      num_replicas: Keyword.get(opts, :num_replicas, 1)
    }
  end

  @doc """
  Validate an IR tree for structural correctness.

  Returns `:ok` or `{:error, reasons}`.
  """
  @spec validate(Automaton.t()) :: :ok | {:error, [String.t()]}
  def validate(%Automaton{} = ir) do
    errors =
      []
      |> validate_name(ir)
      |> validate_type(ir)
      |> validate_rule(ir)
      |> validate_bindings(ir)

    case errors do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  defp validate_name(errors, %{name: nil}), do: ["automaton name is required" | errors]
  defp validate_name(errors, %{name: name}) when is_atom(name), do: errors
  defp validate_name(errors, _), do: ["automaton name must be an atom" | errors]

  defp validate_type(errors, %{type: type}) when type in [:ca, :nca, :ising, :hybrid], do: errors
  defp validate_type(errors, %{type: type}), do: ["unknown automaton type: #{type}" | errors]

  defp validate_rule(errors, %{type: :ca, rule: nil}),
    do: ["CA automaton requires a rule definition" | errors]

  defp validate_rule(errors, %{type: :nca, nca_config: nil}),
    do: ["NCA automaton requires nca_config" | errors]

  defp validate_rule(errors, %{type: :ising, ising_config: nil}),
    do: ["Ising automaton requires ising_config" | errors]

  defp validate_rule(errors, _), do: errors

  defp validate_bindings(errors, %{bindings: bindings}) do
    Enum.reduce(bindings, errors, fn
      %Binding{stream: nil}, acc -> ["binding stream is required" | acc]
      %Binding{name: nil}, acc -> ["binding name is required" | acc]
      _, acc -> acc
    end)
  end
end
