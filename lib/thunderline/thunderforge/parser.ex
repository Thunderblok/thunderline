defmodule Thunderline.Thunderforge.Parser do
  @moduledoc """
  ThunderDSL Parser — Builds IR AST from token stream.

  Consumes tokens from `Thunderforge.Lex` and produces IR structs.

  ## Grammar (EBNF-ish)

      program     := automaton+
      automaton   := 'automaton' ATOM 'do' body 'end'
      body        := statement*
      statement   := type_decl | neighborhood_decl | states_decl | dimensions_decl
                   | rule_block | metrics_block | nca_config_block | ising_config_block
                   | bind_stmt
      type_decl   := 'type' ATOM
      rule_block  := 'rule' 'do' rule_body 'end'
      rule_body   := (born_stmt | survive_stmt | option_stmt)*
      born_stmt   := 'born' list
      survive_stmt := 'survive' list
      metrics_block := 'metrics' 'do' metrics_body 'end'
      metrics_body  := emit_stmt*
      emit_stmt   := 'emit' ATOM
      bind_stmt   := 'bind' ATOM ',' STRING

  ## Example

      {:ok, ir} = Parser.parse([
        {:keyword, "automaton"},
        {:atom, :my_ca},
        {:block_start, "do"},
        {:keyword, "type"},
        {:atom, :ca},
        {:block_end, "end"}
      ])
  """

  alias Thunderline.Thunderforge.IR
  alias Thunderline.Thunderforge.IR.{NCAConfig, IsingConfig}

  @type token :: tuple()
  @type parse_result :: {:ok, IR.Automaton.t()} | {:error, term()}

  @doc """
  Parse token stream into IR.

  Returns `{:ok, %IR.Automaton{}}` or `{:error, reason}`.
  """
  @spec parse([token()]) :: parse_result()
  def parse(tokens) when is_list(tokens) do
    # Filter out newlines for simpler parsing (they're not significant in our grammar)
    tokens = Enum.reject(tokens, fn
      {:newline, _} -> true
      _ -> false
    end)

    case parse_automaton(tokens) do
      {:ok, ir, []} ->
        {:ok, ir}

      {:ok, _ir, remaining} ->
        {:error, {:unexpected_tokens, remaining}}

      {:error, _} = err ->
        err
    end
  end

  # Parse: automaton :name do ... end
  defp parse_automaton([{:keyword, "automaton", _} | rest]) do
    with {:ok, name, rest} <- expect_atom(rest),
         {:ok, rest} <- expect_block_start(rest),
         {:ok, ir, rest} <- parse_body(IR.automaton(name), rest),
         {:ok, rest} <- expect_block_end(rest) do
      {:ok, ir, rest}
    end
  end

  defp parse_automaton([{:keyword, "automaton"} | rest]) do
    # Token without position info
    with {:ok, name, rest} <- expect_atom(rest),
         {:ok, rest} <- expect_block_start(rest),
         {:ok, ir, rest} <- parse_body(IR.automaton(name), rest),
         {:ok, rest} <- expect_block_end(rest) do
      {:ok, ir, rest}
    end
  end

  defp parse_automaton([token | _]) do
    {:error, {:expected_automaton, token}}
  end

  defp parse_automaton([]) do
    {:error, :unexpected_eof}
  end

  # Parse body statements until we hit 'end'
  defp parse_body(ir, tokens) do
    case tokens do
      [{:block_end, _} | _] ->
        {:ok, ir, tokens}

      [{:block_end, _, _} | _] ->
        {:ok, ir, tokens}

      [] ->
        {:error, :unexpected_eof_in_body}

      _ ->
        case parse_statement(ir, tokens) do
          {:ok, ir, rest} -> parse_body(ir, rest)
          {:error, _} = err -> err
        end
    end
  end

  # Parse individual statements
  defp parse_statement(ir, [{:keyword, "type", _} | rest]) do
    parse_type(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "type"} | rest]) do
    parse_type(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "neighborhood", _} | rest]) do
    parse_neighborhood(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "neighborhood"} | rest]) do
    parse_neighborhood(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "states", _} | rest]) do
    parse_states(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "states"} | rest]) do
    parse_states(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "dimensions", _} | rest]) do
    parse_dimensions(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "dimensions"} | rest]) do
    parse_dimensions(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "rule", _} | rest]) do
    parse_rule_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "rule"} | rest]) do
    parse_rule_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "metrics", _} | rest]) do
    parse_metrics_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "metrics"} | rest]) do
    parse_metrics_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "bind", _} | rest]) do
    parse_bind(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "bind"} | rest]) do
    parse_bind(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "nca_config", _} | rest]) do
    parse_nca_config_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "nca_config"} | rest]) do
    parse_nca_config_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "ising_config", _} | rest]) do
    parse_ising_config_block(ir, rest)
  end

  defp parse_statement(ir, [{:keyword, "ising_config"} | rest]) do
    parse_ising_config_block(ir, rest)
  end

  defp parse_statement(_ir, [token | _]) do
    {:error, {:unexpected_statement, token}}
  end

  # type :ca | :nca | :ising | :hybrid
  defp parse_type(ir, tokens) do
    with {:ok, type_atom, rest} <- expect_atom(tokens) do
      {:ok, %{ir | type: type_atom}, rest}
    end
  end

  # neighborhood :moore | :von_neumann | ...
  defp parse_neighborhood(ir, tokens) do
    with {:ok, neighborhood, rest} <- expect_atom(tokens) do
      {:ok, %{ir | neighborhood: neighborhood}, rest}
    end
  end

  # states [:dead, :alive] or states :ternary
  defp parse_states(ir, tokens) do
    case tokens do
      [{:atom, atom, _} | rest] ->
        {:ok, %{ir | states: atom}, rest}

      [{:atom, atom} | rest] ->
        {:ok, %{ir | states: atom}, rest}

      [{:list_start, _} | _] ->
        with {:ok, atoms, rest} <- parse_atom_list(tokens) do
          {:ok, %{ir | states: atoms}, rest}
        end

      [{:list_start, _, _} | _] ->
        with {:ok, atoms, rest} <- parse_atom_list(tokens) do
          {:ok, %{ir | states: atoms}, rest}
        end

      [token | _] ->
        {:error, {:expected_states, token}}
    end
  end

  # dimensions 2
  defp parse_dimensions(ir, tokens) do
    with {:ok, dim, rest} <- expect_integer(tokens) do
      {:ok, %{ir | dimensions: dim}, rest}
    end
  end

  # rule do ... end
  defp parse_rule_block(ir, tokens) do
    with {:ok, rest} <- expect_block_start(tokens),
         {:ok, rule, rest} <- parse_rule_body(IR.rule(), rest),
         {:ok, rest} <- expect_block_end(rest) do
      {:ok, %{ir | rule: rule}, rest}
    end
  end

  defp parse_rule_body(rule, tokens) do
    case tokens do
      [{:block_end, _} | _] ->
        {:ok, rule, tokens}

      [{:block_end, _, _} | _] ->
        {:ok, rule, tokens}

      [{:keyword, "born", _} | rest] ->
        with {:ok, list, rest} <- parse_integer_list(rest) do
          parse_rule_body(%{rule | born: list}, rest)
        end

      [{:keyword, "born"} | rest] ->
        with {:ok, list, rest} <- parse_integer_list(rest) do
          parse_rule_body(%{rule | born: list}, rest)
        end

      [{:keyword, "survive", _} | rest] ->
        with {:ok, list, rest} <- parse_integer_list(rest) do
          parse_rule_body(%{rule | survive: list}, rest)
        end

      [{:keyword, "survive"} | rest] ->
        with {:ok, list, rest} <- parse_integer_list(rest) do
          parse_rule_body(%{rule | survive: list}, rest)
        end

      [{:keyword, "reversible", _} | rest] ->
        with {:ok, bool, rest} <- expect_boolean(rest) do
          parse_rule_body(%{rule | reversible: bool}, rest)
        end

      [{:keyword, "reversible"} | rest] ->
        with {:ok, bool, rest} <- expect_boolean(rest) do
          parse_rule_body(%{rule | reversible: bool}, rest)
        end

      [{:keyword, "ternary", _} | rest] ->
        with {:ok, bool, rest} <- expect_boolean(rest) do
          parse_rule_body(%{rule | ternary: bool}, rest)
        end

      [{:keyword, "ternary"} | rest] ->
        with {:ok, bool, rest} <- expect_boolean(rest) do
          parse_rule_body(%{rule | ternary: bool}, rest)
        end

      [token | _] ->
        {:error, {:unexpected_in_rule, token}}

      [] ->
        {:error, :unexpected_eof_in_rule}
    end
  end

  # metrics do ... end
  defp parse_metrics_block(ir, tokens) do
    with {:ok, rest} <- expect_block_start(tokens),
         {:ok, metrics, rest} <- parse_metrics_body(IR.metrics(), rest),
         {:ok, rest} <- expect_block_end(rest) do
      {:ok, %{ir | metrics: metrics}, rest}
    end
  end

  defp parse_metrics_body(metrics, tokens) do
    case tokens do
      [{:block_end, _} | _] ->
        {:ok, metrics, tokens}

      [{:block_end, _, _} | _] ->
        {:ok, metrics, tokens}

      [{:keyword, "emit", _} | rest] ->
        with {:ok, metric_name, rest} <- expect_atom(rest) do
          parse_metrics_body(%{metrics | emit: [metric_name | metrics.emit]}, rest)
        end

      [{:keyword, "emit"} | rest] ->
        with {:ok, metric_name, rest} <- expect_atom(rest) do
          parse_metrics_body(%{metrics | emit: [metric_name | metrics.emit]}, rest)
        end

      [{:keyword, "sample_rate", _} | rest] ->
        with {:ok, rate, rest} <- expect_integer(rest) do
          parse_metrics_body(%{metrics | sample_rate: rate}, rest)
        end

      [{:keyword, "sample_rate"} | rest] ->
        with {:ok, rate, rest} <- expect_integer(rest) do
          parse_metrics_body(%{metrics | sample_rate: rate}, rest)
        end

      [token | _] ->
        {:error, {:unexpected_in_metrics, token}}

      [] ->
        {:error, :unexpected_eof_in_metrics}
    end
  end

  # bind :input, "stream.name"
  defp parse_bind(ir, tokens) do
    with {:ok, direction, rest} <- expect_atom(tokens),
         {:ok, rest} <- expect_comma(rest),
         {:ok, stream, rest} <- expect_string(rest) do
      binding = IR.binding(direction, direction, stream)
      {:ok, %{ir | bindings: [binding | ir.bindings]}, rest}
    end
  end

  # nca_config do ... end (simplified)
  defp parse_nca_config_block(ir, tokens) do
    with {:ok, rest} <- expect_block_start(tokens),
         {:ok, config, rest} <- parse_nca_config_body(%NCAConfig{}, rest),
         {:ok, rest} <- expect_block_end(rest) do
      {:ok, %{ir | nca_config: config}, rest}
    end
  end

  defp parse_nca_config_body(config, tokens) do
    case tokens do
      [{:block_end, _} | _] -> {:ok, config, tokens}
      [{:block_end, _, _} | _] -> {:ok, config, tokens}
      # Add specific field parsers as needed
      [_ | rest] -> parse_nca_config_body(config, rest)
      [] -> {:error, :unexpected_eof_in_nca_config}
    end
  end

  # ising_config do ... end (simplified)
  defp parse_ising_config_block(ir, tokens) do
    with {:ok, rest} <- expect_block_start(tokens),
         {:ok, config, rest} <- parse_ising_config_body(%IsingConfig{}, rest),
         {:ok, rest} <- expect_block_end(rest) do
      {:ok, %{ir | ising_config: config}, rest}
    end
  end

  defp parse_ising_config_body(config, tokens) do
    case tokens do
      [{:block_end, _} | _] -> {:ok, config, tokens}
      [{:block_end, _, _} | _] -> {:ok, config, tokens}
      # Add specific field parsers as needed
      [_ | rest] -> parse_ising_config_body(config, rest)
      [] -> {:error, :unexpected_eof_in_ising_config}
    end
  end

  # Helper: parse [1, 2, 3]
  defp parse_integer_list([{:list_start, _} | rest]), do: parse_int_list_body([], rest)
  defp parse_integer_list([{:list_start, _, _} | rest]), do: parse_int_list_body([], rest)
  defp parse_integer_list([token | _]), do: {:error, {:expected_list, token}}

  defp parse_int_list_body(acc, [{:list_end, _} | rest]), do: {:ok, Enum.reverse(acc), rest}
  defp parse_int_list_body(acc, [{:list_end, _, _} | rest]), do: {:ok, Enum.reverse(acc), rest}

  defp parse_int_list_body(acc, [{:integer, n, _} | rest]),
    do: parse_int_list_body([n | acc], skip_comma(rest))

  defp parse_int_list_body(acc, [{:integer, n} | rest]),
    do: parse_int_list_body([n | acc], skip_comma(rest))

  defp parse_int_list_body(_acc, [token | _]), do: {:error, {:expected_integer_in_list, token}}

  # Helper: parse [:a, :b, :c]
  defp parse_atom_list([{:list_start, _} | rest]), do: parse_atom_list_body([], rest)
  defp parse_atom_list([{:list_start, _, _} | rest]), do: parse_atom_list_body([], rest)
  defp parse_atom_list([token | _]), do: {:error, {:expected_list, token}}

  defp parse_atom_list_body(acc, [{:list_end, _} | rest]), do: {:ok, Enum.reverse(acc), rest}
  defp parse_atom_list_body(acc, [{:list_end, _, _} | rest]), do: {:ok, Enum.reverse(acc), rest}

  defp parse_atom_list_body(acc, [{:atom, a, _} | rest]),
    do: parse_atom_list_body([a | acc], skip_comma(rest))

  defp parse_atom_list_body(acc, [{:atom, a} | rest]),
    do: parse_atom_list_body([a | acc], skip_comma(rest))

  defp parse_atom_list_body(_acc, [token | _]), do: {:error, {:expected_atom_in_list, token}}

  defp skip_comma([{:comma, _} | rest]), do: rest
  defp skip_comma([{:comma, _, _} | rest]), do: rest
  defp skip_comma(rest), do: rest

  # Expectation helpers
  defp expect_atom([{:atom, a, _} | rest]), do: {:ok, a, rest}
  defp expect_atom([{:atom, a} | rest]), do: {:ok, a, rest}
  defp expect_atom([token | _]), do: {:error, {:expected_atom, token}}
  defp expect_atom([]), do: {:error, :unexpected_eof}

  defp expect_integer([{:integer, n, _} | rest]), do: {:ok, n, rest}
  defp expect_integer([{:integer, n} | rest]), do: {:ok, n, rest}
  defp expect_integer([token | _]), do: {:error, {:expected_integer, token}}
  defp expect_integer([]), do: {:error, :unexpected_eof}

  defp expect_string([{:string, s, _} | rest]), do: {:ok, s, rest}
  defp expect_string([{:string, s} | rest]), do: {:ok, s, rest}
  defp expect_string([token | _]), do: {:error, {:expected_string, token}}
  defp expect_string([]), do: {:error, :unexpected_eof}

  defp expect_boolean([{:keyword, "true", _} | rest]), do: {:ok, true, rest}
  defp expect_boolean([{:keyword, "true"} | rest]), do: {:ok, true, rest}
  defp expect_boolean([{:keyword, "false", _} | rest]), do: {:ok, false, rest}
  defp expect_boolean([{:keyword, "false"} | rest]), do: {:ok, false, rest}
  defp expect_boolean([token | _]), do: {:error, {:expected_boolean, token}}
  defp expect_boolean([]), do: {:error, :unexpected_eof}

  defp expect_block_start([{:block_start, _} | rest]), do: {:ok, rest}
  defp expect_block_start([{:block_start, _, _} | rest]), do: {:ok, rest}
  defp expect_block_start([token | _]), do: {:error, {:expected_do, token}}
  defp expect_block_start([]), do: {:error, :unexpected_eof}

  defp expect_block_end([{:block_end, _} | rest]), do: {:ok, rest}
  defp expect_block_end([{:block_end, _, _} | rest]), do: {:ok, rest}
  defp expect_block_end([token | _]), do: {:error, {:expected_end, token}}
  defp expect_block_end([]), do: {:error, :unexpected_eof}

  defp expect_comma([{:comma, _} | rest]), do: {:ok, rest}
  defp expect_comma([{:comma, _, _} | rest]), do: {:ok, rest}
  defp expect_comma([token | _]), do: {:error, {:expected_comma, token}}
  defp expect_comma([]), do: {:error, :unexpected_eof}
end
