defmodule Thunderline.Id do
  @moduledoc """
  Unified ID generator for Thunderline using ULID (Universally Unique Lexicographically Sortable Identifier).

  ## Why ULID?

  ULIDs provide significant advantages over UUIDv4 for Thunderline's append-heavy, time-ordered workloads:

  - **Lexicographically sortable**: First 48 bits encode timestamp → newer IDs sort after older IDs
  - **128-bit like UUID**: Compatible with Postgres `uuid` column type  
  - **URL-safe, human-friendly**: `/pac/01KANDQMV608PBSMF7TM9T1WR4` vs messy UUIDv4
  - **Index-friendly**: B-tree inserts go to end (append), not random pages
  - **Implicit time encoding**: Infer creation time from ID without extra column

  ## Recommended Use Cases

  | Surface | ULID Fit | Rationale |
  |---------|----------|-----------|
  | Thunderbit IDs | ✅ Perfect | Time-ordered reasoning artifacts, replay-friendly |
  | Thundercell IDs | ✅ Perfect | Ingestion chunks, embeddings, dataset batches |
  | EliteEntry IDs | ✅ Perfect | Generational QD archive entries |
  | Event/Log IDs | ✅ Perfect | Append-only, chronological by nature |
  | PAC Session IDs | ✅ Good | Session timelines, debugging |
  | CA Tick/World IDs | ✅ Good | Snapshot ordering |
  | Trial/Run IDs | ✅ Good | Cerebros training runs |

  ## Usage

      # Generate a new ULID
      id = Thunderline.Id.generate()
      # => "01HZQKX3VGS8WQXJ7Y9ZBNFR4M"

      # Generate ULID for specific timestamp
      id = Thunderline.Id.generate_at(~U[2024-01-15 12:00:00Z])

      # Extract timestamp from ULID
      {:ok, datetime} = Thunderline.Id.timestamp("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")

      # Validate ULID format
      Thunderline.Id.valid?("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      # => true

  ## See Also

  - `Thunderline.Id.Generator` - Low-level generation with options
  - `Thunderline.Id.Parser` - Timestamp extraction and parsing
  - `Thunderline.Id.Types.ULID` - Ash.Type integration for resources
  """

  @type t :: String.t()
  @type ulid_binary :: <<_::128>>

  @doc """
  Generate a new ULID string.

  Uses the current system time as the timestamp component.

  ## Examples

      iex> id = Thunderline.Id.generate()
      iex> String.length(id)
      26

      iex> id1 = Thunderline.Id.generate()
      iex> id2 = Thunderline.Id.generate()
      iex> id2 >= id1
      true
  """
  @spec generate() :: t()
  defdelegate generate(), to: Thunderline.Id.Generator

  @doc """
  Generate a ULID for a specific timestamp.

  Useful for:
  - Creating IDs for historical events during migration
  - Testing with deterministic timestamps
  - Backdating records for replay scenarios

  ## Parameters

  - `datetime` - A `DateTime` struct to use as the timestamp component

  ## Examples

      iex> id = Thunderline.Id.generate_at(~U[2024-01-15 12:00:00Z])
      iex> {:ok, ts} = Thunderline.Id.timestamp(id)
      iex> DateTime.to_unix(ts, :millisecond)
      1705320000000
  """
  @spec generate_at(DateTime.t()) :: t()
  defdelegate generate_at(datetime), to: Thunderline.Id.Generator

  @doc """
  Generate a binary (16-byte) ULID.

  Useful for direct database storage or when working with binary protocols.

  ## Examples

      iex> bin = Thunderline.Id.generate_binary()
      iex> byte_size(bin)
      16
  """
  @spec generate_binary() :: ulid_binary()
  defdelegate generate_binary(), to: Thunderline.Id.Generator

  @doc """
  Extract the timestamp from a ULID string.

  Returns the embedded creation time as a `DateTime` struct.

  ## Examples

      iex> {:ok, dt} = Thunderline.Id.timestamp("01HZQKX3VG0000000000000000")
      iex> dt.year
      2024

      iex> Thunderline.Id.timestamp("invalid")
      {:error, :invalid_ulid}
  """
  @spec timestamp(t()) :: {:ok, DateTime.t()} | {:error, :invalid_ulid}
  defdelegate timestamp(ulid), to: Thunderline.Id.Parser

  @doc """
  Extract timestamp, raising on invalid ULID.

  ## Examples

      iex> dt = Thunderline.Id.timestamp!("01HZQKX3VG0000000000000000")
      iex> is_struct(dt, DateTime)
      true
  """
  @spec timestamp!(t()) :: DateTime.t()
  defdelegate timestamp!(ulid), to: Thunderline.Id.Parser

  @doc """
  Check if a string is a valid ULID.

  Validates both format (26 Crockford Base32 characters) and checksum/structure.

  ## Examples

      iex> Thunderline.Id.valid?("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      true

      iex> Thunderline.Id.valid?("not-a-ulid")
      false

      iex> Thunderline.Id.valid?(nil)
      false
  """
  @spec valid?(term()) :: boolean()
  defdelegate valid?(id), to: Thunderline.Id.Parser

  @doc """
  Convert a binary ULID to its string representation.

  ## Examples

      iex> bin = Thunderline.Id.generate_binary()
      iex> str = Thunderline.Id.to_string(bin)
      iex> String.length(str)
      26
  """
  @spec to_string(ulid_binary()) :: t()
  defdelegate to_string(binary), to: Thunderline.Id.Parser

  @doc """
  Convert a string ULID to its binary representation.

  ## Examples

      iex> {:ok, bin} = Thunderline.Id.to_binary("01HZQKX3VGS8WQXJ7Y9ZBNFR4M")
      iex> byte_size(bin)
      16
  """
  @spec to_binary(t()) :: {:ok, ulid_binary()} | {:error, :invalid_ulid}
  defdelegate to_binary(string), to: Thunderline.Id.Parser

  @doc """
  Compare two ULIDs chronologically.

  Returns:
  - `:lt` if first is older than second
  - `:eq` if same timestamp (random parts may differ)
  - `:gt` if first is newer than second

  Note: This compares only the timestamp portion. Two ULIDs generated in the
  same millisecond will return `:eq` even if their random portions differ.

  ## Examples

      iex> old = Thunderline.Id.generate_at(~U[2024-01-01 00:00:00Z])
      iex> new = Thunderline.Id.generate_at(~U[2024-06-01 00:00:00Z])
      iex> Thunderline.Id.compare_time(old, new)
      :lt
  """
  @spec compare_time(t(), t()) :: :lt | :eq | :gt
  defdelegate compare_time(ulid1, ulid2), to: Thunderline.Id.Parser

  @doc """
  Generate a range of ULIDs covering a time window.

  Useful for time-range queries: "all Thunderbits created between dates X and Y".

  Returns `{min_ulid, max_ulid}` where:
  - `min_ulid` has timestamp = start, random = all zeros
  - `max_ulid` has timestamp = end, random = all ones

  ## Examples

      iex> {min, max} = Thunderline.Id.range(~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z])
      iex> Thunderline.Id.compare_time(min, max)
      :lt
  """
  @spec range(DateTime.t(), DateTime.t()) :: {t(), t()}
  defdelegate range(start_dt, end_dt), to: Thunderline.Id.Generator
end
