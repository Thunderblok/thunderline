defmodule Thunderline.Forge.FileScanner do
  @moduledoc """
  Thunderforge-lite File Scanner

  Walks directories and emits file descriptors for processing.
  Pure Elixir implementation using Task.async_stream for concurrency.

  ## Architecture

  ```
  FileScanner.stream(root)
       │
       ▼
  %FileDescriptor{path, kind, size, mtime}
       │
       ▼
  Parser.parse(descriptor)
       │
       ▼
  Thundercell persistence
  ```

  ## Usage

  ```elixir
  # Stream all supported files from a directory
  Thunderline.Forge.FileScanner.stream("/path/to/repo")
  |> Stream.each(&IO.inspect/1)
  |> Stream.run()

  # Get list of descriptors
  {:ok, descriptors} = Thunderline.Forge.FileScanner.scan("/path/to/repo")
  ```
  """

  @type file_kind :: :text | :markdown | :log | :json | :code | :unknown

  @type file_descriptor :: %{
          path: String.t(),
          kind: file_kind(),
          size: non_neg_integer(),
          mtime: DateTime.t() | nil,
          extension: String.t(),
          relative_path: String.t()
        }

  # Supported extensions and their kinds
  @extension_mapping %{
    # Text
    ".txt" => :text,
    ".text" => :text,
    # Markdown
    ".md" => :markdown,
    ".mdx" => :markdown,
    ".markdown" => :markdown,
    # Logs
    ".log" => :log,
    # JSON
    ".json" => :json,
    ".jsonl" => :json,
    ".ndjson" => :json,
    # Code - Elixir
    ".ex" => :code,
    ".exs" => :code,
    # Code - Other
    ".py" => :code,
    ".js" => :code,
    ".ts" => :code,
    ".tsx" => :code,
    ".jsx" => :code,
    ".rb" => :code,
    ".go" => :code,
    ".rs" => :code,
    ".c" => :code,
    ".h" => :code,
    ".cpp" => :code,
    ".hpp" => :code,
    ".java" => :code,
    ".kt" => :code,
    ".swift" => :code,
    ".sh" => :code,
    ".bash" => :code,
    ".zsh" => :code,
    ".fish" => :code,
    # Config as code
    ".yaml" => :code,
    ".yml" => :code,
    ".toml" => :code,
    ".xml" => :code,
    ".html" => :code,
    ".css" => :code,
    ".scss" => :code,
    ".less" => :code,
    ".sql" => :code,
    ".graphql" => :code,
    ".gql" => :code
  }

  @default_extensions Map.keys(@extension_mapping)
  @default_max_concurrency 8
  @default_max_file_size 10 * 1024 * 1024  # 10MB

  @doc """
  Stream file descriptors from a directory.

  Returns a Stream that yields file descriptors as they're discovered.
  Uses Task.async_stream for concurrent file stat operations.

  ## Options

    * `:extensions` - List of extensions to include (default: all supported)
    * `:max_concurrency` - Max concurrent stat operations (default: 8)
    * `:max_file_size` - Skip files larger than this (default: 10MB)
    * `:include_hidden` - Include hidden files/directories (default: false)
    * `:exclude_patterns` - List of glob patterns to exclude

  ## Examples

      iex> Thunderline.Forge.FileScanner.stream("/path/to/repo")
      #Stream<...>

      iex> stream("/path", extensions: [".ex", ".exs"], max_concurrency: 4)
      #Stream<...>
  """
  @spec stream(String.t(), keyword()) :: Enumerable.t()
  def stream(root, opts \\ []) do
    extensions = Keyword.get(opts, :extensions, @default_extensions)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    max_file_size = Keyword.get(opts, :max_file_size, @default_max_file_size)
    include_hidden = Keyword.get(opts, :include_hidden, false)
    exclude_patterns = Keyword.get(opts, :exclude_patterns, default_excludes())

    root = Path.expand(root)

    root
    |> find_files(extensions, include_hidden, exclude_patterns)
    |> Task.async_stream(
      fn path -> build_descriptor(path, root, max_file_size) end,
      max_concurrency: max_concurrency,
      ordered: false
    )
    |> Stream.filter(fn
      {:ok, {:ok, _descriptor}} -> true
      _ -> false
    end)
    |> Stream.map(fn {:ok, {:ok, descriptor}} -> descriptor end)
  end

  @doc """
  Scan a directory and return all file descriptors.

  This is the eager version of `stream/2`.

  ## Examples

      iex> {:ok, descriptors} = Thunderline.Forge.FileScanner.scan("/path/to/repo")
      iex> length(descriptors)
      42
  """
  @spec scan(String.t(), keyword()) :: {:ok, [file_descriptor()]} | {:error, term()}
  def scan(root, opts \\ []) do
    descriptors =
      root
      |> stream(opts)
      |> Enum.to_list()

    {:ok, descriptors}
  rescue
    e -> {:error, e}
  end

  @doc """
  Build a file descriptor for a single file.

  ## Examples

      iex> {:ok, desc} = Thunderline.Forge.FileScanner.describe("/path/to/file.ex")
      iex> desc.kind
      :code
  """
  @spec describe(String.t()) :: {:ok, file_descriptor()} | {:error, term()}
  def describe(path) do
    path = Path.expand(path)
    root = Path.dirname(path)
    build_descriptor(path, root, @default_max_file_size)
  end

  @doc """
  Get the file kind for an extension.

  ## Examples

      iex> Thunderline.Forge.FileScanner.kind_for_extension(".ex")
      :code

      iex> Thunderline.Forge.FileScanner.kind_for_extension(".md")
      :markdown
  """
  @spec kind_for_extension(String.t()) :: file_kind()
  def kind_for_extension(ext) do
    Map.get(@extension_mapping, String.downcase(ext), :unknown)
  end

  @doc """
  List all supported extensions.
  """
  @spec supported_extensions() :: [String.t()]
  def supported_extensions, do: @default_extensions

  # Private functions

  defp find_files(root, extensions, include_hidden, exclude_patterns) do
    glob_pattern = build_glob_pattern(extensions)

    root
    |> Path.join(glob_pattern)
    |> Path.wildcard()
    |> Stream.reject(fn path ->
      should_exclude?(path, root, include_hidden, exclude_patterns)
    end)
  end

  defp build_glob_pattern(extensions) do
    ext_list =
      extensions
      |> Enum.map(&String.trim_leading(&1, "."))
      |> Enum.join(",")

    "**/*.{#{ext_list}}"
  end

  defp should_exclude?(path, root, include_hidden, exclude_patterns) do
    relative = Path.relative_to(path, root)
    parts = Path.split(relative)

    cond do
      # Check hidden files/directories
      not include_hidden and Enum.any?(parts, &hidden?/1) ->
        true

      # Check exclude patterns
      matches_exclude_pattern?(relative, exclude_patterns) ->
        true

      true ->
        false
    end
  end

  defp hidden?(part) do
    String.starts_with?(part, ".")
  end

  defp matches_exclude_pattern?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      # Simple glob matching
      case pattern do
        "**/node_modules/**" ->
          String.contains?(path, "node_modules/")

        "**/deps/**" ->
          String.contains?(path, "deps/")

        "**/_build/**" ->
          String.contains?(path, "_build/")

        "**/.elixir_ls/**" ->
          String.contains?(path, ".elixir_ls/")

        "**/.git/**" ->
          String.contains?(path, ".git/")

        "**/vendor/**" ->
          String.contains?(path, "vendor/")

        "**/__pycache__/**" ->
          String.contains?(path, "__pycache__/")

        "**/.cache/**" ->
          String.contains?(path, ".cache/")

        _ ->
          # Fallback to regex matching for custom patterns
          try do
            regex = pattern_to_regex(pattern)
            Regex.match?(regex, path)
          rescue
            _ -> false
          end
      end
    end)
  end

  defp pattern_to_regex(pattern) do
    pattern
    |> String.replace("**", ".*")
    |> String.replace("*", "[^/]*")
    |> String.replace("?", ".")
    |> then(&Regex.compile!/1)
  end

  defp default_excludes do
    [
      "**/node_modules/**",
      "**/deps/**",
      "**/_build/**",
      "**/.elixir_ls/**",
      "**/.git/**",
      "**/vendor/**",
      "**/__pycache__/**",
      "**/.cache/**"
    ]
  end

  defp build_descriptor(path, root, max_file_size) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{size: size}} when size > max_file_size ->
        {:error, :file_too_large}

      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        extension = Path.extname(path)
        kind = kind_for_extension(extension)
        relative_path = Path.relative_to(path, root)

        mtime_datetime =
          case DateTime.from_unix(mtime) do
            {:ok, dt} -> dt
            _ -> nil
          end

        descriptor = %{
          path: path,
          kind: kind,
          size: size,
          mtime: mtime_datetime,
          extension: extension,
          relative_path: relative_path
        }

        {:ok, descriptor}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
