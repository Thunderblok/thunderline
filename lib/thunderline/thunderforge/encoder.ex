defmodule Thunderline.Thunderforge.Encoder do
  @moduledoc """
  ThunderDSL Encoder — Transforms IR into runtime configurations.

  Takes validated IR and produces configs consumable by:
  - Thunderbolt CA/NCA stepper
  - Thundercore reward/tick system
  - Thunderflow event bindings

  ## Output Structure

      %{
        thunderbolt: %{
          type: :ca,
          rule_config: %{born: [3], survive: [2, 3], ...},
          stepper_opts: %{...}
        },
        thundercore: %{
          metrics: [:clustering, :entropy],
          reward_config: %{...}
        },
        thunderflow: %{
          bindings: [%{direction: :input, stream: "..."}]
        }
      }
  """

  alias Thunderline.Thunderforge.IR

  @type encoded :: %{
          thunderbolt: map(),
          thundercore: map(),
          thunderflow: map(),
          metadata: map()
        }

  @doc """
  Encode validated IR into runtime configuration.

  Returns `{:ok, config}` or `{:error, reason}`.
  """
  @spec encode(IR.Automaton.t(), keyword()) :: {:ok, encoded()} | {:error, term()}
  def encode(%IR.Automaton{} = ir, opts \\ []) do
    target = Keyword.get(opts, :target, :all)

    config = %{
      thunderbolt: encode_thunderbolt(ir, target),
      thundercore: encode_thundercore(ir, target),
      thunderflow: encode_thunderflow(ir, target),
      metadata: %{
        name: ir.name,
        type: ir.type,
        encoded_at: DateTime.utc_now(),
        version: "0.1.0"
      }
    }

    {:ok, config}
  end

  # Encode Thunderbolt CA/NCA/Ising configuration
  defp encode_thunderbolt(%IR.Automaton{} = ir, target) when target in [:all, :thunderbolt] do
    base = %{
      type: ir.type,
      name: ir.name,
      neighborhood: ir.neighborhood,
      dimensions: ir.dimensions,
      states: encode_states(ir.states)
    }

    case ir.type do
      :ca -> Map.merge(base, encode_ca_rule(ir.rule))
      :nca -> Map.merge(base, encode_nca_config(ir.nca_config))
      :ising -> Map.merge(base, encode_ising_config(ir.ising_config))
      :hybrid -> Map.merge(base, encode_hybrid(ir))
    end
  end

  defp encode_thunderbolt(_ir, _target), do: %{}

  defp encode_states(states) when is_list(states), do: %{discrete: states}
  defp encode_states(:ternary), do: %{ternary: [:neg, :zero, :pos]}
  defp encode_states({:ternary, _}), do: %{ternary: [:neg, :zero, :pos]}
  defp encode_states({:continuous, min, max}), do: %{continuous: {min, max}}
  defp encode_states(other), do: %{raw: other}

  defp encode_ca_rule(nil), do: %{rule_config: nil}

  defp encode_ca_rule(%IR.Rule{} = rule) do
    %{
      rule_config: %{
        born: rule.born,
        survive: rule.survive,
        reversible: rule.reversible,
        ternary: rule.ternary,
        update_fn: rule.update_fn,
        rule_module: rule.rule_module
      },
      # Map to existing RuleParser struct format for compatibility
      rule_spec: %{
        born: rule.born,
        survive: rule.survive,
        rate_hz: Map.get(rule.metadata, :rate_hz, 30),
        seed: Map.get(rule.metadata, :seed),
        zone: Map.get(rule.metadata, :zone)
      }
    }
  end

  defp encode_nca_config(nil), do: %{nca_config: nil}

  defp encode_nca_config(%IR.NCAConfig{} = config) do
    %{
      nca_config: %{
        perception: config.perception,
        update_rule: config.update_rule,
        hidden_channels: config.hidden_channels,
        cell_fire_rate: config.cell_fire_rate,
        step_size: config.step_size,
        living_threshold: config.living_threshold
      },
      # Reference to rule module for stepper
      rule_module: config.update_rule,
      rule_backend: :nca
    }
  end

  defp encode_ising_config(nil), do: %{ising_config: nil}

  defp encode_ising_config(%IR.IsingConfig{} = config) do
    %{
      ising_config: %{
        algorithm: config.algorithm,
        temperature: config.temperature,
        coupling_strength: config.coupling_strength,
        external_field: config.external_field,
        schedule: config.schedule,
        num_replicas: config.num_replicas
      },
      rule_backend: :ising
    }
  end

  defp encode_hybrid(%IR.Automaton{rule: rule, nca_config: nca, ising_config: ising}) do
    %{
      rule_config: if(rule, do: encode_ca_rule(rule).rule_config, else: nil),
      nca_config: if(nca, do: encode_nca_config(nca).nca_config, else: nil),
      ising_config: if(ising, do: encode_ising_config(ising).ising_config, else: nil),
      rule_backend: :hybrid
    }
  end

  # Encode Thundercore metrics and reward configuration
  defp encode_thundercore(%IR.Automaton{} = ir, target) when target in [:all, :thundercore] do
    %{
      metrics: encode_metrics(ir.metrics),
      reward_config: %{
        automaton_name: ir.name,
        automaton_type: ir.type,
        # Side-quest metrics that contribute to reward
        side_quest_metrics: ir.metrics.emit,
        # Sampling configuration
        sample_rate: ir.metrics.sample_rate,
        buffer_size: ir.metrics.buffer_size
      }
    }
  end

  defp encode_thundercore(_ir, _target), do: %{}

  defp encode_metrics(%IR.Metrics{} = metrics) do
    %{
      emit: Enum.reverse(metrics.emit),
      sample_rate: metrics.sample_rate,
      buffer_size: metrics.buffer_size,
      # Map metric names to telemetry event names
      telemetry_events:
        Enum.map(metrics.emit, fn metric ->
          {metric, [:thunderbolt, :automata, :metric, metric]}
        end)
    }
  end

  # Encode Thunderflow event bindings
  defp encode_thunderflow(%IR.Automaton{} = ir, target) when target in [:all, :thunderflow] do
    %{
      bindings:
        Enum.map(Enum.reverse(ir.bindings), fn binding ->
          %{
            direction: binding.direction,
            name: binding.name,
            stream: binding.stream,
            transform: binding.transform
          }
        end),
      # Generate Broadway/GenStage wiring hints
      producers:
        ir.bindings
        |> Enum.filter(&(&1.direction == :input))
        |> Enum.map(& &1.stream),
      consumers:
        ir.bindings
        |> Enum.filter(&(&1.direction == :output))
        |> Enum.map(& &1.stream)
    }
  end

  defp encode_thunderflow(_ir, _target), do: %{}

  @doc """
  Encode IR to format compatible with existing Thunderbolt.CA.Stepper.

  Returns a map that can be passed directly to stepper functions.
  """
  @spec to_stepper_config(IR.Automaton.t()) :: map()
  def to_stepper_config(%IR.Automaton{type: :ca} = ir) do
    %{
      born: ir.rule.born,
      survive: ir.rule.survive,
      neighborhood: ir.neighborhood,
      dimensions: ir.dimensions,
      reversible: ir.rule.reversible,
      ternary: ir.rule.ternary
    }
  end

  def to_stepper_config(%IR.Automaton{type: :nca} = ir) do
    %{
      rule_module: ir.nca_config.update_rule,
      perception: ir.nca_config.perception,
      hidden_channels: ir.nca_config.hidden_channels,
      cell_fire_rate: ir.nca_config.cell_fire_rate,
      step_size: ir.nca_config.step_size
    }
  end

  def to_stepper_config(%IR.Automaton{type: :ising} = ir) do
    %{
      algorithm: ir.ising_config.algorithm,
      temperature: ir.ising_config.temperature,
      coupling: ir.ising_config.coupling_strength,
      schedule: ir.ising_config.schedule
    }
  end

  @doc """
  Generate a RuleParser-compatible struct from IR.

  For backwards compatibility with existing CA infrastructure.
  """
  @spec to_rule_parser_struct(IR.Automaton.t()) :: struct()
  def to_rule_parser_struct(%IR.Automaton{type: :ca, rule: rule}) do
    # Match the struct from Thunderbolt.CA.RuleParser
    %{
      __struct__: Thunderline.Thunderbolt.CA.RuleParser,
      born: rule.born,
      survive: rule.survive,
      rate_hz: Map.get(rule.metadata, :rate_hz, 30),
      seed: Map.get(rule.metadata, :seed),
      zone: Map.get(rule.metadata, :zone),
      rest: nil
    }
  end
end
