defmodule Thunderline.Thundervine.SpecParser do
  @moduledoc """
  DAG spec parser (v0.1) using NimbleParsec for future extensibility (branches & conditionals).

  Grammar (simplified):
    spec        <- ws? workflow_decl nl node_line* ws? EOF
    workflow_decl <- 'workflow' ws name
    node_line   <- 'node' ws ident (ws attr)* nl?
    attr        <- ident '=' value
    value       <- bare_token | quoted

  Required: one workflow header & >=0 node lines.

  Node attributes:
    kind=task|llm|action (default: task)
    ref=<Module.Ref or arbitrary>
    after=a,b,c (comma list) - validated against previously declared node names

  Emits: %{name: wf_name, nodes: [%{name, kind, ref, after: []}]}
  Validation: unknown after reference returns {:error, {:unknown_after, ref, line}}
  """

  import NimbleParsec

  @type node_spec :: %{name: String.t(), kind: String.t(), ref: String.t(), after: [String.t()], line: pos_integer()}
  @type workflow_spec :: %{name: String.t(), nodes: [node_spec()]}

  ws = ignore(repeat(choice([string(" "), string("\t")])) )
  ident = ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?., ?-], min: 1)
  name = ident

  workflow_decl = ignore(string("workflow")) |> concat(ws) |> concat(name) |> tag(:workflow)

  key = ident
  value = ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?., ?:, ?-, ?/], min: 1)
  attr = key |> ignore(string("=")) |> concat(value) |> tag(:attr)

  after_attr = ignore(string("after=")) |> concat(value) |> tag(:after_raw)

  node_line =
    ignore(string("node"))
    |> concat(ws)
    |> concat(ident |> tag(:node_name))
    |> repeat(ws |> concat(choice([after_attr, attr])))
    |> tag(:node)

  newline = choice([string("\n"), string("\r\n"), string("\r")])

  parser =
    ws
    |> concat(workflow_decl)
    |> concat(optional(newline))
    |> repeat(ws |> concat(node_line) |> concat(optional(newline)))
    |> ignore(optional(ws))
    |> eos()

  defparsec :raw, parser

  @spec parse(String.t()) :: {:ok, workflow_spec()} | {:error, term()}
  def parse(text) do
    case raw(text) do
      {:ok, parts, _, _, _, _} -> build(parts)
      {:error, reason, rest, _, {line, _col}, _} -> {:error, %{message: reason, rest: rest, line: line}}
    end
  end

  defp build(parts) do
    wf_name = Enum.find_value(parts, fn {:workflow, name} -> name; _ -> nil end)
    node_parts = Enum.filter(parts, &match?({:node, _}, &1))

    {nodes, _seen} =
      Enum.map_reduce(node_parts, MapSet.new(), fn {:node, node_tokens}, seen ->
        {name, attrs} = extract_node(node_tokens)
        after_refs = Map.get(attrs, :after, [])
        unknown = Enum.find(after_refs, fn ref -> not MapSet.member?(seen, ref) end)
        if unknown do
          throw({:error, {:unknown_after, unknown, Map.get(attrs, :line, 0)}})
        end
        node = %{
          name: name,
          kind: Map.get(attrs, :kind, "task"),
          ref: Map.get(attrs, :ref, name),
          after: after_refs,
          line: Map.get(attrs, :line, 0)
        }
        {node, MapSet.put(seen, name)}
      end)

    {:ok, %{name: wf_name, nodes: nodes}}
  catch
    {:error, reason} -> {:error, reason}
  end

  defp extract_node(tokens) do
    # tokens like [node_name: "fetch", attr: ["kind","task"], after_raw: "a,b"]
    name = Enum.find_value(tokens, fn {:node_name, n} -> n; _ -> nil end)
    attrs = Enum.reduce(tokens, %{line: line_from(tokens)}, fn
      {:attr, [k, v]}, acc -> Map.put(acc, String.to_atom(k), v)
      {:after_raw, list}, acc -> Map.put(acc, :after, String.split(list, ",", trim: true))
      _, acc -> acc
    end)
    {name, attrs}
  end

  defp line_from(_tokens), do: 0 # NimbleParsec line metadata available in error path; for success we skip for now
end
