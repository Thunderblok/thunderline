defmodule Thunderline.Forge.Parser do
  @moduledoc """
  Thunderforge-lite Parser

  Parses files into Thundercell chunks based on content type.
  Uses NimbleParsec for structured parsing (logs, JSON schemas).

  ## Chunking Strategy

  - **Text/Markdown**: Chunk by paragraphs or sections (# headers)
  - **Logs**: Each line or structured log entry = 1 cell
  - **JSON**: Top-level objects/arrays or schema-aware chunking
  - **Code**: Functions, modules, classes as chunks

  ## Usage

  ```elixir
  # Parse a file descriptor into cells
  {:ok, cells} = Thunderline.Forge.Parser.parse(file_descriptor)

  # Parse raw content with explicit kind
  {:ok, cells} = Thunderline.Forge.Parser.parse_content(content, :markdown)
  ```
  """

  import NimbleParsec

  alias Thunderline.Forge.FileScanner

  # Default chunk size for text splitting (characters)
  @default_chunk_size 1000
  @default_overlap 100

  # Log line parsers using NimbleParsec
  # ISO timestamp: 2024-12-06T10:30:45.123Z
  iso_timestamp =
    integer(4)
    |> ignore(string("-"))
    |> integer(2)
    |> ignore(string("-"))
    |> integer(2)
    |> ignore(string("T"))
    |> integer(2)
    |> ignore(string(":"))
    |> integer(2)
    |> ignore(string(":"))
    |> integer(2)
    |> optional(
      ignore(string("."))
      |> integer(min: 1, max: 6)
    )
    |> optional(
      choice([
        string("Z"),
        string("+") |> integer(2) |> ignore(string(":")) |> integer(2),
        string("-") |> integer(2) |> ignore(string(":")) |> integer(2)
      ])
    )
    |> tag(:timestamp)

  # Common log timestamp: Dec 06 10:30:45
  syslog_timestamp =
    ascii_string([?A..?Z, ?a..?z], 3)
    |> ignore(string(" "))
    |> integer(min: 1, max: 2)
    |> ignore(string(" "))
    |> integer(2)
    |> ignore(string(":"))
    |> integer(2)
    |> ignore(string(":"))
    |> integer(2)
    |> tag(:timestamp)

  # Log level
  log_level =
    choice([
      string("DEBUG") |> replace(:debug),
      string("INFO") |> replace(:info),
      string("WARN") |> replace(:warn),
      string("WARNING") |> replace(:warn),
      string("ERROR") |> replace(:error),
      string("FATAL") |> replace(:fatal),
      string("TRACE") |> replace(:trace),
      # Lowercase variants
      string("debug") |> replace(:debug),
      string("info") |> replace(:info),
      string("warn") |> replace(:warn),
      string("warning") |> replace(:warn),
      string("error") |> replace(:error),
      string("fatal") |> replace(:fatal),
      string("trace") |> replace(:trace)
    ])
    |> tag(:level)

  # Bracketed level: [INFO], [ERROR]
  bracketed_level =
    ignore(string("["))
    |> concat(log_level)
    |> ignore(string("]"))

  # Rest of line (message)
  rest_of_line =
    optional(ignore(ascii_char([?\s, ?\t, ?-, ?:, ?|])))
    |> utf8_string([], min: 0)
    |> tag(:message)

  # Combined log line parser
  defparsec(
    :parse_log_line,
    optional(choice([iso_timestamp, syslog_timestamp]))
    |> optional(ignore(ascii_char([?\s, ?\t, ?-, ?|])))
    |> optional(choice([bracketed_level, log_level]))
    |> concat(rest_of_line)
  )

  @doc """
  Parse a file descriptor into Thundercell-compatible maps.

  Returns a list of cell data maps ready for Thundercell.create/1.

  ## Options

    * `:chunk_size` - Max characters per chunk for text (default: 1000)
    * `:overlap` - Character overlap between chunks (default: 100)

  ## Examples

      {:ok, cells} = Parser.parse(%{path: "foo.md", kind: :markdown, ...})
  """
  @spec parse(FileScanner.file_descriptor(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def parse(descriptor, opts \\ []) do
    %{path: path, kind: kind} = descriptor

    case File.read(path) do
      {:ok, content} ->
        cells = parse_content(content, kind, path, opts)
        {:ok, cells}

      {:error, reason} ->
        {:error, {:read_error, path, reason}}
    end
  end

  @doc """
  Parse raw content with explicit kind.

  ## Examples

      cells = Parser.parse_content("# Hello\\nWorld", :markdown, "inline.md")
  """
  @spec parse_content(String.t(), FileScanner.file_kind(), String.t(), keyword()) :: [map()]
  def parse_content(content, kind, source, opts \\ [])

  def parse_content(content, :markdown, source, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)

    content
    |> split_markdown_sections()
    |> Enum.flat_map(fn {section_title, section_content, line_start} ->
      chunk_text(section_content, chunk_size, overlap)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, idx} ->
        %{
          source: source,
          kind: :markdown,
          raw: chunk,
          span: %{
            line_start: line_start,
            section: section_title,
            chunk_index: idx
          },
          structure: %{
            section_title: section_title,
            chunk_of: Enum.count(chunk_text(section_content, chunk_size, overlap))
          },
          labels: [],
          meta: %{}
        }
      end)
    end)
  end

  def parse_content(content, :text, source, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)

    content
    |> chunk_text(chunk_size, overlap)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      %{
        source: source,
        kind: :text,
        raw: chunk,
        span: %{chunk_index: idx},
        structure: %{},
        labels: [],
        meta: %{}
      }
    end)
  end

  def parse_content(content, :log, source, _opts) do
    content
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_num} ->
      parsed = parse_log_line_safe(line)

      %{
        source: source,
        kind: :log,
        raw: line,
        span: %{line: line_num},
        structure: parsed,
        labels: log_level_label(parsed),
        meta: %{}
      }
    end)
  end

  def parse_content(content, :json, source, _opts) do
    case Jason.decode(content) do
      {:ok, data} when is_list(data) ->
        # JSON array - each element is a cell
        data
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} ->
          %{
            source: source,
            kind: :json,
            raw: Jason.encode!(item),
            span: %{array_index: idx},
            structure: extract_json_schema(item),
            labels: [],
            meta: %{}
          }
        end)

      {:ok, data} when is_map(data) ->
        # Single JSON object
        [
          %{
            source: source,
            kind: :json,
            raw: content,
            span: %{},
            structure: extract_json_schema(data),
            labels: [],
            meta: %{keys: Map.keys(data)}
          }
        ]

      {:error, _} ->
        # JSONL / NDJSON - line by line
        content
        |> String.split("\n", trim: true)
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> String.trim(line) != "" end)
        |> Enum.map(fn {line, line_num} ->
          case Jason.decode(line) do
            {:ok, data} ->
              %{
                source: source,
                kind: :json,
                raw: line,
                span: %{line: line_num},
                structure: extract_json_schema(data),
                labels: [],
                meta: %{}
              }

            {:error, _} ->
              %{
                source: source,
                kind: :json,
                raw: line,
                span: %{line: line_num},
                structure: %{parse_error: true},
                labels: [:parse_error],
                meta: %{}
              }
          end
        end)
    end
  end

  def parse_content(content, :code, source, _opts) do
    extension = Path.extname(source)

    case extension do
      ext when ext in [".ex", ".exs"] ->
        parse_elixir_code(content, source)

      ext when ext in [".py"] ->
        parse_python_code(content, source)

      _ ->
        # Generic code chunking by functions/blocks
        parse_generic_code(content, source)
    end
  end

  def parse_content(content, _kind, source, opts) do
    # Fallback to text parsing
    parse_content(content, :text, source, opts)
  end

  # Private helpers

  defp split_markdown_sections(content) do
    lines = String.split(content, "\n")

    {sections, current_title, current_lines, current_start} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil, [], 1}, fn {line, line_num}, {sections, title, lines, start} ->
        if String.match?(line, ~r/^#{1,6}\s+/) do
          # New section header
          section_title = String.replace(line, ~r/^#+\s*/, "")

          if title do
            section = {title, Enum.reverse(lines) |> Enum.join("\n"), start}
            {[section | sections], section_title, [], line_num}
          else
            {sections, section_title, [], line_num}
          end
        else
          {sections, title, [line | lines], start}
        end
      end)

    # Don't forget last section
    final_sections =
      if current_title do
        section = {current_title, Enum.reverse(current_lines) |> Enum.join("\n"), current_start}
        [section | sections]
      else
        if current_lines != [] do
          section = {"(untitled)", Enum.reverse(current_lines) |> Enum.join("\n"), current_start}
          [section | sections]
        else
          sections
        end
      end

    Enum.reverse(final_sections)
  end

  defp chunk_text(text, chunk_size, overlap) do
    text = String.trim(text)

    if String.length(text) <= chunk_size do
      [text]
    else
      do_chunk_text(text, chunk_size, overlap, [])
    end
  end

  defp do_chunk_text(text, chunk_size, overlap, acc) do
    if String.length(text) <= chunk_size do
      Enum.reverse([text | acc])
    else
      chunk = String.slice(text, 0, chunk_size)
      rest = String.slice(text, max(0, chunk_size - overlap)..-1//1)
      do_chunk_text(rest, chunk_size, overlap, [chunk | acc])
    end
  end

  defp parse_log_line_safe(line) do
    case parse_log_line(line) do
      {:ok, parsed, _, _, _, _} ->
        extract_log_parts(parsed)

      _ ->
        %{raw_message: line}
    end
  end

  defp extract_log_parts(parsed) do
    timestamp = Keyword.get(parsed, :timestamp)
    level = Keyword.get(parsed, :level)
    message = Keyword.get(parsed, :message, [""]) |> List.first()

    %{
      timestamp: timestamp,
      level: level && List.first(level),
      message: message && String.trim(message)
    }
  end

  defp log_level_label(%{level: level}) when level in [:error, :fatal], do: [:important]
  defp log_level_label(%{level: :warn}), do: [:needs_review]
  defp log_level_label(_), do: []

  defp extract_json_schema(data) when is_map(data) do
    schema =
      data
      |> Enum.map(fn {k, v} -> {k, type_of(v)} end)
      |> Enum.into(%{})

    %{type: :object, fields: schema}
  end

  defp extract_json_schema(data) when is_list(data) do
    element_types = Enum.map(data, &type_of/1) |> Enum.uniq()
    %{type: :array, element_types: element_types, length: length(data)}
  end

  defp extract_json_schema(data), do: %{type: type_of(data)}

  defp type_of(v) when is_binary(v), do: :string
  defp type_of(v) when is_integer(v), do: :integer
  defp type_of(v) when is_float(v), do: :float
  defp type_of(v) when is_boolean(v), do: :boolean
  defp type_of(nil), do: :null
  defp type_of(v) when is_map(v), do: :object
  defp type_of(v) when is_list(v), do: :array
  defp type_of(_), do: :unknown

  defp parse_elixir_code(content, source) do
    # Use Sourceror for proper Elixir AST parsing
    case Sourceror.parse_string(content) do
      {:ok, ast} ->
        extract_elixir_chunks(ast, content, source)

      {:error, _} ->
        # Fallback to generic parsing
        parse_generic_code(content, source)
    end
  end

  defp extract_elixir_chunks(ast, content, source) do
    # Walk AST and extract module/function definitions
    chunks = collect_elixir_definitions(ast, [])

    if chunks == [] do
      # No definitions found, chunk as generic
      parse_generic_code(content, source)
    else
      lines = String.split(content, "\n")

      Enum.map(chunks, fn {type, name, line_start, line_end} ->
        raw =
          lines
          |> Enum.slice((line_start - 1)..(line_end - 1)//1)
          |> Enum.join("\n")

        %{
          source: source,
          kind: :code,
          raw: raw,
          span: %{line_start: line_start, line_end: line_end},
          structure: %{
            language: :elixir,
            definition_type: type,
            name: to_string(name)
          },
          labels: [],
          meta: %{language: :elixir}
        }
      end)
    end
  end

  defp collect_elixir_definitions({:defmodule, meta, [name | _]} = _ast, acc) do
    line = Keyword.get(meta, :line, 1)
    end_line = Keyword.get(meta, :end, []) |> Keyword.get(:line, line)

    [{:module, extract_module_name(name), line, end_line} | acc]
  end

  defp collect_elixir_definitions({form, meta, [head | _]} = _ast, acc)
       when form in [:def, :defp] do
    line = Keyword.get(meta, :line, 1)
    end_line = Keyword.get(meta, :end, []) |> Keyword.get(:line, line)
    name = extract_function_name(head)

    [{form, name, line, end_line} | acc]
  end

  defp collect_elixir_definitions({_, _, children}, acc) when is_list(children) do
    Enum.reduce(children, acc, &collect_elixir_definitions/2)
  end

  defp collect_elixir_definitions(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_elixir_definitions/2)
  end

  defp collect_elixir_definitions(_, acc), do: acc

  defp extract_module_name({:__aliases__, _, parts}), do: Enum.join(parts, ".")
  defp extract_module_name(other), do: inspect(other)

  defp extract_function_name({name, _, _}) when is_atom(name), do: name
  defp extract_function_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_function_name(_), do: :unknown

  defp parse_python_code(content, source) do
    # Simple regex-based Python parsing
    lines = String.split(content, "\n")

    # Find def/class definitions
    definitions =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        String.match?(line, ~r/^\s*(def|class|async def)\s+\w+/)
      end)
      |> Enum.map(fn {line, line_num} ->
        cond do
          String.match?(line, ~r/^\s*class\s+/) ->
            name = Regex.run(~r/class\s+(\w+)/, line) |> List.last()
            {:class, name, line_num}

          String.match?(line, ~r/^\s*async def\s+/) ->
            name = Regex.run(~r/async def\s+(\w+)/, line) |> List.last()
            {:async_function, name, line_num}

          String.match?(line, ~r/^\s*def\s+/) ->
            name = Regex.run(~r/def\s+(\w+)/, line) |> List.last()
            {:function, name, line_num}

          true ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if definitions == [] do
      parse_generic_code(content, source)
    else
      # Create cells for each definition (simplified - just captures the definition line)
      Enum.map(definitions, fn {type, name, line_num} ->
        %{
          source: source,
          kind: :code,
          raw: Enum.at(lines, line_num - 1),
          span: %{line_start: line_num, line_end: line_num},
          structure: %{
            language: :python,
            definition_type: type,
            name: name
          },
          labels: [],
          meta: %{language: :python}
        }
      end)
    end
  end

  defp parse_generic_code(content, source) do
    # Split by blank lines or function-like patterns
    chunks =
      content
      |> String.split(~r/\n\n+/)
      |> Enum.reject(&(String.trim(&1) == ""))

    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      %{
        source: source,
        kind: :code,
        raw: chunk,
        span: %{chunk_index: idx},
        structure: %{language: :unknown},
        labels: [],
        meta: %{}
      }
    end)
  end
end
