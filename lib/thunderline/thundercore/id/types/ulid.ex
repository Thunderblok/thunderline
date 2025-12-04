defmodule Thunderline.Thundercore.Id.Types.ULID do
  @moduledoc """
  Ash.Type implementation for ULID (Universally Unique Lexicographically Sortable Identifier).

  This type integrates ULIDs with Ash resources, providing:
  - Automatic casting from string/binary
  - Database storage as `:uuid` (Postgres uuid column) or `:string` (char(26))
  - Generator integration for StreamData property testing
  - Validation of ULID format

  ## Usage in Resources

  For time-sortable primary keys:

      defmodule MyApp.Thunderbit do
        use Ash.Resource,
          domain: MyApp.Domain,
          data_layer: AshPostgres.DataLayer

        attributes do
          attribute :id, Thunderline.Id.Types.ULID do
            primary_key? true
            allow_nil? false
            default &Thunderline.Id.generate/0
            writable? true
          end

          # ... other attributes
        end
      end

  For foreign keys and references:

      relationships do
        belongs_to :session, MyApp.Session do
          attribute_type Thunderline.Id.Types.ULID
        end
      end

  ## Storage Modes

  By default, ULIDs are stored as binary (compatible with Postgres `uuid` column).
  For char(26) storage, configure in your resource:

      postgres do
        table "my_table"
        repo MyRepo

        custom_indexes do
          index [:id], using: "btree"
        end
      end

  ## See Also

  - `Thunderline.Id` - Main ULID generation and parsing API
  - `Ecto.ULID` - Underlying Ecto type implementation
  """

  use Ash.Type

  @impl Ash.Type
  def storage_type(_constraints), do: :binary_id

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_binary(value) do
    case Ecto.ULID.cast(value) do
      {:ok, ulid} -> {:ok, ulid}
      :error -> {:error, message: "must be a valid ULID"}
    end
  end

  def cast_input(_, _constraints), do: {:error, message: "must be a string"}

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  # Handle binary from database (uuid column stores as 16-byte binary)
  def cast_stored(value, _constraints) when is_binary(value) and byte_size(value) == 16 do
    case Ecto.ULID.load(value) do
      {:ok, ulid} -> {:ok, ulid}
      :error -> {:error, message: "invalid ULID binary"}
    end
  end

  # Handle string from database (char(26) column)
  def cast_stored(value, _constraints) when is_binary(value) and byte_size(value) == 26 do
    {:ok, String.upcase(value)}
  end

  def cast_stored(_, _constraints), do: {:error, message: "invalid stored value"}

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) when is_binary(value) do
    case Ecto.ULID.dump(value) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, message: "cannot dump invalid ULID"}
    end
  end

  def dump_to_native(_, _constraints), do: {:error, message: "must be a string"}

  @impl Ash.Type
  def generator(_constraints) do
    StreamData.constant(Thunderline.Id.generate())
  end

  @impl Ash.Type
  def embedded?, do: false

  @doc """
  Get the constraints for this type.

  ULID type doesn't use additional constraints beyond format validation.
  """
  @impl Ash.Type
  def constraints, do: []

  @impl Ash.Type
  def apply_constraints(value, _constraints), do: {:ok, value}

  @impl Ash.Type
  def describe(_constraints) do
    "A ULID (Universally Unique Lexicographically Sortable Identifier)"
  end
end
