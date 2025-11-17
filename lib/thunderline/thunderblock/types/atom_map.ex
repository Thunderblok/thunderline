defmodule Thunderline.Thunderblock.Types.AtomMap do
  @moduledoc """
  Custom Ash type for preserving atoms in JSONB fields.

  PostgreSQL's JSONB type converts Elixir atoms to strings during serialization.
  This type preserves atoms by tagging them during storage and converting back on load.

  ## Storage Format
  Atoms are stored as: `%{"__atom__" => "value"}`

  ## Example
      # In schema:
      attribute :meta, Thunderline.Thunderblock.Types.AtomMap

      # Usage:
      %MyResource{meta: %{status: :active, type: :direct}}
      # Stored as: {"status": {"__atom__": "active"}, "type": {"__atom__": "direct"}}
      # Loaded as: %{status: :active, type: :direct}
  """

  use Ash.Type

  @atom_tag "__atom__"

  @impl Ash.Type
  def storage_type(_), do: :map

  @impl Ash.Type
  def cast_input(value, _constraints) when is_map(value), do: {:ok, value}
  def cast_input(_, _), do: :error

  @impl Ash.Type
  def cast_stored(value, _constraints) when is_map(value) do
    decoded = decode_atoms(value)
    {:ok, decoded}
  rescue
    _ -> :error
  end

  def cast_stored(_, _), do: :error

  @impl Ash.Type
  def dump_to_native(value, _constraints) when is_map(value) do
    encoded = encode_atoms(value)
    {:ok, encoded}
  rescue
    _ -> :error
  end

  def dump_to_native(_, _), do: :error

  # Recursively encode atoms in a data structure
  defp encode_atoms(value) when is_atom(value) and not is_nil(value) and not is_boolean(value) do
    %{@atom_tag => Atom.to_string(value)}
  end

  defp encode_atoms(value) when is_map(value) do
    Map.new(value, fn {k, v} ->
      {encode_key(k), encode_atoms(v)}
    end)
  end

  defp encode_atoms(value) when is_list(value) do
    Enum.map(value, &encode_atoms/1)
  end

  defp encode_atoms(value), do: value

  # Recursively decode atoms from a data structure
  defp decode_atoms(%{@atom_tag => atom_string}) when is_binary(atom_string) do
    String.to_existing_atom(atom_string)
  rescue
    ArgumentError -> String.to_atom(atom_string)
  end

  defp decode_atoms(value) when is_map(value) do
    # Check if this is an atom-tagged map first
    if Map.has_key?(value, @atom_tag) and map_size(value) == 1 do
      decode_atoms(value)
    else
      Map.new(value, fn {k, v} ->
        {decode_key(k), decode_atoms(v)}
      end)
    end
  end

  defp decode_atoms(value) when is_list(value) do
    Enum.map(value, &decode_atoms/1)
  end

  defp decode_atoms(value), do: value

  # Encode map keys - convert atoms to strings for storage
  defp encode_key(key) when is_atom(key) and not is_nil(key) and not is_boolean(key) do
    Atom.to_string(key)
  end

  defp encode_key(key), do: key

  # Decode map keys - try to convert to existing atoms, keep as strings if not found
  defp decode_key(key) when is_binary(key) do
    # Try to convert known keys to atoms, but keep unknown ones as strings
    # to avoid creating atoms dynamically
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end
  end

  defp decode_key(key), do: key
end
