defmodule Thunderline.Thunderforge.Lex do
  @moduledoc """
  ThunderDSL Lexer using NimbleParsec.

  Tokenizes ThunderDSL source into a stream of tokens for the parser.

  ## Token Types

  - `:keyword` — Reserved words (automaton, type, rule, etc.)
  - `:identifier` — Names and references
  - `:atom` — Atom literals (:foo)
  - `:integer` — Integer literals
  - `:float` — Float literals
  - `:string` — Quoted strings
  - `:list_start` / `:list_end` — List delimiters
  - `:block_start` / `:block_end` — do/end
  - `:comma` — List separator
  - `:newline` — Significant newlines

  ## Example

      iex> Lex.tokenize("automaton :my_ca do")
      {:ok, [
        {:keyword, "automaton", {1, 1}},
        {:atom, :my_ca, {1, 11}},
        {:block_start, "do", {1, 18}}
      ]}
  """

  import NimbleParsec

  # Whitespace (not newlines - those are significant)
  ws = ignore(ascii_string([?\s, ?\t], min: 1))
  optional_ws = optional(ws)

  # Newlines (significant for statement separation)
  newline =
    choice([string("\r\n"), string("\n"), string("\r")])
    |> replace(:newline)
    |> label("newline")

  # Comments (ignore to end of line)
  comment =
    string("#")
    |> repeat(lookahead_not(choice([string("\n"), eos()])) |> utf8_char([]))
    |> ignore()

  # Keywords
  keyword =
    choice([
      string("automaton"),
      string("type"),
      string("neighborhood"),
      string("states"),
      string("dimensions"),
      string("rule"),
      string("metrics"),
      string("bind"),
      string("emit"),
      string("born"),
      string("survive"),
      string("nca_config"),
      string("ising_config"),
      string("perception"),
      string("update_rule"),
      string("hidden_channels"),
      string("cell_fire_rate"),
      string("step_size"),
      string("algorithm"),
      string("temperature"),
      string("coupling"),
      string("schedule"),
      string("sample_rate"),
      string("buffer_size"),
      string("transform"),
      string("reversible"),
      string("ternary"),
      string("true"),
      string("false")
    ])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({:keyword_token, []})

  # Block delimiters
  block_start =
    string("do")
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> replace({:block_start, "do"})

  block_end =
    string("end")
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> replace({:block_end, "end"})

  # Atom literal (:foo, :foo_bar, :FooBar)
  atom_literal =
    ignore(string(":"))
    |> concat(ascii_string([?a..?z, ?A..?Z, ?_, ?0..?9], min: 1))
    |> reduce({:atom_token, []})

  # Identifier (foo, foo_bar, FooBar, Foo.Bar.Baz)
  identifier =
    ascii_string([?a..?z, ?A..?Z, ?_], 1)
    |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?.], min: 1))
    |> reduce({:identifier_token, []})

  # Integer literal
  integer_literal =
    optional(ascii_char([?-, ?+]))
    |> concat(ascii_string([?0..?9], min: 1))
    |> reduce({:integer_token, []})

  # Float literal
  float_literal =
    optional(ascii_char([?-, ?+]))
    |> concat(ascii_string([?0..?9], min: 1))
    |> concat(string("."))
    |> concat(ascii_string([?0..?9], min: 1))
    |> reduce({:float_token, []})

  # String literal (double-quoted)
  string_literal =
    ignore(string("\""))
    |> repeat(
      lookahead_not(string("\""))
      |> choice([
        string("\\\"") |> replace(?"),
        string("\\n") |> replace(?\n),
        string("\\t") |> replace(?\t),
        string("\\\\") |> replace(?\\),
        utf8_char([])
      ])
    )
    |> ignore(string("\""))
    |> reduce({:string_token, []})

  # List delimiters
  list_start = string("[") |> replace({:list_start, "["})
  list_end = string("]") |> replace({:list_end, "]"})

  # Punctuation
  comma = string(",") |> replace({:comma, ","})

  # Single token (order matters - more specific first)
  token =
    choice([
      comment,
      newline,
      block_start,
      block_end,
      keyword,
      atom_literal,
      float_literal,
      integer_literal,
      string_literal,
      list_start,
      list_end,
      comma,
      identifier
    ])

  # Full tokenizer
  tokenizer =
    optional_ws
    |> repeat(token |> concat(optional_ws))
    |> eos()

  defparsec(:tokenize_raw, tokenizer)

  @doc """
  Tokenize ThunderDSL source into token stream.

  Returns `{:ok, tokens}` or `{:error, reason}`.
  """
  @spec tokenize(String.t()) :: {:ok, [tuple()]} | {:error, term()}
  def tokenize(source) when is_binary(source) do
    case tokenize_raw(source) do
      {:ok, tokens, "", %{}, {line, col}, _} ->
        {:ok, add_positions(tokens, line, col)}

      {:ok, tokens, rest, %{}, {line, col}, _} ->
        {:error, %{message: "unexpected input", rest: rest, line: line, col: col, tokens: tokens}}

      {:error, reason, rest, %{}, {line, col}, _} ->
        {:error, %{message: reason, rest: rest, line: line, col: col}}
    end
  end

  # Token constructors (called via reduce)
  def keyword_token(chars) when is_list(chars) do
    word = IO.iodata_to_binary(chars)
    {:keyword, word}
  end

  def atom_token(chars) when is_list(chars) do
    atom = chars |> IO.iodata_to_binary() |> String.to_atom()
    {:atom, atom}
  end

  def identifier_token(chars) when is_list(chars) do
    {:identifier, IO.iodata_to_binary(chars)}
  end

  def integer_token(chars) when is_list(chars) do
    int = chars |> IO.iodata_to_binary() |> String.to_integer()
    {:integer, int}
  end

  def float_token(chars) when is_list(chars) do
    float = chars |> IO.iodata_to_binary() |> String.to_float()
    {:float, float}
  end

  def string_token(chars) when is_list(chars) do
    {:string, IO.iodata_to_binary(chars)}
  end

  # Add position info to tokens (simplified - tracks based on newlines)
  defp add_positions(tokens, _final_line, _final_col) do
    {positioned, _line, _col} =
      Enum.reduce(tokens, {[], 1, 1}, fn
        :newline, {acc, line, _col} ->
          {[{:newline, line} | acc], line + 1, 1}

        {type, value}, {acc, line, col} ->
          {[{type, value, {line, col}} | acc], line, col + token_width(type, value)}

        other, {acc, line, col} ->
          {[{:unknown, other, {line, col}} | acc], line, col}
      end)

    Enum.reverse(positioned)
  end

  defp token_width(:keyword, word), do: String.length(word)
  defp token_width(:identifier, name), do: String.length(name)
  defp token_width(:atom, atom), do: String.length(Atom.to_string(atom)) + 1
  defp token_width(:integer, _), do: 1
  defp token_width(:float, _), do: 1
  defp token_width(:string, str), do: String.length(str) + 2
  defp token_width(_, _), do: 1
end
