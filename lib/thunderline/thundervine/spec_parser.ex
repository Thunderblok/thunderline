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

  @type node_spec :: %{
          name: String.t(),
          kind: String.t(),
          ref: String.t(),
          after: [String.t()],
          line: pos_integer()
        }
  @type workflow_spec :: %{name: String.t(), nodes: [node_spec()]}

  ws = ignore(repeat(choice([string(" "), string("\t")])))
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

  defparsec(:raw, parser)

  @spec parse(String.t()) :: {:ok, workflow_spec()} | {:error, term()}
  def parse(text) do
    case raw(text) do
      {:ok, parts, _, _, _, _} ->
        build(parts)

      {:error, reason, rest, _, {line, _col}, _} ->
        {:error, %{message: reason, rest: rest, line: line}}
    end
  end

  defp build(parts) do
    wf_name =
      Enum.find_value(parts, fn
        {:workflow, name} -> normalize_token(name)
        _ -> nil
      end)

    node_parts = Enum.filter(parts, &match?({:node, _}, &1))

    nodes =
      Enum.map(node_parts, fn {:node, node_tokens} ->
        {name, attrs} = extract_node(node_tokens)

        %{
          name: name,
          kind: Map.get(attrs, :kind, "task"),
          ref: Map.get(attrs, :ref, name),
          after: Map.get(attrs, :after, []),
          line: Map.get(attrs, :line, 0)
        }
      end)

    # Validate that all :after references exist among defined node names (normalized)
    names = MapSet.new(Enum.map(nodes, fn n -> n.name |> String.trim() end))

    case Enum.find(nodes, fn %{after: after_refs} ->
           Enum.find(after_refs, fn ref ->
             ref_norm = ref |> String.trim()
             not MapSet.member?(names, ref_norm)
           end)
         end) do
      nil ->
        :ok

      %{after: after_refs, line: line} ->
        unknown = Enum.find(after_refs, fn ref -> not MapSet.member?(names, String.trim(ref)) end)
        throw({:error, {:unknown_after, unknown, line}})
    end

    {:ok, %{name: wf_name, nodes: nodes}}
  catch
    {:error, reason} -> {:error, reason}
  end

  defp extract_node(tokens) do
    # tokens like [node_name: "fetch", attr: ["kind","task"], after_raw: "a,b"]
    name =
      Enum.find_value(tokens, fn
        {:node_name, n} -> normalize_token(n)
        _ -> nil
      end)

    attrs =
      Enum.reduce(tokens, %{line: line_from(tokens)}, fn
        {:attr, kv}, acc when is_list(kv) ->
          [k, v] =
            case kv do
              [k, v] -> [normalize_token(k), normalize_token(v)]
              other -> other |> List.flatten() |> Enum.map(&normalize_token/1)
            end

          Map.put(acc, String.to_atom(k), v)

        # after_raw may be a binary or a single-element list; normalize then split
        {:after_raw, raw}, acc ->
          list = raw |> normalize_token() |> String.split(",", trim: true)
          Map.put(acc, :after, list)

        _, acc ->
          acc
      end)

    {name, attrs}
  end

  # NimbleParsec line metadata available in error path; for success we skip for now
  defp line_from(_tokens), do: 0

  # NimbleParsec can wrap captured binaries in single-element lists when tagged or repeated.
  # Ensure we always return a binary for downstream logic.
  defp normalize_token(value) when is_binary(value), do: value
  defp normalize_token([value]) when is_binary(value), do: value

  defp normalize_token(value) when is_list(value) do
    value
    |> List.flatten()
    |> Enum.map_join("", fn
      v when is_binary(v) -> v
      v when is_integer(v) -> <<v>>
      v -> to_string(v)
    end)
  end

  defp normalize_token(value), do: to_string(value)
end
